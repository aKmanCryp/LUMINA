import {createRoot} from 'react-dom/client';
import AstroApp from './app/AstroApp';
import './app/globals.css';
import './app/reading.css';
const [route='',id='']=window.location.pathname.split('/').filter(Boolean);
const views:Record<string,string>={experiencia:'form','mis-lecturas':'history',resultado:'result',admin:'admin',legal:'legal'};
function LoginPending(){return <main className="page-wrap"><div className="eyebrow">LÚMINA · MIGRACIÓN</div><h1 className="page-title">Conexión de cuenta pendiente</h1><p>El acceso de clientes se conectará durante la migración. Las compras están desactivadas.</p><a className="button primary" href="/">Volver al inicio</a></main>;}
createRoot(document.getElementById('root')!).render(route==='login'?<LoginPending/>:<AstroApp view={route?(views[route]||'404'):'home'} id={id}/>);
