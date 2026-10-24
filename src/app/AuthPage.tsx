import { useState, type FormEvent } from 'react';
import { ArrowRight, RefreshCw, LogOut } from 'lucide-react';
import { signIn, signUp, signOut } from '../lib/client';
import type { Me } from '../lib/client';

export function AuthPage({ onAuthed }: { onAuthed: () => void }) {
  const [mode, setMode] = useState<'login' | 'signup'>('login');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [name, setName] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  async function submit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setBusy(true);
    setError('');
    try {
      if (mode === 'signup') {
        await signUp(email.trim(), password, name);
      } else {
        await signIn(email.trim(), password);
      }
      onAuthed();
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="page-wrap auth-page">
      <div className="auth-card">
        <div className="eyebrow">LÚMINA · TU CUENTA</div>
        <h1 className="page-title">
          {mode === 'login' ? <>Ingresá a <em>tu espacio.</em></> : <>Creá <em>tu cuenta.</em></>}
        </h1>
        <p className="page-subtitle">
          {mode === 'login'
            ? 'Ingresá con tu correo y contraseña para ver tus lecturas y pedidos.'
            : 'Registrate con tu correo y una contraseña. Tus lecturas quedan asociadas a tu cuenta.'}
        </p>

        {error && <div className="error-box" role="alert"><span>{error}</span></div>}

        <form onSubmit={submit} className="experience-form">
          {mode === 'signup' && (
            <label>
              Tu nombre o alias
              <input
                name="name"
                maxLength={40}
                autoComplete="off"
                placeholder="Ej. Luna"
                value={name}
                onChange={(e) => setName(e.target.value)}
              />
            </label>
          )}
          <label>
            Correo
            <input
              type="email"
              name="email"
              required
              autoComplete="email"
              placeholder="tu@correo.com"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
            />
          </label>
          <label>
            Contraseña
            <input
              type="password"
              name="password"
              required
              minLength={6}
              autoComplete={mode === 'login' ? 'current-password' : 'new-password'}
              placeholder="Mínimo 6 caracteres"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
            />
          </label>
          <button className="button primary full" disabled={busy} aria-busy={busy}>
            <span>{busy ? 'Procesando…' : mode === 'login' ? 'Ingresar' : 'Crear cuenta'}</span>
            {busy ? <RefreshCw className="cta-spinner" size={18} /> : <ArrowRight size={18} />}
          </button>
        </form>

        <button
          className="text-link auth-toggle"
          onClick={() => { setMode(mode === 'login' ? 'signup' : 'login'); setError(''); }}
        >
          {mode === 'login' ? '¿No tenés cuenta? Registrate' : '¿Ya tenés cuenta? Ingresá'}
        </button>
      </div>
    </main>
  );
}

export function SignOutButton({ me }: { me: Me | null }) {
  if (!me) return null;
  return (
    <button
      className="text-link"
      onClick={async () => { await signOut(); window.location.href = '/'; }}
    >
      <LogOut size={14} /> Cerrar sesión
    </button>
  );
}
