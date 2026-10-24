import { env } from "cloudflare:workers";
import { getChatGPTUser } from "../app/chatgpt-auth";
import { AppError, PRODUCTS, SIGNS, VERSION, dateKey, dailyFor, safeCsv, validateOrder, type OrderInput, type Report } from "./domain";
import { generate, type GeneratorEnv } from "./generator";
import { makePdf } from "./pdf";
import { isLiveQr, qrSnapshot, validateQr, validatePaymentReport, transactionKey, type QrRow, type ManualRow, type QrSnapshot } from "./qr";
type Runtime=GeneratorEnv&{DB?:D1Database;BUCKET?:R2Bucket;PAYMENTS_MODE?:string;DEMO_ADMIN_ACCESS?:string;ADMIN_USER_IDS?:string};
const runtime=()=>env as Runtime;
const database=()=>{const db=runtime().DB;if(!db)throw new AppError("La base de datos todavía no está disponible.",503);return db;};
type Row={id:string;owner_id:string;request_key:string;fingerprint:string;product:string;amount:number;discount:number;currency:string;payload:string;payment_status:string;delivery_status:string;result:string|null;source:string|null;ai_cost:number;fee_estimate:number;referral_owner:string|null;marketing_consent:number;consent_version:string;created_at:string;paid_at:string|null;delivered_at:string|null;lease_until:string|null;attempts:number;error_code:string|null;mode:string};
const now=()=>new Date().toISOString();
const stmt=(sql:string,...args:unknown[])=>database().prepare(sql).bind(...args);
async function identity(req:Request){
 const account=await getChatGPTUser();if(account)return {id:account.userId,name:account.fullName||"Explorador/a",local:false};
 // Compile-time development branch: absent from production. No external OAuth/session stack.
 if(import.meta.env.DEV&&["terminal.local","127.0.0.1","localhost"].includes(new URL(req.url).hostname))return {id:"local-demo",name:"Explorador/a",local:true};
 throw new AppError("Iniciá sesión para guardar tu experiencia.",401);
}
const paymentMode=()=>runtime().PAYMENTS_MODE==="manual_qr"?"manual_qr":"demo";
const liveContentReady=()=>runtime().CONTENT_MODE==="openai"&&!!runtime().OPENAI_API_KEY;
async function admin(req:Request){
 const u=await identity(req),ids=(runtime().ADMIN_USER_IDS||"").split(",").map(s=>s.trim()).filter(Boolean);
 if(!u.local&&!ids.includes(u.id)&&!(paymentMode()==="demo"&&runtime().DEMO_ADMIN_ACCESS==="owner-private"))throw new AppError("Acceso administrativo no habilitado.",403);
 return u;
}
async function profile(id:string){await stmt("INSERT INTO profiles (id,referral_code,created_at) VALUES (?,?,?) ON CONFLICT(id) DO NOTHING",id,crypto.randomUUID().replaceAll("-","").slice(0,8).toUpperCase(),now()).run();return (await stmt("SELECT referral_code FROM profiles WHERE id=?",id).first<{referral_code:string}>())!;}
async function owned(id:string,owner:string){if(!/^[a-f0-9-]{36}$/.test(id))throw new AppError("Pedido no encontrado.",404);const row=await stmt("SELECT * FROM orders WHERE id=? AND owner_id=?",id,owner).first<Row>();if(!row)throw new AppError("Pedido no encontrado.",404);return row;}
function publicOrder(r:Row){return {id:r.id,product:r.product,amount:r.amount,discount:r.discount,currency:r.currency,payload:JSON.parse(r.payload),paymentStatus:r.payment_status,deliveryStatus:r.delivery_status,result:r.result&&JSON.parse(r.result),source:r.source,createdAt:r.created_at,paidAt:r.paid_at,deliveredAt:r.delivered_at,attempts:r.attempts,error:r.error_code,mode:r.mode};}
function mutation(req:Request){const origin=req.headers.get("origin");if(!origin||origin!==new URL(req.url).origin)throw new AppError("Origen de solicitud no permitido.",403);if(!req.headers.get("content-type")?.startsWith("application/json"))throw new AppError("Se requiere JSON.",415);}
async function body(req:Request,max=8000){
 const reader=req.body?.getReader();if(!reader)throw new AppError("Solicitud vacía.");let length=0;const parts:Uint8Array[]=[];
 while(true){const {done,value}=await reader.read();if(done)break;length+=value.byteLength;if(length>max){await reader.cancel();throw new AppError("Solicitud demasiado extensa.",413);}parts.push(value);}
 const data=new Uint8Array(length);let offset=0;for(const part of parts){data.set(part,offset);offset+=part.length;}try{const parsed=JSON.parse(new TextDecoder().decode(data));if(!parsed||typeof parsed!=="object"||Array.isArray(parsed))throw new Error("INVALID_JSON_OBJECT");return parsed;}catch{throw new AppError("Solicitud no válida.");}
}
async function limit(owner:string,scope:string,max=30){const minute=Math.floor(Date.now()/60000),key=`${scope}:${owner}:${minute}`;const r=await stmt("INSERT INTO rate_limits (key,count,expires_at) VALUES (?,1,?) ON CONFLICT(key) DO UPDATE SET count=count+1 RETURNING count",key,Date.now()+120000).first<{count:number}>();if((r?.count||0)>max)throw new AppError("Esperá un momento antes de volver a intentar.",429);}
const json=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers:{"Content-Type":"application/json; charset=utf-8","Cache-Control":"no-store","X-Content-Type-Options":"nosniff","Referrer-Policy":"same-origin"}});
async function digest(s:string){return Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256",new TextEncoder().encode(s)))).map(b=>b.toString(16).padStart(2,"0")).join("");}
async function logEvent(name:string,product:string|null=null){await stmt("INSERT INTO events (id,name,product,created_at) VALUES (?,?,?,?)",crypto.randomUUID(),name,product,now()).run();}
async function createOrder(req:Request){
 const u=await identity(req);await limit(u.id,"order",12);const input=validateOrder(await body(req));const key=req.headers.get("idempotency-key");if(!key||!/^[a-zA-Z0-9-]{16,80}$/.test(key))throw new AppError("Falta la clave de la solicitud.");
 const fingerprint=await digest(JSON.stringify(input));const existing=await stmt("SELECT * FROM orders WHERE owner_id=? AND request_key=?",u.id,key).first<Row>();if(existing){if(existing.fingerprint!==fingerprint)throw new AppError("Esta solicitud ya se usó con otros datos.",409);return json(publicOrder(existing));}
 if(paymentMode()==="manual_qr"&&!liveContentReady())throw new AppError("Las ventas están pausadas hasta habilitar el contenido de producción.",503);
 await profile(u.id);let discount=0,referralOwner:string|null=null;const product=PRODUCTS.find(p=>p.id===input.product)!;
 if(input.referral&&paymentMode()==="manual_qr")throw new AppError("Los descuentos requieren un QR por el importe exacto y están pausados en cobros manuales.");
 if(input.referral){
  if(input.product==="premium")throw new AppError("El referido aplica a lectura y compatibilidad.");
  const ref=await stmt("SELECT id FROM profiles WHERE referral_code=?",input.referral).first<{id:string}>();
  if(!ref||ref.id===u.id)throw new AppError("Código inválido o perteneciente a tu cuenta.");
  const used=await stmt("SELECT COUNT(*) n FROM orders WHERE owner_id=? AND (payment_status='paid' OR (discount>0 AND payment_status IN ('pending','failed')))",u.id).first<{n:number}>();
  if(used!.n>0)throw new AppError("El referido es solo para el primer pedido, sin descuentos pendientes.");
  const cap=await stmt("SELECT COUNT(*) n FROM orders WHERE referral_owner=? AND created_at>=? AND payment_status IN ('pending','paid')",ref.id,dateKey().slice(0,7)+"-01").first<{n:number}>();
  if(cap!.n>=5)throw new AppError("Este código alcanzó su límite de cinco usos del mes.");
  discount=Math.min(3000,Math.round(product.price*0.1));referralOwner=ref.id;
 }
 const id=crypto.randomUUID();
 if(paymentMode()==="manual_qr"&&!await findQr(product.price-discount))throw new AppError("Estamos renovando el QR de este importe. Volvé en unos minutos; no realices ningún pago.",409);
 // Conditional insert prevents concurrent first-purchase/referral abuse across different keys.
 await stmt("INSERT INTO orders (id,owner_id,request_key,fingerprint,product,amount,discount,payload,referral_owner,marketing_consent,consent_version,created_at) SELECT ?,?,?,?,?,?,?,?,?,?,?,? WHERE ?=0 OR (NOT EXISTS (SELECT 1 FROM orders WHERE owner_id=? AND (payment_status='paid' OR (discount>0 AND payment_status IN ('pending','failed')))) AND (SELECT COUNT(*) FROM orders WHERE referral_owner=? AND created_at>=? AND payment_status IN ('pending','paid'))<5) ON CONFLICT(owner_id,request_key) DO NOTHING",id,u.id,key,fingerprint,input.product,product.price-discount,discount,JSON.stringify(input),referralOwner,input.marketing?1:0,VERSION,now(),discount,u.id,referralOwner,dateKey().slice(0,7)+"-01").run();
 const row=await stmt("SELECT * FROM orders WHERE owner_id=? AND request_key=?",u.id,key).first<Row>();if(!row)throw new AppError("El referido ya se aplicó a otro pedido. Revisá tu historial.",409);if(row.fingerprint!==fingerprint)throw new AppError("Conflicto de solicitud.",409);
 if(paymentMode()==="manual_qr"){await stmt("UPDATE orders SET mode='manual_qr' WHERE id=?",row.id).run();row.mode="manual_qr";}
 await logEvent("checkout_created",input.product);return json(publicOrder(row),201);
}
async function deliver(id:string,forceError=false){
 const stamp=now(),lease=new Date(Date.now()+120000).toISOString();
 const claimed=await stmt("UPDATE orders SET delivery_status='generating',lease_until=?,attempts=attempts+1,error_code=NULL WHERE id=? AND payment_status='paid' AND delivery_status!='delivered' AND (lease_until IS NULL OR lease_until<?) AND attempts<5 RETURNING *",lease,id,stamp).first<Row>();
 if(!claimed)return;
 try{
  if(forceError)throw new Error("DEMO_GENERATION_FAILED");
  const generated=await generate(JSON.parse(claimed.payload) as OrderInput,id,runtime());
  await stmt("UPDATE orders SET result=?,source=?,ai_cost=ai_cost+?,delivery_status='delivered',delivered_at=?,lease_until=NULL,error_code=NULL WHERE id=? AND payment_status='paid' AND lease_until=?",JSON.stringify(generated.report),generated.report.source,generated.cost,now(),id,lease).run();await logEvent("delivered",claimed.product);
 }catch(e){const code=e instanceof Error&&/^[A-Z_0-9]+$/.test(e.message)?e.message:"GENERATION_REVIEW";await stmt("UPDATE orders SET delivery_status='error',lease_until=NULL,error_code=? WHERE id=? AND lease_until=?",code,id,lease).run();}
}
async function simulate(req:Request,id:string){
 const u=await identity(req);await limit(u.id,"payment",20);const order=await owned(id,u.id);if(order.mode!=="demo"||(runtime().PAYMENTS_MODE&&runtime().PAYMENTS_MODE!=="demo"))throw new AppError("Simulador deshabilitado.",403);
 const {outcome,failGeneration}=await body(req);if(!["approved","declined","cancelled"].includes(outcome))throw new AppError("Resultado de simulación inválido.");
 if(order.payment_status==="refunded"||order.payment_status==="cancelled")throw new AppError("El pedido fue reembolsado o cancelado. Creá un pedido nuevo.",409);
 const stamp=now(),event=`demo:${id}:${outcome}`;
 if(outcome==="approved"){
  await database().batch([
   stmt("INSERT INTO payment_events (id,order_id,state,created_at) VALUES (?,?,?,?) ON CONFLICT(id) DO NOTHING",event,id,"paid",stamp),
   stmt("UPDATE orders SET payment_status='paid',paid_at=COALESCE(paid_at,?),fee_estimate=amount*0.033 WHERE id=? AND payment_status IN ('pending','failed')",stamp,id),
  ]);
  await deliver(id,failGeneration===true);
 }else if(order.payment_status!=="paid"){
  await database().batch([stmt("INSERT INTO payment_events (id,order_id,state,created_at) VALUES (?,?,?,?) ON CONFLICT(id) DO NOTHING",event,id,outcome,stamp),stmt("UPDATE orders SET payment_status=? WHERE id=? AND payment_status IN ('pending','failed')",outcome==="cancelled"?"cancelled":"failed",id)]);
 }
 return json(publicOrder(await owned(id,u.id)));
}
async function findQr(amount:number){
 const rows=await stmt("SELECT * FROM qr_codes WHERE amount=? AND enabled=1 ORDER BY expires_at DESC",amount).all<QrRow>();return rows.results.find(q=>isLiveQr(q))||null;
}
async function uploadQr(req:Request){
 const u=await admin(req);await limit(u.id,"qr-upload",12);const b=validateQr(await body(req,1450000));const bucket=runtime().BUCKET;if(!bucket)throw new AppError("El almacenamiento de imágenes todavía no está disponible.",503);
 const id=crypto.randomUUID(),key=`payment-qr/${id}`,old=await stmt("SELECT object_key FROM qr_codes WHERE slot=?",b.slot).first<{object_key:string}>();
 await bucket.put(key,b.bytes,{httpMetadata:{contentType:b.mime}});
 try{await stmt("INSERT INTO qr_codes (slot,id,object_key,mime,holder,label,amount,generated_at,expires_at,enabled,reusable,updated_at) VALUES (?,?,?,?,?,?,?,?,?,1,1,?) ON CONFLICT(slot) DO UPDATE SET id=excluded.id,object_key=excluded.object_key,mime=excluded.mime,holder=excluded.holder,label=excluded.label,amount=excluded.amount,generated_at=excluded.generated_at,expires_at=excluded.expires_at,enabled=1,reusable=1,updated_at=excluded.updated_at",b.slot,id,key,b.mime,b.holder,b.label,b.amount,b.generatedAt,b.expiresAt,now()).run();}catch(e){await bucket.delete(key);throw e;}
 if(old?.object_key)await bucket.delete(old.object_key).catch(()=>{});
 return json({ok:true,id},201);
}
async function imageResponse(key:string,mime:string){
 const image=await runtime().BUCKET?.get(key);if(!image)throw new AppError("Imagen no disponible.",404);
 return new Response(image.body,{headers:{"Content-Type":mime,"Cache-Control":"private, no-store","X-Content-Type-Options":"nosniff","Content-Security-Policy":"default-src 'none'; sandbox","Content-Disposition":"inline; filename=\"QR-Mango.png\""}});
}
async function checkoutQr(req:Request,r:Row){
 if(!["pending","failed"].includes(r.payment_status))throw new AppError("Este pedido ya no admite un nuevo pago.",409);
 if(r.mode==="demo"&&paymentMode()!=="demo")throw new AppError("Este pedido es de demostración. Creá uno nuevo.",409);
 const b=await body(req);const reported=await stmt("SELECT status FROM manual_payments WHERE order_id=?",r.id).first<{status:string}>();
 if(reported&&reported.status!=="rejected")throw new AppError("Ya informaste un pago. Esperá la revisión; no pagues otra vez.",409);
 const intent=await stmt("SELECT * FROM qr_intents WHERE order_id=?",r.id).first<{qr_id:string;snapshot:string}>();
 if(intent&&!b.refresh){const q=await stmt("SELECT * FROM qr_codes WHERE id=?",intent.qr_id).first<QrRow>();if(q&&isLiveQr(q))return json({qr:JSON.parse(intent.snapshot),imageUrl:`/api/orders/${r.id}/qr-image`,test:r.mode!=="manual_qr"});}
 const q=await findQr(r.amount);if(!q)return json({qr:null,message:"Estamos renovando el QR para este importe. No realices ningún pago hasta que esté disponible.",test:r.mode!=="manual_qr"});
 // Snapshot ties this checkout to the recipient and exact amount actually displayed.
 await stmt("INSERT INTO qr_intents (order_id,qr_id,snapshot,created_at) VALUES (?,?,?,?) ON CONFLICT(order_id) DO UPDATE SET qr_id=excluded.qr_id,snapshot=excluded.snapshot,created_at=excluded.created_at",r.id,q.id,JSON.stringify(qrSnapshot(q)),now()).run();
 if(r.mode==="demo")await stmt("UPDATE orders SET mode='manual_qr_test' WHERE id=? AND mode='demo'",r.id).run();
 return json({qr:qrSnapshot(q),imageUrl:`/api/orders/${r.id}/qr-image`,test:r.mode!=="manual_qr"});
}
async function orderQrImage(r:Row){
 const intent=await stmt("SELECT qr_id FROM qr_intents WHERE order_id=?",r.id).first<{qr_id:string}>();const q=intent&&await stmt("SELECT * FROM qr_codes WHERE id=?",intent.qr_id).first<QrRow>();
 if(!q||!isLiveQr(q)||q.amount!==r.amount||!["pending","failed"].includes(r.payment_status))throw new AppError("Este QR venció o fue retirado. Actualizá antes de pagar.",410);
 return await imageResponse(q.object_key,q.mime);
}
async function reportPayment(req:Request,r:Row){
 const u=await identity(req);await limit(u.id,"report-payment",10);
 if(!["manual_qr","manual_qr_test"].includes(r.mode)||!["pending","failed"].includes(r.payment_status))throw new AppError("Este pedido no admite un aviso de pago QR.",409);
 const intent=await stmt("SELECT snapshot FROM qr_intents WHERE order_id=?",r.id).first<{snapshot:string}>();if(!intent)throw new AppError("Primero abrí el QR de este pedido.",409);
 const b=validatePaymentReport(await body(req));
 // An expired QR may have been paid before expiry; the operator must check the ledger.
 await stmt("INSERT INTO manual_payments (order_id,payer,reference,reported_at,status) VALUES (?,?,?,?,'review') ON CONFLICT(order_id) DO UPDATE SET payer=excluded.payer,reference=excluded.reference,reported_at=excluded.reported_at,status='review',note=NULL WHERE manual_payments.status='rejected'",r.id,b.payer,b.reference,now()).run();
 return json({ok:true,status:"review",message:"Aviso recibido. Falta verificar el ingreso en Mango; no vuelvas a pagar."});
}
async function verifyManualPayment(req:Request,id:string,actor:string){
 const r=await stmt("SELECT * FROM orders WHERE id=?",id).first<Row>(),report=await stmt("SELECT * FROM manual_payments WHERE order_id=?",id).first<ManualRow>();
 if(!r||!report||!["manual_qr","manual_qr_test"].includes(r.mode))throw new AppError("Aviso de pago no encontrado.",404);
 const b=await body(req);
 if(b.action==="reject"){
  if(r.payment_status==="paid"||report.status==="verified")throw new AppError("Este pago ya fue confirmado.",409);
  const note=String(b.note||"").trim();if(note.length<5||note.length>200)throw new AppError("Explicá el motivo de revisión (5 a 200 caracteres).");
  await stmt("UPDATE manual_payments SET status='rejected',note=? WHERE order_id=? AND status='review'",note,id).run();return json({ok:true});
 }
 if(b.action!=="approve"||b.checked!==true||Number(b.amount)!==r.amount)throw new AppError("Verificá el ingreso real y confirmá el importe exacto del pedido.");
 if(r.mode==="manual_qr"&&(!liveContentReady()||paymentMode()!=="manual_qr"))throw new AppError("La operación requiere el entorno de producción habilitado.",409);
 const intent=await stmt("SELECT snapshot FROM qr_intents WHERE order_id=?",id).first<{snapshot:string}>();if(!intent)throw new AppError("Falta la cuenta de cobro del pedido.",409);
 const snapshot=JSON.parse(intent.snapshot) as QrSnapshot,key=transactionKey(snapshot.holder,String(b.reference||""));
 if(r.payment_status==="paid"&&report.transaction_key!==key)throw new AppError("Este pedido ya se confirmó con otra referencia.",409);
 const used=await stmt("SELECT order_id FROM manual_payments WHERE transaction_key=?",key).first<{order_id:string}>();if(used&&used.order_id!==id)throw new AppError("Esta transacción ya fue utilizada en otro pedido.",409);
 const stamp=now();
 try{await database().batch([
  stmt("UPDATE manual_payments SET status='verified',transaction_key=?,verified_at=COALESCE(verified_at,?),verified_by=? WHERE order_id=? AND (status='review' OR transaction_key=?) AND EXISTS (SELECT 1 FROM orders WHERE id=? AND payment_status IN ('pending','failed','paid'))",key,stamp,actor,id,key,id),
  stmt("UPDATE orders SET payment_status='paid',paid_at=COALESCE(paid_at,?),fee_estimate=0 WHERE id=? AND payment_status IN ('pending','failed') AND EXISTS (SELECT 1 FROM manual_payments WHERE order_id=? AND status='verified' AND transaction_key=?)",stamp,id,id,key),
  stmt("INSERT INTO payment_events (id,order_id,state,created_at) SELECT ?,?,'paid',? WHERE EXISTS (SELECT 1 FROM orders WHERE id=? AND payment_status='paid') ON CONFLICT(id) DO NOTHING",`manual:${id}`,id,stamp,id),
 ]);}catch(e){if(String(e).includes("UNIQUE"))throw new AppError("La transacción ya está asociada a otro pedido.",409);throw e;}
 const confirmed=await stmt("SELECT * FROM orders WHERE id=?",id).first<Row>();const finalReport=await stmt("SELECT transaction_key FROM manual_payments WHERE order_id=?",id).first<{transaction_key:string}>();
 if(finalReport?.transaction_key!==key)throw new AppError("El pedido ya fue verificado con otra referencia.",409);
 if(confirmed?.payment_status!=="paid")throw new AppError("El aviso cambió de estado. Actualizá el panel antes de confirmar.",409);
 await deliver(id);return json({ok:true,order:publicOrder((await stmt("SELECT * FROM orders WHERE id=?",id).first<Row>())!)});
}

async function dashboard(){
 const [rows,expenseRows,ev]=await Promise.all([stmt("SELECT * FROM orders ORDER BY created_at DESC LIMIT 1000").all<Row>(),stmt("SELECT * FROM expenses ORDER BY date DESC LIMIT 1000").all<{id:string;category:string;amount:number;date:string;note:string}>(),stmt("SELECT name,COUNT(*) n FROM events WHERE created_at>=? GROUP BY name",dateKey().slice(0,7)+"-01").all<{name:string;n:number}>()]);
 const all=rows.results.filter(o=>paymentMode()==="demo"?o.mode!=="manual_qr":o.mode==="manual_qr"),month=dateKey().slice(0,7),day=dateKey();const dateOf=(s:string|null)=>s?dateKey(new Date(s)):"";
 const captured=all.filter(o=>o.payment_status==="paid"||o.payment_status==="refunded"),paid=captured.filter(o=>o.payment_status==="paid"),m=captured.filter(o=>dateOf(o.paid_at).startsWith(month)),net=m.filter(o=>o.payment_status==="paid");
 const sum=(r:Row[],f:keyof Row)=>r.reduce((s,o)=>s+Number(o[f]||0),0);const gross=sum(m,"amount"),refunds=sum(m.filter(o=>o.payment_status==="refunded"),"amount"),fees=sum(m,"fee_estimate"),ai=sum(m,"ai_cost"),expenses=expenseRows.results.filter(x=>x.date.startsWith(month)),ad=expenses.filter(x=>x.category==="publicidad").reduce((s,x)=>s+x.amount,0),fixed=expenses.filter(x=>x.category!=="publicidad").reduce((s,x)=>s+x.amount,0);
 const counts=new Map<string,number>();paid.forEach(o=>counts.set(o.owner_id,(counts.get(o.owner_id)||0)+1));const newCustomers=Array.from(new Set(net.map(o=>o.owner_id))).filter(id=>!paid.some(o=>o.owner_id===id&&dateOf(o.paid_at)<month+"-01")).length;
 const series=Array.from({length:14},(_,i)=>{const d=new Date();d.setUTCDate(d.getUTCDate()-(13-i));const key=dateKey(d);return {date:key,amount:sum(paid.filter(o=>dateOf(o.paid_at)===key),"amount")};});
 return {mode:paymentMode(),date:day,month,limitedTo:1000,todaySales:paid.filter(o=>dateOf(o.paid_at)===day).length,todayRevenue:sum(paid.filter(o=>dateOf(o.paid_at)===day),"amount"),monthGross:gross,refunds,monthRevenue:gross-refunds,fees,aiCost:ai,adSpend:ad,fixedCosts:fixed,netBeforeTax:(gross-refunds)/1.1-fees-ai-ad-fixed,vatReserve:(gross-refunds)/11,marginBeforeVat:gross-refunds-fees-ai-ad-fixed,pending:all.filter(o=>o.payment_status==="pending").length,delivered:paid.filter(o=>o.delivery_status==="delivered").length,errors:all.filter(o=>o.delivery_status==="error").map(publicOrder),recurringCustomers:Array.from(counts.values()).filter(n=>n>1).length,newCustomers,cac:newCustomers?ad/newCustomers:null,products:PRODUCTS.map(p=>({id:p.id,name:p.short,count:net.filter(o=>o.product===p.id).length,revenue:sum(net.filter(o=>o.product===p.id),"amount")})),referrals:paid.filter(o=>o.referral_owner).length,discounts:sum(net,"discount"),orders:all.map(publicOrder),expenses:expenseRows.results,series,events:ev.results};
}
export async function api(req:Request,path:string[]){
 try{
  const method=req.method,p=path.join("/");if(method==="POST")mutation(req);
  if(p==="health")return json({ok:true,payments:paymentMode(),version:VERSION});
  if(p==="payments/config"&&method==="GET"){const q=await stmt("SELECT * FROM qr_codes WHERE enabled=1").all<QrRow>();return json({mode:paymentMode(),contentReady:liveContentReady(),availableAmounts:q.results.filter(q=>isLiveQr(q)).map(q=>q.amount)});}
  if(p==="daily"&&method==="GET"){
   const date=dateKey(),key=`${date}:editorial-v1`;let cached=await stmt("SELECT content FROM daily_cache WHERE key=?",key).first<{content:string}>();if(!cached){const content=JSON.stringify(SIGNS.map(s=>dailyFor(s.id,date)));await stmt("INSERT INTO daily_cache (key,content,source,created_at) VALUES (?,?,?,?) ON CONFLICT(key) DO NOTHING",key,content,"editorial-demo",now()).run();cached={content};}return json({date,items:JSON.parse(cached.content),mode:"editorial-demo"});
  }
  if(p==="me"&&method==="GET"){const u=await identity(req),pr=await profile(u.id);let isAdmin=false;try{await admin(req);isAdmin=true;}catch{}return json({name:u.name,referralCode:pr.referral_code,admin:isAdmin,mode:paymentMode()});}
  if(p==="events"&&method==="POST"){const u=await identity(req);await limit(u.id,"event",30);const {name,product}=await body(req);if(!["product_view","form_started","share_card","pdf_download"].includes(name)||product&&!PRODUCTS.some(p=>p.id===product))throw new AppError("Evento inválido.");await logEvent(name,product||null);return json({ok:true});}
  if(p==="orders"&&method==="POST")return await createOrder(req);
  if(p==="orders"&&method==="GET"){const u=await identity(req);const r=await stmt("SELECT * FROM orders WHERE owner_id=? ORDER BY created_at DESC LIMIT 200",u.id).all<Row>();return json({orders:r.results.map(publicOrder)});}
  if(path[0]==="orders"&&path[1]){
   const u=await identity(req),r=await owned(path[1],u.id);
   if(path.length===2&&method==="GET")return json(publicOrder(r));
   if(path[2]==="qr"&&method==="POST")return await checkoutQr(req,r);
   if(path[2]==="qr-image"&&method==="GET")return await orderQrImage(r);
   if(path[2]==="payment-report"&&method==="POST")return await reportPayment(req,r);
   if(path[2]==="payment-report"&&method==="GET"){const report=await stmt("SELECT * FROM manual_payments WHERE order_id=?",r.id).first<ManualRow>();return json({report:report?{status:report.status,payer:report.payer,reference:report.reference,reportedAt:report.reported_at,note:report.note}:null});}
   if(path[2]==="retry"&&method==="POST"){await limit(u.id,"retry",8);if(r.payment_status!=="paid")throw new AppError("El pago no está aprobado.",409);if(r.attempts>=5)throw new AppError("Se alcanzó el límite de intentos. Requiere revisión administrativa.",409);await deliver(r.id);return json(publicOrder(await owned(r.id,u.id)));}
   if(path[2]==="pdf"&&method==="GET"){if(r.payment_status!=="paid"||r.delivery_status!=="delivered"||!r.result)throw new AppError("El informe todavía no está disponible.",409);const data=makePdf(JSON.parse(r.result) as Report,{id:r.id,date:dateKey(new Date(r.created_at)),product:PRODUCTS.find(p=>p.id===r.product)!.short});return new Response(data as BodyInit,{headers:{"Content-Type":"application/pdf","Content-Disposition":`attachment; filename="LUMINA-${r.id.slice(0,8)}.pdf"`,"Cache-Control":"private, no-store","X-Content-Type-Options":"nosniff"}});}
  }
  if(path[0]==="demo"&&path[1]==="payments"&&path[2]&&method==="POST")return await simulate(req,path[2]);
  if(p==="payments/webhook")throw new AppError("Pasarela real pendiente de homologación. Ningún pago fue acreditado.",503);
  if(path[0]==="admin"){
   const actor=await admin(req);
   if(p==="admin/qr"&&method==="GET"){const q=await stmt("SELECT * FROM qr_codes ORDER BY slot").all<QrRow>();return json({codes:q.results.map(q=>({...qrSnapshot(q),slot:q.slot,active:isLiveQr(q),enabled:!!q.enabled,imageUrl:`/api/admin/qr/${q.slot}/image`})),mode:paymentMode(),contentReady:liveContentReady()});}
   if(p==="admin/qr"&&method==="POST")return await uploadQr(req);
   if(path[1]==="qr"&&/^[123]$/.test(path[2]||"")){
    const q=await stmt("SELECT * FROM qr_codes WHERE slot=?",Number(path[2])).first<QrRow>();if(!q)throw new AppError("QR no encontrado.",404);
    if(path[3]==="image"&&method==="GET")return await imageResponse(q.object_key,q.mime);
    if(path[3]==="disable"&&method==="POST"){await stmt("UPDATE qr_codes SET enabled=0,updated_at=? WHERE slot=?",now(),q.slot).run();return json({ok:true});}
   }
   if(p==="admin/payment-reports"&&method==="GET"){const r=await stmt("SELECT m.*,o.amount,o.product,o.mode,o.payment_status,o.fee_estimate,q.snapshot FROM manual_payments m JOIN orders o ON m.order_id=o.id LEFT JOIN qr_intents q ON q.order_id=o.id ORDER BY m.reported_at DESC LIMIT 200").all();return json({reports:r.results});}
   if(path[1]==="manual-payment"&&path[2]&&method==="POST")return await verifyManualPayment(req,path[2],actor.id);
   if(p==="admin/dashboard"&&method==="GET")return json(await dashboard());
   if(p==="admin/expenses"&&method==="POST"){
    const b=await body(req),parsedDate=new Date(String(b.date)+"T12:00:00Z");if(!["publicidad","hosting","herramientas","otros"].includes(b.category)||!Number.isInteger(b.amount)||b.amount<=0||b.amount>20000000||typeof b.note!=="string"||b.note.length>120||!/^\d{4}-\d{2}-\d{2}$/.test(b.date)||Number.isNaN(parsedDate.getTime())||parsedDate.toISOString().slice(0,10)!==b.date)throw new AppError("Revisá fecha, categoría e importe del gasto.");
    const key=req.headers.get("idempotency-key");if(!key||!/^[a-zA-Z0-9-]{16,80}$/.test(key))throw new AppError("Falta clave de solicitud.");await stmt("INSERT INTO expenses (id,category,amount,date,note,created_at,request_key) VALUES (?,?,?,?,?,?,?) ON CONFLICT(request_key) DO NOTHING",crypto.randomUUID(),b.category,b.amount,b.date,b.note,now(),key).run();return json({ok:true});
   }
   if(path[1]==="refund"&&path[2]&&method==="POST"){
    const r=await stmt("SELECT * FROM orders WHERE id=?",path[2]).first<Row>();if(!r||!["demo","manual_qr_test"].includes(r.mode))throw new AppError("Solo se admite una reversa simulada en pedidos de prueba.",409);await database().batch([stmt("INSERT INTO payment_events (id,order_id,state,created_at) VALUES (?,?,?,?) ON CONFLICT(id) DO NOTHING",`demo:${r.id}:refund`,r.id,"refunded",now()),stmt("UPDATE orders SET payment_status='refunded' WHERE id=? AND payment_status='paid'",r.id)]);return json({ok:true});
   }
   if(p==="admin/export"&&method==="GET"){
    const rows=(await stmt("SELECT id,created_at,product,amount,discount,payment_status,delivery_status,ai_cost,fee_estimate,mode FROM orders ORDER BY created_at DESC LIMIT 10000").all<Record<string,unknown>>()).results;
    const costs=(await stmt("SELECT id,date,category,amount,note FROM expenses ORDER BY date DESC LIMIT 10000").all<Record<string,unknown>>()).results;
    const lines=[["tipo","id","fecha","concepto","importe_PYG","descuento_PYG","estado_pago","entrega","costo_IA_PYG","comision_est_PYG","modo","nota"],...rows.map(r=>["pedido",r.id,r.created_at,r.product,r.amount,r.discount,r.payment_status,r.delivery_status,r.ai_cost,r.fee_estimate,r.mode,""]),...costs.map(r=>["gasto",r.id,r.date,r.category,r.amount,0,"","",0,0,"demo",r.note])];
    return new Response("\ufeff"+lines.map(r=>r.map(safeCsv).join(",")).join("\r\n"),{headers:{"Content-Type":"text/csv;charset=utf-8","Content-Disposition":`attachment; filename="LUMINA-movimientos-${dateKey()}.csv"`,"Cache-Control":"no-store"}});
   }
  }
  throw new AppError("Ruta no encontrada.",404);
 }catch(e){if(e instanceof AppError)return json({error:e.message},e.status);console.error("ASTROPY_API_FAILURE",e instanceof Error?e.name:"unknown");return json({error:"No pudimos completar la operación. Volvé a intentar sin crear otro pedido."},500);}
}
