/** Display dates in day/month/year; retain ISO dates at the API boundary. */
export function formatBirthDigits(value:string){
 const digits=value.replace(/\D/g,"").slice(0,8);
 return digits.slice(0,2)+(digits.length>2?"/"+digits.slice(2,4):"")+(digits.length>4?"/"+digits.slice(4,8):"");
}
export function birthIsoFromDisplay(value:string):string|null{
 const match=/^(\d{2})\/(\d{2})\/(\d{4})$/.exec(value);if(!match)return null;
 const iso=`${match[3]}-${match[2]}-${match[1]}`,date=new Date(iso+"T12:00:00Z");
 return Number.isFinite(date.getTime())&&date.toISOString().slice(0,10)===iso?iso:null;
}
export function normalizeBirthPaste(value:string){
 const text=value.trim(),iso=/^(\d{4})-(\d{2})-(\d{2})$/.exec(text),local=/^(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{4})$/.exec(text);
 if(iso)return `${iso[3]}/${iso[2]}/${iso[1]}`;
 if(local)return `${local[1].padStart(2,"0")}/${local[2].padStart(2,"0")}/${local[3]}`;
 return formatBirthDigits(text);
}
