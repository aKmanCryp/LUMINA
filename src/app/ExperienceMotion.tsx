"use client";
import {useEffect,useLayoutEffect,useRef,useState,type ReactNode} from "react";
import {Check,Sparkles} from "lucide-react";
import type {ProductId} from "../lib/domain";
// Decorative loops run only while their section is visible.
export function useInViewMotion<T extends HTMLElement>(){
 const ref=useRef<T>(null),[active,setActive]=useState(false);
 useEffect(()=>{
  const node=ref.current;if(!node)return;
  const preference=window.matchMedia("(prefers-reduced-motion: reduce)");
  let observer:IntersectionObserver|undefined;
  function observe(){
   observer?.disconnect();setActive(false);
   if(preference.matches||!("IntersectionObserver" in window))return;
   observer=new IntersectionObserver(entries=>setActive(entries.some(entry=>entry.isIntersecting)),{threshold:0,rootMargin:"40px"});
   observer.observe(node!);
  }
  observe();preference.addEventListener("change",observe);
  return()=>{observer?.disconnect();preference.removeEventListener("change",observe);};
 },[]);
 return {ref,active};
}
export function AnimatedSigns({product}:{product:ProductId}){
 return <div className={"astral-emblem astral-emblem-"+product} key={product} aria-hidden="true"><span className="emblem-orbit"/><span className="emblem-orbit inner"/><span className="emblem-star star-a">✧</span><span className="emblem-star star-b">✦</span><span className="emblem-star star-c">·</span>{product==="compatibilidad"?<div className="emblem-pair"><span className="emblem-glyph first">♎︎</span><span className="emblem-connection">✧</span><span className="emblem-glyph second">♌︎</span></div>:<span className="emblem-glyph solo">{product==="premium"?"✳":"☾"}</span>}</div>;
}
const phrases={
 payment:["Tu aviso está en revisión","Verificamos el ingreso en Mango","Tu lectura se habilita al confirmar"],
 preparing:["Tu pago está confirmado","Preparando tu espacio personal","Tu lectura está en camino"],
 reveal:["Tu pago está confirmado","Un momento para vos","Tu lectura está lista"],
};
export function ReadingCeremony({phase,compact=false,onSkip}:{phase:"payment"|"preparing"|"reveal";compact?:boolean;onSkip?:()=>void}){
 const [beat,setBeat]=useState(0);
 useEffect(()=>{setBeat(0);if(window.matchMedia("(prefers-reduced-motion: reduce)").matches)return;const timer=setInterval(()=>setBeat(n=>phase==="reveal"?Math.min(n+1,2):(n+1)%3),phase==="reveal"?900:2200);return()=>clearInterval(timer);},[phase]);
 return <div className={"reading-ceremony ceremony-"+phase+(compact?" compact":"")} data-phase={phase}><div className="ceremony-art" aria-hidden="true"><span className="ceremony-orbit orbit-one"/><span className="ceremony-orbit orbit-two"/><span className="ceremony-zodiac zodiac-a">♎︎</span><span className="ceremony-zodiac zodiac-b">♌︎</span><span className="ceremony-zodiac zodiac-c">♓︎</span><span className="ceremony-spark spark-a">✧</span><span className="ceremony-spark spark-b">✦</span><div className="ceremony-cards"><div className="ceremony-card card-left"><span className="card-frame"/><span className="card-corner">✧</span><span className="card-symbol">☾</span><span className="card-foot">LÚMINA</span></div><div className="ceremony-card card-center"><span className="card-frame"/><span className="card-corner">✦</span><span className="card-symbol">✳</span><span className="card-foot">TU UNIVERSO</span></div><div className="ceremony-card card-right"><span className="card-frame"/><span className="card-corner">✧</span><span className="card-symbol">☼</span><span className="card-foot">TU MOMENTO</span></div></div></div><div className="ceremony-copy"><div className="ceremony-state">{phase==="payment"?<Sparkles size={14}/>:<Check size={14}/>} {phase==="payment"?"VERIFICACIÓN MANUAL":phase==="preparing"?"PAGO CONFIRMADO":"TU LECTURA ESTÁ LISTA"}</div><p key={phase+beat} className="ceremony-phrase">{phrases[phase][beat]}</p>{phase==="payment"?<small>El aviso aún no confirma el pago.</small>:phase==="preparing"?<small>El informe se mostrará cuando termine su preparación.</small>:<small>Una nueva perspectiva, a tu ritmo.</small>}</div>{phase==="reveal"&&<><div className="ceremony-progress" aria-hidden="true"><span/></div>{onSkip&&<button className="text-link ceremony-skip" type="button" onClick={onSkip}>Abrir mi lectura ahora <span aria-hidden="true">→</span></button>}</>}</div>;
}
export function useReadingReveal(id:string,ready:boolean){
 const [doneId,setDoneId]=useState<string|null>(null);
 function complete(){try{sessionStorage.setItem("lumina.reading-opened."+id,"1");}catch{}setDoneId(id);}
 useLayoutEffect(()=>{
  if(!ready)return;let seen=false;try{seen=sessionStorage.getItem("lumina.reading-opened."+id)==="1";}catch{}
  if(seen||window.matchMedia("(prefers-reduced-motion: reduce)").matches){setDoneId(id);return;}
  const timer=setTimeout(()=>{try{sessionStorage.setItem("lumina.reading-opened."+id,"1");}catch{}setDoneId(id);},3000);
  return()=>clearTimeout(timer);
 },[id,ready]);
 return {show:ready&&doneId!==id,complete};
}
export function ScrollReadingModule({id,children}:{id:string;children:ReactNode}){
 const ref=useRef<HTMLElement>(null),[phase,setPhase]=useState<"static"|"armed"|"visible">("static");
 useEffect(()=>{
  const node=ref.current;if(!node||!("IntersectionObserver" in window)||window.matchMedia("(prefers-reduced-motion: reduce)").matches)return;
  let observer:IntersectionObserver|undefined;
  try{observer=new IntersectionObserver(entries=>{if(entries.some(e=>e.isIntersecting)){setPhase("visible");observer?.disconnect();}},{threshold:.1,rootMargin:"0px 0px -25px 0px"});setPhase("armed");observer.observe(node);}catch{setPhase("static");}
  return()=>observer?.disconnect();
 },[]);
 return <section ref={ref} id={id} tabIndex={-1} aria-labelledby={id+"-title"} className="reading-module scroll-reading-module" data-reveal={phase} onFocusCapture={()=>setPhase("visible")}>{children}</section>;
}
