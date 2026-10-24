export const money=(v:number)=>"₲"+new Intl.NumberFormat("es-PY",{maximumFractionDigits:0}).format(v);
export async function request(path:string,body?:unknown,key?:string){
 const r=await fetch("/api/"+path,body===undefined?{cache:"no-store"}:{method:"POST",headers:{"Content-Type":"application/json",...(key?{"Idempotency-Key":key}:{})},body:JSON.stringify(body)});
 const d=await r.json() as any;if(!r.ok)throw new Error(d.error||"No pudimos completar la solicitud.");return d;
}
