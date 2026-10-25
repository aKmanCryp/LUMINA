/*
# Complete accounting + cron scheduler

## Accounting fixes
- record_consumption: over-consumption (actual > reserved) records full actual cost,
  releases 0, and tracks overspend in the reconciliation row
- admin_get_dashboard: shows pending_reservations (unreconciled), overspend_pyg,
  and budget_remaining

## Backoff for config errors
- claim_next_queued_order skips orders with config/budget errors for 10 minutes

## Cron scheduler
- Enables pg_cron + pg_net
- Creates a cron job that calls the process-queue edge function every 2 minutes
- The cron job reads the function URL and cron secret from app_settings
- The admin must set 'cron_secret' and 'project_url' in app_settings for the
  cron job to work. If not set, the job runs but the HTTP call fails silently.
*/

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;
GRANT USAGE ON SCHEMA extensions TO postgres, anon, authenticated, service_role;

-- record_consumption: handle over-consumption
CREATE OR REPLACE FUNCTION public.record_consumption(
  p_order_id uuid, p_lease_token uuid, p_actual_cost_pyg int
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_row budget_reconciliation%ROWTYPE; v_release int;
BEGIN
  SELECT * INTO v_row FROM budget_reconciliation
  WHERE order_id = p_order_id AND lease_token = p_lease_token FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'message', 'No hay reserva para este intento.');
  END IF;
  IF v_row.reconciled THEN
    RETURN jsonb_build_object('ok', true, 'message', 'Ya conciliado.', 'idempotent', true);
  END IF;
  v_release := GREATEST(v_row.reserved_pyg - p_actual_cost_pyg, 0);
  IF v_release > 0 THEN
    PERFORM public.release_budget(v_release);
  END IF;
  UPDATE budget_reconciliation
    SET actual_pyg = p_actual_cost_pyg, reconciled = true, reconciled_at = now()
    WHERE order_id = p_order_id AND lease_token = p_lease_token;
  RETURN jsonb_build_object('ok', true, 'released_pyg', v_release,
    'overspend_pyg', GREATEST(p_actual_cost_pyg - v_row.reserved_pyg, 0));
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.record_consumption(uuid, uuid, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_consumption(uuid, uuid, int) TO service_role;

-- claim_next_queued_order: backoff on config errors
CREATE OR REPLACE FUNCTION public.claim_next_queued_order()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_id uuid;
BEGIN
  SELECT id INTO v_id FROM orders
  WHERE payment_status = 'paid'
    AND delivery_status IN ('queued', 'error')
    AND attempts < 5
    AND (
      error IS NULL
      OR error NOT IN ('AI_NOT_CONFIGURED', 'AI_UNKNOWN_MODEL', 'AI_BUDGET_EXCEEDED', 'AI_BUDGET_ZERO')
      OR (lease_until IS NOT NULL AND lease_until < now() - INTERVAL '10 minutes')
    )
  ORDER BY
    CASE WHEN delivery_status = 'queued' THEN 0 ELSE 1 END,
    paid_at ASC NULLS LAST, created_at ASC
  LIMIT 1
  FOR UPDATE SKIP LOCKED;

  IF v_id IS NULL THEN RETURN null; END IF;
  RETURN public.claim_generation_lease(v_id);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.claim_next_queued_order() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.claim_next_queued_order() TO service_role;

-- admin_get_dashboard with pending reservations and overspend
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
SELECT jsonb_object_agg(key, value) INTO v_settings FROM app_settings;

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

-- Add cron_secret and anon_key to allowed settings
CREATE OR REPLACE FUNCTION public.admin_set_setting(p_key text, p_value jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Solo un administrador puede cambiar la configuración.'; END IF;
  IF p_key NOT IN ('sales_enabled', 'ai_budget_pyg', 'cron_secret', 'project_url') THEN
    RAISE EXCEPTION 'Configuración no permitida.';
  END IF;
  INSERT INTO app_settings (key, value, updated_at)
  VALUES (p_key, p_value, now())
  ON CONFLICT (key) DO UPDATE SET value = excluded.value, updated_at = now();
  RETURN jsonb_build_object('ok', true, 'key', p_key, 'value', p_value);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_set_setting(text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_setting(text, jsonb) TO authenticated;

-- Create the cron job. It reads the function URL and secret from app_settings
-- at runtime, so no secrets are hardcoded.
-- The admin must set 'project_url' (e.g., 'abcdefgh.supabase.co') and
-- 'cron_secret' in app_settings for the cron job to authenticate.
-- The process-queue function checks the X-Cron-Secret header.
SELECT cron.schedule(
  'process-generation-queue',
  '*/2 * * * *',
  $cron$
  SELECT net.http_post(
    url := 'https://' || COALESCE(
      (SELECT value::text FROM app_settings WHERE key = 'project_url'),
      'localhost'
    ) || '/functions/v1/process-queue',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'X-Cron-Secret', COALESCE(
        (SELECT value::text FROM app_settings WHERE key = 'cron_secret'),
        ''
      )
    ),
    body := '{}'::jsonb
  )
  $cron$
);
