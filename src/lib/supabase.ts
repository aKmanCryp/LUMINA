import { createClient } from '@supabase/supabase-js';

const url = import.meta.env.VITE_SUPABASE_URL;
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

if (!url || !anonKey) {
  throw new Error('Falta la configuración de Supabase en las variables de entorno.');
}

export const supabase = createClient(url, anonKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
  },
});

export type Profile = {
  id: string;
  email: string;
  display_name: string | null;
  is_admin: boolean;
  created_at: string;
};

export type OrderRow = {
  id: string;
  user_id: string;
  product: string;
  amount: number;
  discount: number;
  payload: Record<string, unknown>;
  payment_status: string;
  delivery_status: string;
  result: unknown;
  created_at: string;
  error: string | null;
  attempts: number;
  mode: string;
};
