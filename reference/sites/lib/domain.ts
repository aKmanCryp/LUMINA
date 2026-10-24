export const VERSION="2026-10-22.v2",TZ="America/Asuncion";
export const PRODUCTS=[
{id:"lectura",name:"Tu lectura personal",short:"Lectura personal",price:19000,subtitle:"Una pausa para conocerte un poco más.",description:"Una experiencia sobre amor, proyectos o vos, con ideas para llevar a tu día.",features:["Una temática a tu elección","Reflexiones y una pequeña práctica","Lectura guardada y PDF privado"]},
{id:"compatibilidad",name:"Entre dos estrellas",short:"Compatibilidad",price:29000,subtitle:"Dos formas de ser. Una conversación.",description:"Explorá afinidades simbólicas y nuevas maneras de escucharse, sin puntajes ni destinos escritos.",features:["Dos perfiles zodiacales","Afinidades y diferencias simbólicas","Preguntas para conversar y PDF"]},
{id:"premium",name:"Tu universo personal",short:"Experiencia premium",price:49000,subtitle:"Más espacio para explorar tu mundo.",description:"Un recorrido ampliado con ejercicios y un informe para volver a leer. Prototipo del siguiente producto.",features:["Seis módulos de reflexión","Ejercicios interactivos privados","PDF ampliado · sin carta natal"]},
] as const;
export type ProductId=typeof PRODUCTS[number]["id"];
export const SIGNS=[
{id:"aries",name:"Aries",glyph:"♈︎",dates:"21 mar – 19 abr",element:"Fuego",trait:"iniciativa",color:"#e6ab8e",start:321},
{id:"tauro",name:"Tauro",glyph:"♉︎",dates:"20 abr – 20 may",element:"Tierra",trait:"constancia",color:"#b9c796",start:420},
{id:"geminis",name:"Géminis",glyph:"♊︎",dates:"21 may – 20 jun",element:"Aire",trait:"curiosidad",color:"#e7cb8d",start:521},
{id:"cancer",name:"Cáncer",glyph:"♋︎",dates:"21 jun – 22 jul",element:"Agua",trait:"sensibilidad",color:"#b0c7db",start:621},
{id:"leo",name:"Leo",glyph:"♌︎",dates:"23 jul – 22 ago",element:"Fuego",trait:"expresividad",color:"#e3be7c",start:723},
{id:"virgo",name:"Virgo",glyph:"♍︎",dates:"23 ago – 22 sep",element:"Tierra",trait:"atención al detalle",color:"#b5c1ab",start:823},
{id:"libra",name:"Libra",glyph:"♎︎",dates:"23 sep – 22 oct",element:"Aire",trait:"búsqueda de equilibrio",color:"#c5b2e9",start:923},
{id:"escorpio",name:"Escorpio",glyph:"♏︎",dates:"23 oct – 21 nov",element:"Agua",trait:"profundidad",color:"#c59cbf",start:1023},
{id:"sagitario",name:"Sagitario",glyph:"♐︎",dates:"22 nov – 21 dic",element:"Fuego",trait:"exploración",color:"#d3b7ed",start:1122},
{id:"capricornio",name:"Capricornio",glyph:"♑︎",dates:"22 dic – 19 ene",element:"Tierra",trait:"perseverancia",color:"#a7b9c4",start:1222},
{id:"acuario",name:"Acuario",glyph:"♒︎",dates:"20 ene – 18 feb",element:"Aire",trait:"originalidad",color:"#a6ccce",start:120},
{id:"piscis",name:"Piscis",glyph:"♓︎",dates:"19 feb – 20 mar",element:"Agua",trait:"imaginación",color:"#b4b8e5",start:219},
] as const;
export const THEMES={amor:"Amor y relaciones",trabajo:"Trabajo y proyectos",personal:"Reflexión personal",general:"Panorama general"};
export type Theme=keyof typeof THEMES;
export type OrderInput={product:ProductId;name:string;birth:string;theme:Theme;name2?:string;birth2?:string;adult:boolean;terms:boolean;otherConsent?:boolean;marketing?:boolean;referral?:string};
export type Report={title:string;intro:string;sections:{title:string;body:string;prompt:string}[];closing:string;source:string};
export function dateKey(date=new Date()){return new Intl.DateTimeFormat("en-CA",{timeZone:TZ,year:"numeric",month:"2-digit",day:"2-digit"}).format(date);}
export function signFor(birth:string){const [,m,d]=birth.split("-").map(Number),n=m*100+d;return [...SIGNS].sort((a,b)=>b.start-a.start).find(s=>n>=s.start)??SIGNS[9];}
export function validBirth(value:string,today=dateKey()){
 if(!/^\d{4}-\d{2}-\d{2}$/.test(value))return false;const d=new Date(value+"T12:00:00Z");if(Number.isNaN(d.getTime())||d.toISOString().slice(0,10)!==value)return false;
 if(Number(value.slice(0,4))<1900||value>today)return false;const [y,m,day]=today.split("-").map(Number),[by,bm,bd]=value.split("-").map(Number);return y-by-((m<bm||(m===bm&&day<bd))?1:0)>=18;
}
export class AppError extends Error{status:number;constructor(message:string,status=400){super(message);this.status=status;}}
export function validateOrder(x:unknown,today=dateKey()):OrderInput{
 const b=x as OrderInput;if(!b||typeof b!=="object")throw new AppError("Revisá el formulario.");
 if(!PRODUCTS.some(p=>p.id===b.product))throw new AppError("Producto no disponible.");
 const name=(n:unknown)=>typeof n==="string"&&/^[\p{L}\p{M} .’'-]{1,40}$/u.test(n.trim())&&n.trim().length>=2;
 if(!name(b.name)||!validBirth(b.birth??"",today))throw new AppError("Ingresá un nombre válido y una fecha de nacimiento de una persona mayor de 18 años.");
 if(!Object.hasOwn(THEMES,b.theme))throw new AppError("Seleccioná una temática.");
 if(b.terms!==true||b.adult!==true)throw new AppError("Aceptá los términos y confirmá tu mayoría de edad.");
 if(b.product==="compatibilidad"&&(!name(b.name2)||!validBirth(b.birth2??"",today)||b.otherConsent!==true))throw new AppError("Completá los datos de la segunda persona adulta y confirmá su autorización.");
 if(b.referral&&!/^[A-Z0-9]{8}$/.test(b.referral))throw new AppError("El código de referido debe tener 8 letras o números.");
 return {product:b.product,name:b.name.trim(),birth:b.birth,theme:b.theme,...(b.product==="compatibilidad"?{name2:b.name2!.trim(),birth2:b.birth2,otherConsent:true}:{}),terms:true,adult:true,marketing:b.marketing===true,referral:b.referral||undefined};
}
const REL=["Una charla sin apuro puede abrir espacio para entenderse mejor. Probá escuchar hasta el final antes de preparar tu respuesta.","Quizá hoy te resulte útil expresar una necesidad con palabras simples. Dar contexto puede ser más amable que esperar que la otra persona adivine.","Hay valor en los gestos cotidianos. Elegí un detalle que exprese afecto sin esperar una respuesta determinada.","Podés reservar un momento para una conversación pendiente. Preguntar cómo está la otra persona es un buen comienzo.","Poner un límite con respeto también cuida los vínculos. Pensá qué podés ofrecer hoy sin dejarte de lado."];
const WORK=["Elegí una tarea pequeña y terminable. Un primer paso concreto puede ordenar un proyecto que venís postergando.","Dejá un margen para revisar antes de entregar. Una segunda mirada tranquila puede ayudarte a ver alternativas.","Separá lo urgente de lo que simplemente hace ruido. Elegir una prioridad es una práctica, no una prueba de tu valor.","Si una idea necesita aire, anotala antes de evaluarla. Después elegí qué parte vale la pena explorar.","Pedir una aclaración puede ahorrar suposiciones. Buscá un acuerdo concreto sobre el siguiente paso."];
const WELL=["Hacé una pausa que se sienta posible: mirar por la ventana, estirarte suavemente o dejar el teléfono un rato.","Notá cómo llegás a este momento. No hace falta resolverlo todo para darte unos minutos de descanso.","Probá un rato sin compararte. Tu ritmo de hoy puede ser distinto al de ayer.","Recuperá una actividad sencilla que disfrutes por el hecho de hacerla, sin medir el resultado.","Dejá un pequeño espacio libre en tu agenda. Estar disponible para vos también merece lugar."];
const REFLECT=["¿Qué podrías hacer hoy con un poco menos de exigencia?","¿Cuál es la conversación que te gustaría empezar con más curiosidad?","¿Qué parte de tu día depende de una elección pequeña que sí podés hacer?","¿Qué querés conservar y qué podrías dejar descansar esta semana?","¿Qué gesto te haría sentir más en sintonía con lo que valorás?"];
function hash(s:string){let h=2166136261;for(const c of s)h=Math.imul(h^c.charCodeAt(0),16777619);return h>>>0;}
export function dailyFor(signId:string,date=dateKey()){
 const s=SIGNS.find(s=>s.id===signId);if(!s)throw new AppError("Signo no válido.");const seed=hash(date+signId);
 return {date,sign:s.id,title:["Dale espacio a lo que te hace bien.","Volvé a tu propio ritmo.","Las pequeñas pausas también cuentan.","Hay algo nuevo en mirar de nuevo.","Hoy, empezá por vos."][seed%5],sections:[{title:"Relaciones",body:REL[seed%5]},{title:"Trabajo",body:WORK[(seed>>>3)%5]},{title:"Bienestar",body:WELL[(seed>>>6)%5]},{title:"Reflexión",body:REFLECT[(seed>>>9)%5]}],source:"editorial-demo"};
}
export function demoReport(input:OrderInput,orderId:string):Report{
 const s=signFor(input.birth),b=input.birth2?signFor(input.birth2):null,seed=hash(orderId),theme=THEMES[input.theme];
 const intro=`${input.name}, esta lectura usa la ${s.trait} que la tradición asocia con ${s.name} como una invitación simbólica. Tomá lo que te resulte útil y dejá lo que no te represente. Tus decisiones siguen siendo tuyas.`;
 const sections=input.product==="compatibilidad"?[
 {title:`El mundo de ${input.name}`,body:`En el lenguaje recreativo del zodíaco, ${s.name} se vincula con ${s.trait} y el elemento ${s.element.toLowerCase()}. Esto puede ser un punto de partida para conversar, sin definir la personalidad de nadie. Contale a ${input.name2} en qué situaciones te reconocés en esa descripción y en cuáles no.`,prompt:"¿Qué te gustaría que la otra persona entendiera mejor de vos?"},
 {title:`El mundo de ${input.name2}`,body:`A ${b!.name} se le atribuye ${b!.trait}, dentro del elemento ${b!.element.toLowerCase()}. ${input.name2} puede sentirse cerca o lejos de ese símbolo. Preguntar por sus experiencias reales les dará más información que cualquier etiqueta.`,prompt:"¿Qué gesto cotidiano te hace sentir escuchado o escuchada?"},
 {title:"Un punto de encuentro",body:`${s.element===b!.element?"Compartir un elemento ofrece una metáfora de ritmos parecidos.":"Sus elementos distintos ofrecen una metáfora de perspectivas que pueden complementarse."} La afinidad se construye con atención, acuerdos y respeto. Elijan una actividad sencilla que disfruten y conversen sobre qué la hace valiosa para cada persona.`,prompt:"¿Qué disfrutan juntos sin necesidad de hacerlo igual?"},
 {title:"Diferencias que se pueden conversar",body:"Una diferencia de ritmo no demuestra falta de interés. Cuando algo moleste, describan el hecho concreto y lo que necesitan, evitando convertirlo en una definición de la otra persona. Pueden acordar un momento para hablar y una pausa si la conversación se vuelve difícil.",prompt:"Completá: cuando sucede..., me gustaría que pudiéramos..."},
 {title:"Un pequeño acuerdo",body:"Tómense diez minutos con turnos para hablar. Cada persona comparte algo que agradece y una petición posible para esta semana. La otra repite lo que entendió antes de responder. La astrología no determina el futuro de un vínculo ni reemplaza el consentimiento o el respeto.",prompt:"¿Qué acuerdo concreto les gustaría probar esta semana?"},
 ]:[
 {title:"Tu punto de partida",body:`Para explorar ${theme.toLowerCase()}, tomemos ${s.trait} como una imagen y no como una certeza sobre vos. Pensá en una situación reciente en la que esta cualidad te haya servido. Después recordá otra en la que necesitaste una forma diferente de actuar. Esa variedad también forma parte de tu historia.`,prompt:"¿Qué te gustaría entender mejor de este momento?"},
 {title:input.theme==="amor"?"Vínculos con espacio":input.theme==="trabajo"?"Un proyecto a tu ritmo":"Lo que querés cuidar",body:`${input.theme==="amor"?REL[seed%5]:input.theme==="trabajo"?WORK[seed%5]:WELL[seed%5]} En vez de buscar una respuesta definitiva, describí una necesidad actual y una acción pequeña que dependa de vos. No hace falta justificarla con el signo ni compararla con el ritmo de otras personas.`,prompt:REFLECT[seed%5]},
 {title:"Una mirada diferente",body:`La tradición asocia ${s.element.toLowerCase()} con una manera simbólica de acercarse al mundo. Usá esa imagen para imaginar otra perspectiva: ¿qué vería alguien que necesita más tiempo, más información o más espacio? Podés explorar esa pregunta sin negar lo que vos sentís.`,prompt:"¿Qué cambia si mirás la situación desde otra perspectiva?"},
 {title:"Tu práctica de la semana",body:"Elegí una acción breve, concreta y amable: escribir una pregunta, pedir una aclaración o reservar un rato para una conversación. Anotá cuándo te gustaría intentarla. Al terminar la semana, revisá qué aprendiste, incluso si el resultado fue distinto al esperado.",prompt:"Esta semana quiero dar espacio a..."},
 ];
 if(input.product==="premium")sections.push({title:"Tu mapa de prioridades",body:"Dibujá tres círculos: lo que depende de vos, lo que podés conversar y lo que hoy no podés controlar. Elegí una sola idea del primer círculo para empezar. Este ejercicio organiza reflexiones personales y no usa cálculos de planetas ni una carta natal.",prompt:"¿Dónde te gustaría poner tu energía esta semana?"},{title:"Una carta para volver a vos",body:"Escribite unas líneas sobre lo que estás aprendiendo. Podés incluir algo que querés agradecerte y una expectativa que te gustaría soltar. Guardá la carta y volvé a ella cuando te resulte útil. El valor está en tus propias palabras, no en acertar una interpretación.",prompt:"Si pudieras hablarte con más amabilidad, ¿qué te dirías?"});
 return {title:input.product==="compatibilidad"?`${input.name} y ${input.name2}: una conversación entre estrellas`:`Un universo de posibilidades, ${input.name}`,intro,sections,closing:"Una experiencia recreativa para reflexionar. No predice hechos ni sustituye orientación profesional. Contenido de demostración creado con plantillas editoriales.",source:"editorial-demo"};
}
export function safeCsv(value:unknown){let s=String(value??"");if(/^[=+\-@\t\r]/.test(s))s="'"+s;return '"'+s.replaceAll('"','""')+'"';}
