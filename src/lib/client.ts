import {dailyFor,dateKey,SIGNS} from './domain';
export const money=(v:number)=>'₲'+new Intl.NumberFormat('es-PY',{maximumFractionDigits:0}).format(v);
// Public backend URL only. NEVER put secret keys in VITE_* variables.
const base=(import.meta.env.VITE_API_BASE_URL||'').replace(/\/$/,'');
export function apiUrl(path:string){return `${base}/${path.replace(/^\//,'')}`;}
export async function request(path:string,body?:unknown,key?:string):Promise<any>{
 if(!base){
  // Preserve only the original public editorial demonstration. No fake users,
  // orders, payments or private reports are created in this migration starter.
  if(path==='daily'&&body===undefined){const date=dateKey();return {date,items:SIGNS.map(s=>dailyFor(s.id,date)),mode:'editorial-demo'};}
  if(path==='payments/config'&&body===undefined)return {mode:'demo',contentReady:false,availableAmounts:[]};
  if(path==='me'&&body===undefined)return null;
  if(path==='events')return {ok:false,reason:'backend_not_connected'};
  throw new Error('Migración a Bolt: falta conectar la cuenta y el servidor. Las compras todavía están desactivadas.');
 }
 // Phase 2 must attach a verified customer session here. A URL alone does not
 // enable authentication, ownership, uploads, downloads or admin authorization.
 const r=await fetch(apiUrl(path),body===undefined?{cache:'no-store',credentials:'include'}:{method:'POST',credentials:'include',headers:{'Content-Type':'application/json',...(key?{'Idempotency-Key':key}:{})},body:JSON.stringify(body)});
 const d=await r.json();if(!r.ok)throw new Error(d.error||'No pudimos completar la solicitud.');return d;
}
