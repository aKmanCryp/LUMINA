import { api } from "../../../lib/server";
export const dynamic="force-dynamic";
export async function GET(request:Request,{params}:{params:Promise<{path:string[]}>}){return api(request,(await params).path);}
export async function POST(request:Request,{params}:{params:Promise<{path:string[]}>}){return api(request,(await params).path);}
