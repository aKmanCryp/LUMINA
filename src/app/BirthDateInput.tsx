"use client";
import {useId,useRef,useState} from "react";
import {CalendarDays} from "lucide-react";
import {validBirth} from "../lib/domain";
import {birthIsoFromDisplay,formatBirthDigits,normalizeBirthPaste} from "../lib/birth-date";
export function BirthDateInput({name,label}:{name:"birth"|"birth2";label:string}){
 const [value,setValue]=useState(""),[touched,setTouched]=useState(false),ref=useRef<HTMLInputElement>(null),id=useId();
 const iso=birthIsoFromDisplay(value);
 const message=(v:string)=>!v?"":!birthIsoFromDisplay(v)?"Ingresá una fecha válida en DD/MM/AAAA.":!validBirth(birthIsoFromDisplay(v)!)?"La fecha debe corresponder a una persona mayor de 18 años, nacida desde 1900.":"";
 function update(v:string){setValue(v);ref.current?.setCustomValidity(message(v));}
 const error=touched?message(value):"";
 return <div className="birth-date-field"><label htmlFor={id}>{label}</label><span className="birth-date-control"><input ref={ref} id={id} name={name+"Display"} type="text" inputMode="numeric" required maxLength={10} pattern="[0-9]{2}/[0-9]{2}/[0-9]{4}" placeholder="DD/MM/AAAA" autoComplete={name==="birth"?"bday":"off"} value={value} aria-invalid={error?true:undefined} aria-describedby={id+"-hint"} onChange={e=>update(formatBirthDigits(e.target.value))} onBlur={()=>setTouched(true)} onPaste={e=>{e.preventDefault();update(normalizeBirthPaste(e.clipboardData.getData("text")));}}/><CalendarDays size={17} aria-hidden="true"/></span><input type="hidden" name={name} value={iso||""}/><small id={id+"-hint"} className={error?"date-input-hint invalid":"date-input-hint"}>{error||"DD/MM/AAAA · Mayores de 18 años"}</small></div>;
}
