import assert from 'node:assert/strict';
import {birthIsoFromDisplay,formatBirthDigits,normalizeBirthPaste} from '../lib/birth-date.ts';
const cases=[
 ['day before month',()=>assert.equal(birthIsoFromDisplay('03/11/1998'),'1998-11-03')],
 ['last day of year',()=>assert.equal(birthIsoFromDisplay('31/12/1990'),'1990-12-31')],
 ['leap year',()=>assert.equal(birthIsoFromDisplay('29/02/2000'),'2000-02-29')],
 ['century is not leap',()=>assert.equal(birthIsoFromDisplay('29/02/1900'),null)],
 ['impossible day',()=>assert.equal(birthIsoFromDisplay('31/11/1998'),null)],
 ['US format rejected',()=>assert.equal(birthIsoFromDisplay('12/31/1998'),null)],
 ['incomplete year',()=>assert.equal(birthIsoFromDisplay('31/12/98'),null)],
 ['no extra characters',()=>assert.equal(birthIsoFromDisplay('31/12/1998x'),null)],
 ['digits become day-month-year',()=>assert.equal(formatBirthDigits('31121998'),'31/12/1998')],
 ['partial input can be edited',()=>assert.equal(formatBirthDigits('31/1'),'31/1')],
 ['ISO paste',()=>assert.equal(normalizeBirthPaste('1998-11-03'),'03/11/1998')],
 ['short date paste',()=>assert.equal(normalizeBirthPaste('3/1/1998'),'03/01/1998')],
];
for(const [name,test] of cases){test();}
console.log('PASS: '+cases.length+' date-format and calendar boundary checks');
