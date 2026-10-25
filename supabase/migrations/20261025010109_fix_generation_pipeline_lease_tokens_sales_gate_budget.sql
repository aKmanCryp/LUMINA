/*
# Fix generation pipeline: lease tokens, sales gate, atomic budget, authorization

## Problems fixed
1. Double lease: admin_approve_order called start_generation_after_approval (which
   claimed the lease), then the edge function called claim_generation_lease and got null.
   Now approve only marks paid; the worker claims the lease exactly once.
2. fail_generation inserted into generation_log without attempt (NOT NULL violation).
3. No lease token: a stale worker could overwrite a newer worker's result. Now each
   claim returns a unique lease_token that must be presented to complete or fail.
4. start_generation_after_approval was granted to authenticated without ownership or
   admin check. Removed entirely.
5. No sales gate: create_order allowed orders even when sales are disabled. Now a
   sales_enabled setting (default false) gates order creation.
6. No atomic budget reservation: concurrent requests could exceed the budget. Now
   reserve_budget atomically decrements a budget row before each paid call.

## New columns on orders
- lease_token uuid NULL — unique per claim; complete/fail must match it

## New table: app_settings
Key-value store for sales_enabled (bool, default false) and ai_budget_pyg (int, default 0).
Only is_admin() can read/write. The edge function reads via service_role.

## New function: reserve_budget(int) -> boolean
SECURITY DEFINER, service_role only. Atomically decrements the budget if enough
remains. Returns true if reserved, false if exceeded. Uses row-level lock.

## New function: release_budget(int)
Releases budget back if generation failed after reservation but before token usage
was recorded. service_role only.

## Rewritten functions
- claim_generation_lease: returns lease_token; complete/fail require it
- complete_generation: checks lease_token match; returns ok boolean in JSON
- fail_generation: takes lease_token, inserts attempt from orders.attempts
- admin_approve_order: no longer calls start_generation; just marks paid
- create_order: checks sales_enabled before creating

## Removed
- start_generation_after_approval: deleted (no longer needed)
*/

-- Add lease_token column
ALTER TABLE orders ADD COLUMN IF NOT EXISTS lease_token uuid;

