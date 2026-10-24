import {createRoot} from 'react-dom/client';
import AstroApp from './app/AstroApp';
import './app/globals.css';
import './app/reading.css';
const [route='',id='']=window.location.pathname.split('/').filter(Boolean);
const views:Record<string,string>={experiencia:'form','mis-lecturas':'history',resultado:'result',admin:'admin',legal:'legal'};
function AuthRoute(){return <AstroApp view="auth" />;}
createRoot(document.getElementById('root')!).render(route==='login'?<AuthRoute/>:<AstroApp view={route?(views[route]||'404'):'home'} id={id}/>);
