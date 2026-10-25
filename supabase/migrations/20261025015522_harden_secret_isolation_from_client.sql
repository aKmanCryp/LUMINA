/*
# Harden secret isolation: cron_secret and project_url must not reach the client

## Problem
Three RPC functions could leak `cron_secret` to any authenticated user:
1. `get_setting(p_key)` — SECURITY DEFINER, callable by any authenticated user,
   returned the value of ANY key in app_settings, including `cron_secret`.
2. `admin_get_settings()` — returned ALL keys including `cron_secret` to the
   admin browser (shown in a password field, but still sent over the wire).
3. `admin_get_dashboard()` — embedded ALL settings (including `cron_secret`)
   in the dashboard response.

`cron_secret` is a server-side shared secret between pg_cron and the
process-queue edge function. It must NEVER be readable from the browser,
even by an admin. The edge function reads it from its own Deno env
(`CRON_SECRET`), not from the database.

## Fix
1. `get_setting` now rejects secret keys (`cron_secret`) with an error. It is
   used internally by edge functions via the service role, which bypasses the
   check anyway — but if called by a client, it refuses to return secrets.
2. `admin_get_settings` now redacts `cron_secret` and `project_url` from the
   returned object. The admin panel cannot read or display the secret.
3. `admin_get_dashboard` now returns only non-secret settings
   (`sales_enabled`, `ai_budget_pyg`) in its `settings` object.
4. `admin_set_setting` no longer accepts `cron_secret` or `project_url` — these
   are managed as edge function secrets / env vars, not through the admin panel.

## Important notes
- `cron_secret` and `project_url` remain in `app_settings` for the cron job to
  read at runtime (via `net.http_post`), but they are no longer readable from
  any client-facing RPC.
- The cron job's inline SQL reads `app_settings` directly (not through RPCs),
  so it is unaffected by the RPC redaction.
- Existing `cron_secret` / `project_url` rows in `app_settings`, if any, are
  left in place — the cron job still reads them.
*/

-- 1. get_setting: reject secret keys when called by non-service roles
CREATE OR REPLACE FUNCTION public.get_setting(p_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_val jsonb; v_is_secret boolean;
BEGIN
  v_is_secret := p_key IN ('cron_secret');
  IF v_is_secret AND current_setting('role', true) NOT IN ('service_role', 'postgres') THEN
    RAISE EXCEPTION 'No tenés permiso para leer esta configuración.';
  END IF;
  SELECT value INTO v_val FROM app_settings WHERE key = p_key;
  RETURN v_val;
END;
$function$;
-- Keep EXECUTE open to authenticated (edge functions call via service role which bypasses)
REVOKE EXECUTE ON FUNCTION public.get_setting(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_setting(text) TO authenticated, service_role;

-- 2. admin_get_settings: redact secrets from the returned object
CREATE OR REPLACE FUNCTION public.admin_get_settings()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_result jsonb;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Solo un administrador puede ver la configuración.'; END IF;
  SELECT jsonb_object_agg(key, value) INTO v_result
  FROM app_settings
  WHERE key NOT IN ('cron_secret', 'project_url');
  RETURN v_result;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_get_settings() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_get_settings() TO authenticated;

-- 3. admin_get_dashboard: return only non-secret settings
CREATE OR REPLACE FUNCTION public.admin_get_dashboard()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_qr_codes jsonb; v_notices jsonb; v_orders jsonb;
  v_pending_count int; v_delivered_count int; v_gen_errors int; v_ai_cost int;
  v_settings jsonb; v_pending_reservations int; v_overspend_pyg int; v_budget_remaining int;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Solo un administrador puede ver el panel.'; END IF;

  SELECT COALESCE(jsonb_agg(row_to_json(q) ORDER BY q.slot), '[]'::jsonb) INTO v_qr_codes
  FROM (SELECT id, slot, product, amount, holder, label, image_data, generated_at, expires_at, active, created_at
  FROM qr_codes WHERE active = true ORDER BY slot) q;

  SELECT COALESCE(jsonb_agg(row_to_json(n)), '[]'::jsonb) INTO v_notices
  FROM (SELECT pn.id, pn.order_id, pn.payer, pn.reference, pn.status, pn.reject_note, pn.created_at, pn.reviewed_at,
  o.product, o.amount, o.mode, u.email as user_email
  FROM payment_notices pn JOIN orders o ON o.id = pn.order_id
  LEFT JOIN auth.users u ON u.id = o.user_id ORDER BY pn.created_at DESC) n;

  SELECT COALESCE(jsonb_agg(row_to_json(o)), '[]'::jsonb) INTO v_orders
  FROM (SELECT o.id, o.product, o.amount, o.payment_status, o.delivery_status, o.mode, o.created_at, o.error, o.attempts,
  o.source, o.ai_cost, o.paid_at, o.delivered_at,
  u.email as user_email FROM orders o LEFT JOIN auth.users u ON u.id = o.user_id
  ORDER BY o.created_at DESC LIMIT 100) o;

  SELECT COUNT(*) INTO v_pending_count FROM orders WHERE payment_status = 'pending';
  SELECT COUNT(*) INTO v_delivered_count FROM orders WHERE delivery_status = 'delivered';
  SELECT COUNT(*) INTO v_gen_errors FROM orders WHERE delivery_status = 'error';
  SELECT COALESCE(SUM(ai_cost), 0) INTO v_ai_cost FROM orders WHERE source = 'openai';
  SELECT jsonb_object_agg(key, value) INTO v_settings
  FROM app_settings WHERE key NOT IN ('cron_secret', 'project_url');

  SELECT COALESCE(SUM(reserved_pyg), 0) INTO v_pending_reservations
  FROM budget_reconciliation WHERE reconciled = false;

  SELECT COALESCE(SUM(GREATEST(actual_pyg - reserved_pyg, 0)), 0) INTO v_overspend_pyg
  FROM budget_reconciliation WHERE reconciled = true AND actual_pyg > reserved_pyg;

  SELECT COALESCE((value::text)::int, 0) INTO v_budget_remaining FROM app_settings WHERE key = 'ai_budget_pyg';

  RETURN jsonb_build_object(
    'qr_codes', v_qr_codes, 'notices', v_notices, 'orders', v_orders,
    'pending', v_pending_count, 'delivered', v_delivered_count,
    'gen_errors', v_gen_errors, 'ai_cost', v_ai_cost,
    'settings', v_settings,
    'pending_reservations', v_pending_reservations,
    'overspend_pyg', v_overspend_pyg,
    'budget_remaining', v_budget_remaining
  );
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_get_dashboard() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_get_dashboard() TO authenticated;

-- 4. admin_set_setting: remove cron_secret and project_url from allowed keys
CREATE OR REPLACE FUNCTION public.admin_set_setting(p_key text, p_value jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Solo un administrador puede cambiar la configuración.'; END IF;
  IF p_key NOT IN ('sales_enabled', 'ai_budget_pyg') THEN
    RAISE EXCEPTION 'Configuración no permitida. cron_secret y project_url se configuran como secretos del backend, no desde el panel.';
  END IF;
  INSERT INTO app_settings (key, value, updated_at)
  VALUES (p_key, p_value, now())
  ON CONFLICT (key) DO UPDATE SET value = excluded.value, updated_at = now();
  RETURN jsonb_build_object('ok', true, 'key', p_key, 'value', p_value);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_set_setting(text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_setting(text, jsonb) TO authenticated;