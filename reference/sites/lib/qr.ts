import { AppError } from "./domain";
export type QrRow={slot:number;id:string;object_key:string;mime:string;holder:string;label:string;amount:number;generated_at:string;expires_at:string;enabled:number;reusable:number;updated_at:string};
export type ManualRow={order_id:string;payer:string;reference:string;reported_at:string;status:string;transaction_key:string|null;verified_at:string|null;verified_by:string|null;note:string|null};
export type QrSnapshot={id:string;holder:string;label:string;amount:number;generatedAt:string;expiresAt:string};
export const QR_MAX_BYTES=1048576;
export const qrSnapshot=(q:QrRow):QrSnapshot=>({id:q.id,holder:q.holder,label:q.label,amount:q.amount,generatedAt:q.generated_at,expiresAt:q.expires_at});
export const isLiveQr=(q:QrRow,at=Date.now())=>q.enabled===1&&q.reusable===1&&new Date(q.generated_at).getTime()<=at&&new Date(q.expires_at).getTime()>at;
export function validateQr(b:Record<string,unknown>,at=Date.now()){
 const slot=Number(b.slot),amount=Number(b.amount),generated=new Date(String(b.generatedAt)),expires=new Date(String(b.expiresAt));
 const holder=String(b.holder||"").trim(),label=String(b.label||"Mango").trim();
 if(![1,2,3].includes(slot)||!Number.isInteger(amount)||amount<1000||amount>1000000)throw new AppError("Elegí un espacio del 1 al 3 y un importe válido.");
 if(holder.length<3||holder.length>80||label.length<2||label.length>40||/[<>\x00-\x1f]/.test(holder+label))throw new AppError("Ingresá el titular real y un nombre de cuenta válido.");
 const g=generated.getTime(),e=expires.getTime();
 if(!Number.isFinite(g)||!Number.isFinite(e)||g>at+60000||e<=at||e<=g||e-g>4*3600000||at-g>4*3600000)throw new AppError("La vigencia debe coincidir con Mango y no superar cuatro horas desde la generación original.");
 if(b.authorized!==true||b.reusable!==true||b.amountConfirmed!==true)throw new AppError("Confirmá autorización, importe y que este QR admite varios cobros.");
 const data=String(b.image||""),m=data.match(/^data:(image\/(?:png|jpeg|webp));base64,([A-Za-z0-9+/=]+)$/);
 if(!m||m[2].length>Math.ceil(QR_MAX_BYTES*4/3)+4)throw new AppError("Usá una imagen PNG, JPG o WebP de hasta 1 MB.");
 let bytes:Uint8Array;try{bytes=Uint8Array.from(atob(m[2]),c=>c.charCodeAt(0));}catch{throw new AppError("La imagen no es válida.");}
 const hex=Array.from(bytes.slice(0,12),b=>b.toString(16).padStart(2,"0")).join("");
 const valid=m[1]==="image/png"?hex.startsWith("89504e470d0a1a0a"):m[1]==="image/jpeg"?hex.startsWith("ffd8ff"):hex.startsWith("52494646")&&hex.slice(16,24)==="57454250";
 if(!valid||bytes.length<32||bytes.length>QR_MAX_BYTES)throw new AppError("El archivo no coincide con un formato de imagen admitido.");
 return {slot,amount,holder,label,generatedAt:generated.toISOString(),expiresAt:expires.toISOString(),mime:m[1],bytes};
}
export function validatePaymentReport(b:Record<string,unknown>){
 const payer=String(b.payer||"").trim(),reference=String(b.reference||"").trim();
 if(payer.length<3||payer.length>80||!reference||reference.length>80||/[<>\x00-\x1f]/.test(payer+reference))throw new AppError("Ingresá el nombre que figura en el pago y su referencia (hasta 80 caracteres).");
 return {payer,reference};
}
export function transactionKey(holder:string,reference:string){
 const clean=(s:string)=>s.normalize("NFKC").toUpperCase().replace(/[^\p{L}\p{N}]/gu,"");
 const r=clean(reference);if(r.length<4||r.length>80)throw new AppError("Copiá la referencia real de Mango (mínimo cuatro letras o números).");
 return "mango:"+clean(holder)+":"+r;
}
