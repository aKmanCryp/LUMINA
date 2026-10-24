import fs from 'node:fs/promises';
import {LEGAL} from '../lib/legal.ts';
const text='# ASTROPY · Políticas para revisión\n\n21/10/2026. Borradores del piloto privado. Completar proveedor, RUC, domicilio y soporte antes de uso comercial. No constituyen garantía de cumplimiento.\n\n'+Object.values(LEGAL).map(doc=>'## '+doc.title+'\n\n'+doc.sections.map(s=>'### '+s.title+'\n\n'+s.body).join('\n\n')).join('\n\n---\n\n');
await fs.writeFile(process.argv[2],text);
