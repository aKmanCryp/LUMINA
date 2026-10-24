import { supabase, type Profile, type OrderRow } from './supabase';
import { dailyFor, dateKey, SIGNS, PRODUCTS, validateOrder, type OrderInput, type Report } from './domain';

export const money = (v: number) => '₲' + new Intl.NumberFormat('es-PY', { maximumFractionDigits: 0 }).format(v);

export function apiUrl(path: string) {
  return `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/${path.replace(/^\//, '')}`;
}

export type Me = {
  id: string;
  name: string;
  email: string;
  referralCode: string;
  admin: boolean;
  mode: string;
};

export type Order = {
  id: string;
  product: OrderInput['product'];
  amount: number;
  discount: number;
  payload: OrderInput;
  paymentStatus: string;
  deliveryStatus: string;
  result: Report | null;
  createdAt: string;
  error: string | null;
  attempts: number;
  mode: string;
};

function toOrder(row: OrderRow): Order {
  return {
    id: row.id,
    product: row.product as OrderInput['product'],
    amount: row.amount,
    discount: row.discount,
    payload: row.payload as unknown as OrderInput,
    paymentStatus: row.payment_status,
    deliveryStatus: row.delivery_status,
    result: (row.result as Report) ?? null,
    createdAt: row.created_at,
    error: row.error,
    attempts: row.attempts,
    mode: row.mode,
  };
}

function referralCode(id: string): string {
  let h = 2166136261;
  for (let i = 0; i < id.length; i++) h = Math.imul(h ^ id.charCodeAt(i), 16777619);
  return (h >>> 0).toString(36).toUpperCase().padEnd(8, '0').slice(0, 8);
}

export async function getMe(): Promise<Me | null> {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session?.user) return null;

  const { data: profile } = await supabase
    .from('profiles')
    .select('id, email, display_name, is_admin')
    .eq('id', session.user.id)
    .maybeSingle();

  if (!profile) return null;

  return {
    id: (profile as Profile).id,
    name: (profile as Profile).display_name ?? (profile as Profile).email,
    email: (profile as Profile).email,
    referralCode: referralCode((profile as Profile).id),
    admin: (profile as Profile).is_admin,
    mode: 'manual_qr',
  };
}

export async function signUp(email: string, password: string, displayName: string): Promise<void> {
  const { data, error } = await supabase.auth.signUp({
    email,
    password,
    options: { data: { display_name: displayName.trim() || undefined } },
  });
  if (error) throw new Error(translateAuthError(error.message));
  // The database trigger create_profile_on_signup() creates the profile row
  // automatically. If email confirmation is enabled, the user must confirm
  // before they can sign in.
  if (data.user && data.session === null) {
    throw new Error('Te enviamos un correo de confirmación. Revisá tu bandeja antes de ingresar.');
  }
}

export async function signIn(email: string, password: string): Promise<void> {
  const { error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) throw new Error(translateAuthError(error.message));
}

export async function signOut(): Promise<void> {
  await supabase.auth.signOut();
}

function translateAuthError(msg: string): string {
  const m = msg.toLowerCase();
  if (m.includes('invalid login')) return 'Correo o contraseña incorrectos.';
  if (m.includes('already registered') || m.includes('already been registered'))
    return 'Ya existe una cuenta con ese correo.';
  if (m.includes('password')) return 'La contraseña debe tener al menos 6 caracteres.';
  if (m.includes('email')) return 'Ingresá un correo válido.';
  if (m.includes('rate limit')) return 'Demasiados intentos. Aguardá un momento.';
  return 'No pudimos completar la solicitud.';
}

export async function request(path: string, body?: unknown, key?: string): Promise<any> {
  // Public endpoints that don't require auth
  if (path === 'daily' && body === undefined) {
    const date = dateKey();
    return { date, items: SIGNS.map((s) => dailyFor(s.id, date)), mode: 'editorial-demo' };
  }
  if (path === 'payments/config' && body === undefined) {
    return { mode: 'demo', contentReady: false, availableAmounts: [] };
  }
  if (path === 'events') {
    return { ok: false, reason: 'backend_not_connected' };
  }

  // Auth-required endpoints
  const { data: { session } } = await supabase.auth.getSession();
  if (!session?.user) throw new Error('Necesitás iniciar sesión para continuar.');

  if (path === 'me' && body === undefined) {
    return getMe();
  }

  if (path === 'orders' && body === undefined) {
    const { data, error } = await supabase
      .from('orders')
      .select('*')
      .eq('user_id', session.user.id)
      .order('created_at', { ascending: false })
      .limit(100);
    if (error) throw new Error('No pudimos cargar tus pedidos.');
    return { orders: (data as OrderRow[]).map(toOrder) };
  }

  if (path === 'orders' && body !== undefined) {
    const input = validateOrder(body);
    const product = PRODUCTS.find((p) => p.id === input.product)!;
    const { data, error } = await supabase
      .from('orders')
      .insert({
        product: input.product,
        payload: input as unknown as Record<string, unknown>,
      })
      .select('*')
      .single();
    if (error) throw new Error('No pudimos guardar tu pedido.');
    return toOrder(data as OrderRow);
  }

  if (path.startsWith('orders/') && !path.includes('/', 'orders/'.length)) {
    const orderId = path.slice('orders/'.length);
    const { data, error } = await supabase
      .from('orders')
      .select('*')
      .eq('id', orderId)
      .eq('user_id', session.user.id)
      .maybeSingle();
    if (error) throw new Error('No pudimos cargar el pedido.');
    if (!data) throw new Error('No se encontró este pedido o no tenés acceso.');
    return toOrder(data as OrderRow);
  }

  // Admin endpoints — still blocked in this phase (no payments/IA yet)
  if (path.startsWith('admin/')) {
    throw new Error('El panel de administración aún no está conectado. Faltan pagos e IA.');
  }

  // Demo payment / retry / PDF — blocked until backend is connected
  if (path.startsWith('demo/') || path.includes('/retry') || path.includes('/pdf') || path.includes('/qr')) {
    throw new Error('Migración a Bolt: faltan conectar pagos e IA. Las compras están desactivadas.');
  }

  throw new Error('Operación no disponible en esta etapa.');
}

export { supabase };