-- App settings table for sales gate and budget
CREATE TABLE IF NOT EXISTS app_settings (
  key text PRIMARY KEY,
  value jsonb NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE app_settings ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON app_settings TO authenticated;
GRANT SELECT, INSERT, UPDATE ON app_settings TO service_role;

DROP POLICY IF EXISTS "select_admin_app_settings" ON app_settings;
CREATE POLICY "select_admin_app_settings" ON app_settings FOR SELECT
  TO authenticated USING (is_admin());

-- Default settings: sales disabled, budget zero
INSERT INTO app_settings (key, value) VALUES
  ('sales_enabled', 'false'::jsonb),
  ('ai_budget_pyg', '0'::jsonb)
ON CONFLICT (key) DO NOTHING;

-- Helper to read a setting
CREATE OR REPLACE FUNCTION public.get_setting(p_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_val jsonb;
BEGIN
  SELECT value INTO v_val FROM app_settings WHERE key = p_key;
  RETURN v_val;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.get_setting(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_setting(text) TO authenticated, service_role;

-- Admin function to update a setting
CREATE OR REPLACE FUNCTION public.admin_set_setting(p_key text, p_value jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Solo un administrador puede cambiar la configuración.'; END IF;
  IF p_key NOT IN ('sales_enabled', 'ai_budget_pyg') THEN
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

-- Atomic budget reservation: decrements if enough remains, returns true/false
CREATE OR REPLACE FUNCTION public.reserve_budget(p_cost_pyg int)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_budget int; v_new int;
BEGIN
  SELECT (value::text)::int INTO v_budget FROM app_settings WHERE key = 'ai_budget_pyg' FOR UPDATE;
  IF v_budget IS NULL THEN RETURN false; END IF;
  IF v_budget < p_cost_pyg THEN RETURN false; END IF;
  v_new := v_budget - p_cost_pyg;
  UPDATE app_settings SET value = to_jsonb(v_new), updated_at = now() WHERE key = 'ai_budget_pyg';
  RETURN true;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.reserve_budget(int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reserve_budget(int) TO service_role;

-- Release budget back (if generation failed after reservation)
CREATE OR REPLACE FUNCTION public.release_budget(p_cost_pyg int)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_budget int;
BEGIN
  SELECT (value::text)::int INTO v_budget FROM app_settings WHERE key = 'ai_budget_pyg' FOR UPDATE;
  IF v_budget IS NULL THEN RETURN; END IF;
  UPDATE app_settings SET value = to_jsonb(v_budget + p_cost_pyg), updated_at = now() WHERE key = 'ai_budget_pyg';
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.release_budget(int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.release_budget(int) TO service_role;

-- Drop the old start_generation_after_approval
DROP FUNCTION IF EXISTS public.start_generation_after_approval(uuid);

-- Rewrite claim_generation_lease to return a lease_token
CREATE OR REPLACE FUNCTION public.claim_generation_lease(p_order_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_row orders%ROWTYPE; v_lease timestamptz; v_token uuid;
BEGIN
  v_lease := now() + INTERVAL '2 minutes';
  v_token := gen_random_uuid();

  UPDATE orders
    SET delivery_status = 'generating',
        lease_until = v_lease,
        lease_token = v_token,
        attempts = attempts + 1,
        error = NULL
  WHERE id = p_order_id
    AND payment_status = 'paid'
    AND delivery_status NOT IN ('delivered', 'generating')
    AND attempts < 5
  RETURNING * INTO v_row;

  IF NOT FOUND THEN
    -- Maybe generating with expired lease (worker crashed)
    UPDATE orders
      SET lease_until = v_lease,
          lease_token = v_token,
          attempts = attempts + 1,
          error = NULL
    WHERE id = p_order_id
      AND payment_status = 'paid'
      AND delivery_status = 'generating'
      AND (lease_until IS NULL OR lease_until < now())
      AND attempts < 5
    RETURNING * INTO v_row;
  END IF;

  IF NOT FOUND THEN RETURN null; END IF;

  INSERT INTO generation_log (order_id, attempt, status)
  VALUES (p_order_id, v_row.attempts, 'started');

  RETURN jsonb_build_object(
    'id', v_row.id,
    'product', v_row.product,
    'payload', v_row.payload,
    'attempts', v_row.attempts,
    'lease_token', v_token
  );
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.claim_generation_lease(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.claim_generation_lease(uuid) TO service_role;

-- Rewrite complete_generation with lease_token check
CREATE OR REPLACE FUNCTION public.complete_generation(
  p_order_id uuid,
  p_lease_token uuid,
  p_result jsonb,
  p_source text,
  p_input_tokens int DEFAULT 0,
  p_output_tokens int DEFAULT 0,
  p_cost_pyg int DEFAULT 0,
  p_model text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_updated int; v_attempts int;
BEGIN
  UPDATE orders
    SET result = p_result,
        source = p_source,
        ai_cost = ai_cost + p_cost_pyg,
        delivery_status = 'delivered',
        delivered_at = now(),
        lease_until = NULL,
        lease_token = NULL,
        error = NULL
  WHERE id = p_order_id
    AND payment_status = 'paid'
    AND delivery_status = 'generating'
    AND lease_token = p_lease_token;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated = 0 THEN
    RETURN jsonb_build_object('ok', false, 'message', 'Lease expirado o token inválido. El resultado no se guardó.');
  END IF;

  SELECT attempts INTO v_attempts FROM orders WHERE id = p_order_id;
  INSERT INTO generation_log (order_id, attempt, status, input_tokens, output_tokens, cost_pyg, model)
  VALUES (p_order_id, v_attempts, 'completed', p_input_tokens, p_output_tokens, p_cost_pyg, p_model);

  RETURN jsonb_build_object('ok', true, 'message', 'Lectura entregada.');
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.complete_generation(uuid, uuid, jsonb, text, int, int, int, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_generation(uuid, uuid, jsonb, text, int, int, int, text) TO service_role;

-- Rewrite fail_generation with lease_token check and proper attempt
CREATE OR REPLACE FUNCTION public.fail_generation(p_order_id uuid, p_lease_token uuid, p_error_code text, p_tokens_used int DEFAULT 0)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_attempts int; v_updated int;
BEGIN
  UPDATE orders
    SET delivery_status = 'error',
        lease_until = NULL,
        lease_token = NULL,
        error = p_error_code
  WHERE id = p_order_id
    AND delivery_status = 'generating'
    AND lease_token = p_lease_token;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated = 0 THEN
    -- Token doesn't match — a newer worker owns this order. Do nothing.
    RETURN jsonb_build_object('ok', false, 'message', 'Lease no válido.');
  END IF;

  SELECT attempts INTO v_attempts FROM orders WHERE id = p_order_id;
  INSERT INTO generation_log (order_id, attempt, status, error_code, input_tokens, output_tokens)
  VALUES (p_order_id, v_attempts, 'failed', p_error_code, p_tokens_used, 0);

  RETURN jsonb_build_object('ok', true);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.fail_generation(uuid, uuid, text, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fail_generation(uuid, uuid, text, int) TO service_role;

-- Rewrite admin_approve_order: no longer calls start_generation
CREATE OR REPLACE FUNCTION public.admin_approve_order(p_order_id uuid, p_reference text, p_verified_amount integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_order orders%ROWTYPE; v_notice payment_notices%ROWTYPE; v_dup_count int; v_reference text;
BEGIN
IF NOT is_admin() THEN RAISE EXCEPTION 'Solo un administrador puede aprobar pedidos.'; END IF;
SELECT * INTO v_order FROM orders WHERE id = p_order_id;
IF NOT FOUND THEN RAISE EXCEPTION 'Pedido no encontrado.'; END IF;
IF v_order.payment_status = 'paid' THEN RETURN jsonb_build_object('ok',true,'message','Este pedido ya estaba aprobado.','idempotent',true); END IF;
IF v_order.payment_status != 'pending' THEN RAISE EXCEPTION 'Este pedido no está pendiente de aprobación.'; END IF;

SELECT * INTO v_notice FROM payment_notices WHERE order_id = p_order_id;
IF NOT FOUND OR v_notice.status <> 'review' THEN
  RAISE EXCEPTION 'No hay un aviso de pago en revisión para este pedido.';
END IF;

v_reference := btrim(coalesce(p_reference, ''));
IF upper(v_reference) <> upper(btrim(v_notice.reference)) THEN
  RAISE EXCEPTION 'La referencia no coincide con la que informó la persona.';
END IF;

IF p_verified_amount IS DISTINCT FROM v_order.amount THEN
  RAISE EXCEPTION 'El monto verificado no coincide con el total del pedido.';
END IF;

SELECT COUNT(*) INTO v_dup_count FROM payment_notices pn
JOIN orders o ON o.id = pn.order_id
WHERE upper(btrim(pn.reference)) = upper(v_reference)
  AND pn.order_id <> p_order_id
  AND (pn.status = 'verified' OR o.payment_status = 'paid');
IF v_dup_count > 0 THEN RAISE EXCEPTION 'Esta referencia ya fue usada en otro pedido verificado.'; END IF;

UPDATE orders SET payment_status = 'paid', paid_at = now() WHERE id = p_order_id AND payment_status = 'pending';
IF NOT FOUND THEN RETURN jsonb_build_object('ok',true,'message','Este pedido ya fue aprobado.','idempotent',true); END IF;
UPDATE payment_notices SET status = 'verified', reviewed_by = auth.uid(), reviewed_at = now() WHERE order_id = p_order_id;
INSERT INTO audit_log (action, actor, target_order, detail)
VALUES ('approve_order', auth.uid(), p_order_id, jsonb_build_object('reference', v_reference, 'amount', p_verified_amount));

-- Generation is NOT triggered here. The admin or a background worker calls
-- the deliver-reading edge function, which claims the lease exactly once.
RETURN jsonb_build_object('ok',true,'message','Pago verificado. El pedido fue aprobado.','needs_generation',true);
END;
$function$;

-- Add sales_enabled check to create_order
CREATE OR REPLACE FUNCTION public.create_order(p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
v_product text; v_amount int; v_user_id uuid := auth.uid(); v_row orders%ROWTYPE;
v_prices jsonb := '{"lectura":19000,"compatibilidad":29000,"premium":49000}'::jsonb;
v_name text; v_name2 text; v_birth text; v_birth2 text; v_theme text; v_referral text;
v_clean jsonb; v_sales_enabled jsonb;
BEGIN
IF v_user_id IS NULL THEN RAISE EXCEPTION 'Necesitás iniciar sesión para crear un pedido.'; END IF;
IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN
  RAISE EXCEPTION 'Revisá el formulario.';
END IF;

-- Sales gate: orders are rejected when sales are disabled
v_sales_enabled := public.get_setting('sales_enabled');
IF v_sales_enabled IS NULL OR (v_sales_enabled::text)::boolean IS NOT TRUE THEN
  RAISE EXCEPTION 'Las ventas están pausadas. Aguardá a que el administrador habilite los pedidos.';
END IF;

v_product := p_payload->>'product';
IF v_product IS NULL OR NOT (v_product IN ('lectura','compatibilidad','premium')) THEN
  RAISE EXCEPTION 'Producto no disponible.';
END IF;
v_amount := (v_prices->>v_product)::int;

v_name  := btrim(coalesce(p_payload->>'name',''));
v_birth := p_payload->>'birth';
IF NOT lumina_valid_name(v_name) OR NOT lumina_valid_birth(v_birth) THEN
  RAISE EXCEPTION 'Ingresá un nombre válido y una fecha de nacimiento de una persona mayor de 18 años.';
END IF;

v_theme := p_payload->>'theme';
IF v_theme IS NULL OR NOT (v_theme IN ('amor','trabajo','personal','general')) THEN
  RAISE EXCEPTION 'Seleccioná una temática.';
END IF;

IF (p_payload->>'terms') IS DISTINCT FROM 'true' OR (p_payload->>'adult') IS DISTINCT FROM 'true' THEN
  RAISE EXCEPTION 'Aceptá los términos y confirmá tu mayoría de edad.';
END IF;

v_clean := jsonb_build_object(
  'product', v_product, 'name', v_name, 'birth', v_birth, 'theme', v_theme,
  'terms', true, 'adult', true,
  'marketing', ((p_payload->>'marketing') = 'true')
);

IF v_product = 'compatibilidad' THEN
  v_name2  := btrim(coalesce(p_payload->>'name2',''));
  v_birth2 := p_payload->>'birth2';
  IF NOT lumina_valid_name(v_name2) OR NOT lumina_valid_birth(v_birth2)
     OR (p_payload->>'otherConsent') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'Completá los datos de la segunda persona adulta y confirmá su autorización.';
  END IF;
  v_clean := v_clean || jsonb_build_object('name2', v_name2, 'birth2', v_birth2, 'otherConsent', true);
END IF;

v_referral := p_payload->>'referral';
IF v_referral IS NOT NULL AND v_referral <> '' THEN
  IF v_referral !~ '^[A-Z0-9]{8}$' THEN
    RAISE EXCEPTION 'El código de referido debe tener 8 letras o números.';
  END IF;
  v_clean := v_clean || jsonb_build_object('referral', v_referral);
END IF;

INSERT INTO orders (user_id, product, amount, discount, payload, payment_status, delivery_status, mode)
VALUES (v_user_id, v_product, v_amount, 0, v_clean, 'pending', 'pending', 'manual_qr')
RETURNING * INTO v_row;
RETURN jsonb_build_object('id',v_row.id,'product',v_row.product,'amount',v_row.amount,'discount',v_row.discount,
'payload',v_row.payload,'payment_status',v_row.payment_status,'delivery_status',v_row.delivery_status,
'created_at',v_row.created_at,'error',v_row.error,'attempts',v_row.attempts,'mode',v_row.mode);
END;
$function$;

-- Add admin_get_settings function
CREATE OR REPLACE FUNCTION public.admin_get_settings()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_result jsonb;
BEGIN
IF NOT is_admin() THEN RAISE EXCEPTION 'Solo un administrador puede ver la configuración.'; END IF;
SELECT jsonb_object_agg(key, value) INTO v_result FROM app_settings;
RETURN v_result;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.admin_get_settings() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_get_settings() TO authenticated;

-- Update dashboard to include settings
CREATE OR REPLACE FUNCTION public.admin_get_dashboard()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_qr_codes jsonb; v_notices jsonb; v_orders jsonb; v_pending_count int; v_delivered_count int; v_gen_errors int; v_ai_cost int; v_settings jsonb;
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

RETURN jsonb_build_object('qr_codes',v_qr_codes,'notices',v_notices,'orders',v_orders,
'pending',v_pending_count,'delivered',v_delivered_count,'gen_errors',v_gen_errors,'ai_cost',v_ai_cost,
'settings',v_settings);
END;
$function$;
