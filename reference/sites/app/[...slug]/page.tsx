import AstroApp from "../AstroApp";
export const dynamic="force-dynamic";
export default async function Page({params}:{params:Promise<{slug:string[]}>}){const {slug}=await params;const map:Record<string,string>={experiencia:"form","mis-lecturas":"history",resultado:"result",admin:"admin",legal:"legal"};return <AstroApp view={map[slug[0]]||"404"} id={slug[1]||""}/>;}
