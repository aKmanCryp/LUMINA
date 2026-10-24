import fs from 'node:fs/promises';
import {demoReport} from '../lib/domain.ts';
import {makePdf} from '../lib/pdf.ts';
const input={product:'premium',name:'Luna Demo',birth:'1998-10-10',theme:'personal',adult:true,terms:true};
const bytes=makePdf(demoReport(input,'EJEMPLO-FICTICIO'),{id:'EJEMPLO-FICTICIO',product:'Experiencia premium - DEMOSTRACION',date:'2026-10-21'});
await fs.writeFile(process.argv[2]||'outputs/example.pdf',bytes);
console.log('PDF generated with fictitious data');
