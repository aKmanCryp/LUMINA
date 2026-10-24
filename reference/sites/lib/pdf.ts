import type { Report } from "./domain";
// Small PDF 1.4 renderer for Workers, with WinAnsi fonts and byte-accurate xref.
const clean=(s:string)=>s.replace(/[—–]/g,"-").replace(/[“”]/g,'"').replace(/[‘’]/g,"'").replace(/₲/g,"Gs.").replace(/[^\x20-\x7e\xa0-\xff\n]/g,"");
const literal=(s:string)=>clean(s).replace(/[\\()]/g,"\\$&").replace(/[\x80-\xff]/g,c=>"\\"+c.charCodeAt(0).toString(8).padStart(3,"0"));
function wrap(s:string,max=82){const out:string[]=[];for(const para of clean(s).split("\n")){let line="";for(const word of para.split(/\s+/)){if((line+" "+word).length>max){out.push(line);line=word;}else line+=(line?" ":"")+word;}if(line)out.push(line);}return out;}
export function makePdf(report:Report,meta:{product:string;date:string;id:string}):Uint8Array{
 const pages:string[][]=[];let page:string[]=[];let y=732;
 const text=(s:string,size=11,font="F1",color="0.18 0.17 0.27")=>{page.push(`${color} rg BT /${font} ${size} Tf 52 ${y} Td (${literal(s)}) Tj ET`);y-=size+6;};
 const newPage=()=>{if(page.length)pages.push(page);page=["0.065 0.055 0.14 rg 0 786 595 56 re f","0.8 0.7 0.94 rg BT /F2 15 Tf 52 809 Td (L U M I N A) Tj ET"];y=748;};
 const ensure=(height:number)=>{if(y-height<75)newPage();};newPage();
 const block=(s:string,size=11,font="F1",width=82)=>{for(const l of wrap(s,width)){ensure(size+6);text(l,size,font);}y-=9;};
 block("TU EXPERIENCIA ASTRAL",9,"F2");block(report.title,22,"F2",42);block(`${meta.product} - ${meta.date} - ${report.source==="openai"?"Generado con IA":"Demostración editorial"}`,9);y-=8;block(report.intro);
 for(const [i,s]of report.sections.entries()){ensure(110);y-=6;block(`${String(i+1).padStart(2,"0")}  ${s.title}`,14,"F2",62);block(s.body);block(s.prompt,11,"F3",78);y-=5;}
 ensure(100);block(report.closing,9,"F3",95);block(`Referencia privada: ${meta.id}`,8);if(page.length)pages.push(page);
 const objects:string[]=["<< /Type /Catalog /Pages 2 0 R >>","","<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>","<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>","<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Oblique /Encoding /WinAnsiEncoding >>"],kids:string[]=[];
 pages.forEach((lines,i)=>{const pageId=objects.length+1,streamId=pageId+1;kids.push(`${pageId} 0 R`);const stream=lines.join("\n")+`\n0.5 0.5 0.6 rg BT /F1 8 Tf 52 38 Td (LÚMINA - Contenido recreativo - ${i+1} / ${pages.length}) Tj ET`;objects.push(`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 3 0 R /F2 4 0 R /F3 5 0 R >> >> /Contents ${streamId} 0 R >>`,`<< /Length ${stream.length} >>\nstream\n${stream}\nendstream`);});
 objects[1]=`<< /Type /Pages /Count ${pages.length} /Kids [${kids.join(" ")}] >>`;let out="%PDF-1.4\n";const offsets=[0];objects.forEach((s,i)=>{offsets.push(out.length);out+=`${i+1} 0 obj\n${s}\nendobj\n`;});const start=out.length;
 out+=`xref\n0 ${objects.length+1}\n0000000000 65535 f \n`+offsets.slice(1).map(x=>`${String(x).padStart(10,"0")} 00000 n \n`).join("")+`trailer\n<< /Size ${objects.length+1} /Root 1 0 R >>\nstartxref\n${start}\n%%EOF`;return Uint8Array.from(out,c=>c.charCodeAt(0));
}
