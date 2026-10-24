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

export type QrData = {
  id: string;
  slot: number;
  product: string;
  amount: number;
  holder: string;
  label: string;
  image_data: string;
  generated_at: string;
  expires_at: string;
};

export type PaymentNotice = {
  id: string;
  order_id: string;
  payer: string;
  reference: string;
  status: string;
  reject_note: string | null;
  created_at: string;
  reviewed_at: string | null;
  product: string;
  amount: number;
  mode: string;
  user_email: string;
};

export type AdminDashboard = {
  qr_codes: QrData[];
  notices: PaymentNotice[];
  orders: any[];
  pending: number;
  delivered: number;
  gen_errors?: number;
  ai_cost?: number;
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

function rpcToOrder(data: any): Order {
  return {
    id: data.id,
    product: data.product as OrderInput['product'],
    amount: data.amount,
    discount: data.discount ?? 0,
    payload: data.payload as unknown as OrderInput,
    paymentStatus: data.payment_status,
    deliveryStatus: data.delivery_status,
    result: (data.result as Report) ?? null,
    createdAt: data.created_at,
    error: data.error ?? null,
    attempts: data.attempts ?? 0,
    mode: data.mode,
  };
}

function referralCode(id: string): string {
  let h = 2166136261;
  for (let i = 0; i < id.length; i++) h = Math.imul(h ^ id.charCodeAt(i), 16777619);
  return (h >>> 0).toString(36).toUpperCase().padEnd(8, '0').slice(0, 8);
}

// Trigger the deliver-reading edge function to generate a reading.
// Fire-and-forget: the edge function claims the lease and works asynchronously.
async function triggerDelivery(orderId: string): Promise<void> {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session?.access_token) return;
  const fnUrl = `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/deliver-reading`;
  const resp = await fetch(fnUrl, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${session.access_token}`,
      apikey: import.meta.env.VITE_SUPABASE_ANON_KEY!,
    },
    body: JSON.stringify({ order_id: orderId }),
  });
  if (!resp.ok) {
    console.error('[lumina] deliver-reading responded', resp.status);
  }
}

// Download the PDF for a delivered order via authenticated fetch.
// The edge function verifies JWT ownership; knowing the URL alone is not enough.
export async function downloadPdf(orderId: string): Promise<Blob> {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session?.access_token) throw new Error('Necesitás iniciar sesión para descargar el PDF.');
  const fnUrl = `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/order-pdf/${orderId}`;
  const resp = await fetch(fnUrl, {
    headers: {
      Authorization: `Bearer ${session.access_token}`,
      apikey: import.meta.env.VITE_SUPABASE_ANON_KEY!,
    },
  });
  if (!resp.ok) {
    const body = await resp.json().catch(() => ({}));
    throw new Error(body.error || 'No pudimos generar el PDF.');
  }
  return resp.blob();
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
    // Neutral wording on purpose: confirming that an address has an account would let
    // anyone test a list of emails through this form and build a customer list.
    return 'No pudimos crear la cuenta con esos datos. Si ya tenés una cuenta, ingresá desde el formulario de inicio de sesión o recuperá tu contraseña.';
  if (m.includes('password')) return 'La contraseña debe tener al menos 6 caracteres.';
  if (m.includes('email')) return 'Ingresá un correo válido.';
  if (m.includes('rate limit')) return 'Demasiados intentos. Aguardá un momento.';
  return 'No pudimos completar la solicitud.';
}

// The database raises its own Spanish, user-facing messages for every rule the app
// enforces. Anything else (constraint names, permission denials, PostgREST internals)
// is internal detail and must not reach the screen.
const APP_ERROR_MARKERS = [
  'Solo un administrador',
  'iniciar sesión',
  'Producto no disponible',
  'Revisá el formulario',
  'Ingresá un nombre válido',
  'Seleccioná una temática',
  'Aceptá los términos',
  'Completá los datos de la segunda persona',
  'El código de referido',
  'No se encontró este pedido',
  'Este pedido ya no acepta avisos',
  'Ingresá el nombre de quien transfirió',
  'Ingresá el número de referencia',
  'Esta referencia ya fue',
  'Pedido no encontrado',
  'Este pedido ya estaba aprobado',
  'Este pedido ya fue aprobado',
  'Este pedido no está pendiente',
  'No hay un aviso de pago',
  'El monto verificado no coincide',
  'La referencia no coincide',
  'No tenés un pedido pendiente',
  'El espacio debe ser',
  'Plan no válido',
  'El vencimiento no puede superar',
  'El QR ya está vencido',
  'La imagen del QR no es válida',
  'La imagen del QR es demasiado grande',
  'No hay un QR',
];

function rpcError(error: { message: string }): Error {
  const m = error.message ?? '';
  if (m.includes('Solo un administrador')) return new Error('Necesitás permisos de administrador.');
  if (m.includes('iniciar sesión')) return new Error('Necesitás iniciar sesión para continuar.');
  if (APP_ERROR_MARKERS.some((marker) => m.includes(marker))) return new Error(m);
  console.error('[lumina] error interno:', m);
  return new Error('No pudimos completar la operación. Intentá de nuevo en un momento.');
}

export async function request(path: string, body?: unknown, _key?: string): Promise<any> {
  // Public endpoints
  if (path === 'daily' && body === undefined) {
    const date = dateKey();
    return { date, items: SIGNS.map((s) => dailyFor(s.id, date)), mode: 'editorial-demo' };
  }
  if (path === 'payments/config' && body === undefined) {
    return { mode: 'manual_qr', contentReady: false, availableAmounts: [] };
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

  // List own orders
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

  // Create order via server-side function
  if (path === 'orders' && body !== undefined) {
    const input = validateOrder(body);
    const { data, error } = await supabase.rpc('create_order', {
      p_payload: input as unknown as Record<string, unknown>,
    });
    if (error) throw rpcError(error);
    return rpcToOrder(data);
  }

  // Get single order (ownership enforced by RLS)
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

  // Get QR for order's product/amount
  if (path.includes('/qr') && path.startsWith('orders/')) {
    const orderId = path.split('/')[1];
    // First get the order to know product and amount
    const { data: order, error: orderErr } = await supabase
      .from('orders')
      .select('product, amount, payment_status')
      .eq('id', orderId)
      .eq('user_id', session.user.id)
      .maybeSingle();
    if (orderErr || !order) throw new Error('No se encontró este pedido o no tenés acceso.');
    if ((order as any).payment_status !== 'pending') throw new Error('Este pedido ya no está pendiente de pago.');

    const { data: qr, error: qrErr } = await supabase.rpc('get_qr_for_product', {
      p_product: (order as any).product,
      p_amount: (order as any).amount,
    });
    if (qrErr) throw rpcError(qrErr);
    if (!qr) return { qr: null, message: 'No hay un QR vigente para este importe. Aguardá a que el administrador cargue uno.' };
    return { qr, imageUrl: qr.image_data };
  }

  // Submit payment notice ("Ya pagué")
  if (path.includes('/payment-report') && path.startsWith('orders/') && body !== undefined) {
    const orderId = path.split('/')[1];
    const b = body as { payer: string; reference: string };
    const { data, error } = await supabase.rpc('submit_payment_notice', {
      p_order_id: orderId,
      p_payer: b.payer,
      p_reference: b.reference,
    });
    if (error) throw rpcError(error);
    return data;
  }

  // Get payment notice status for an order
  if (path.includes('/payment-report') && path.startsWith('orders/') && body === undefined) {
    const orderId = path.split('/')[1];
    const { data, error } = await supabase
      .from('payment_notices')
      .select('id, payer, reference, status, reject_note, created_at')
      .eq('order_id', orderId)
      .maybeSingle();
    if (error) throw new Error('No pudimos cargar el aviso de pago.');
    return { report: data };
  }

  // Admin: dashboard
  if (path === 'admin/dashboard') {
    const { data, error } = await supabase.rpc('admin_get_dashboard');
    if (error) throw rpcError(error);
    return {
      qrCodes: (data as AdminDashboard).qr_codes,
      notices: (data as AdminDashboard).notices,
      orders: (data as AdminDashboard).orders,
      pending: (data as AdminDashboard).pending,
      delivered: (data as AdminDashboard).delivered,
      genErrors: (data as AdminDashboard).gen_errors || 0,
      aiCost: (data as AdminDashboard).ai_cost || 0,
      todaySales: 0, todayRevenue: 0, monthRevenue: 0, netBeforeTax: 0,
      monthGross: 0, refunds: 0, fees: 0, adSpend: 0, fixedCosts: 0,
      vatReserve: 0, series: [], month: '', products: [], recurringCustomers: 0,
      referrals: 0, discounts: 0, cac: null, errors: [],
    };
  }

  // Admin: upload QR
  if (path === 'admin/qr' && body !== undefined) {
    const b = body as any;
    const { data, error } = await supabase.rpc('admin_upload_qr', {
      p_slot: b.slot,
      p_product: b.product,
      p_amount: b.amount,
      p_holder: b.holder,
      p_label: b.label,
      p_image_data: b.image,
      p_generated_at: b.generatedAt,
      p_expires_at: b.expiresAt,
    });
    if (error) throw rpcError(error);
    return data;
  }

  // Admin: list QR codes (via dashboard)
  if (path === 'admin/qr' && body === undefined) {
    const { data, error } = await supabase.rpc('admin_get_dashboard');
    if (error) throw rpcError(error);
    return { codes: (data as AdminDashboard).qr_codes, mode: 'manual_qr' };
  }

  // Admin: disable QR
  if (path.match(/^admin\/qr\/\d+\/disable$/)) {
    const slot = Number(path.split('/')[2]);
    const { data, error } = await supabase.rpc('admin_disable_qr', { p_slot: slot });
    if (error) throw rpcError(error);
    return data;
  }

  // Admin: approve order (triggers generation via edge function)
  if (path.startsWith('admin/manual-payment/') && body !== undefined) {
    const orderId = path.split('/')[2];
    const b = body as { action: string; reference: string; amount: number };
    if (b.action === 'approve') {
      const { data, error } = await supabase.rpc('admin_approve_order', {
        p_order_id: orderId,
        p_reference: b.reference,
        p_verified_amount: b.amount,
      });
      if (error) throw rpcError(error);
      // If the RPC started a generation lease, trigger the edge function
      if (data?.generate_order_id) {
        triggerDelivery(data.generate_order_id).catch((e) => console.error('[lumina] delivery trigger failed:', e));
      }
      return data;
    }
    // reject
    const { data, error } = await supabase.rpc('admin_reject_notice', {
      p_order_id: orderId,
      p_note: (b as any).note || 'No se encontró el ingreso.',
    });
    if (error) throw rpcError(error);
    return data;
  }

  // Admin: list payment reports (via dashboard)
  if (path === 'admin/payment-reports') {
    const { data, error } = await supabase.rpc('admin_get_dashboard');
    if (error) throw rpcError(error);
    return { reports: (data as AdminDashboard).notices };
  }

  // Retry generation for a paid order that failed or is stuck
  if (path.includes('/retry') && path.startsWith('orders/') && body !== undefined) {
    const orderId = path.split('/')[1];
    // Verify ownership and status
    const { data: order, error: orderErr } = await supabase
      .from('orders')
      .select('id, payment_status, delivery_status, attempts')
      .eq('id', orderId)
      .eq('user_id', session.user.id)
      .maybeSingle();
    if (orderErr || !order) throw new Error('No se encontró este pedido o no tenés acceso.');
    if ((order as any).payment_status !== 'paid') throw new Error('El pago no está aprobado.');
    if ((order as any).delivery_status === 'delivered') throw new Error('La lectura ya fue entregada.');
    if ((order as any).attempts >= 5) throw new Error('Se alcanzó el límite de intentos. Requiere revisión administrativa.');
    // Trigger delivery edge function
    const result = await triggerDelivery(orderId);
    // Re-fetch the updated order
    const { data: updated, error: fetchErr } = await supabase
      .from('orders')
      .select('*')
      .eq('id', orderId)
      .eq('user_id', session.user.id)
      .maybeSingle();
    if (fetchErr || !updated) throw new Error('No pudimos cargar el estado actualizado.');
    return toOrder(updated as OrderRow);
  }

  // PDF download: authenticated fetch via edge function
  if (path.includes('/pdf') && path.startsWith('orders/')) {
    const orderId = path.split('/')[1];
    return { pdfUrl: apiUrl(`order-pdf/${orderId}`) };
  }

  // Blocked: demo payments
  if (path.startsWith('demo/')) {
    throw new Error('Las ventas públicas siguen desactivadas. Faltan conectar IA y entregas.');
  }

  // Blocked: admin expenses, refund, export
  if (path.startsWith('admin/expenses') || path.startsWith('admin/refund') || path.startsWith('admin/export')) {
    throw new Error('Esta función no está disponible en esta etapa.');
  }

  throw new Error('Operación no disponible en esta etapa.');
}

export { supabase };
