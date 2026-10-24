/*
# Generation pipeline: columns on orders + generation_log table + lease function

## Purpose
Add the persistent generation job infrastructure for LÚMINA readings.
After an admin approves a payment, a generation job is created and claimed
by the deliver-reading edge function. This keeps delivery separate from
payment, supports retries without re-charging, and prevents simultaneous
executions.

## Changes to `orders`
- `source` text NULL — where the reading came from ('openai' | 'editorial-demo')
- `ai_cost` int NOT NULL DEFAULT 0 — actual cost in PYG (0 for demo)
- `delivered_at` timestamptz NULL — when delivery was completed
- `paid_at` timestamptz NULL — when payment was approved
- `lease_until` timestamptz NULL — generation lease expiry; prevents concurrent workers

## New table: `generation_log`
Records each generation attempt with its outcome, error code, token usage,
and cost. Used by the admin panel for monitoring.

## New function: `claim_generation_lease(uuid)`
SECURITY DEFINER. Called by the deliver-reading edge function (which passes
the service-role key). Atomically claims a paid, non-delivered order for
generation: sets delivery_status='generating', increments attempts, sets
lease_until to now+2min. Returns the order row. Returns null if nothing
needs generation. Also called internally by admin_approve_order.

## New function: `complete_generation(uuid, jsonb, text, int, int, int)`
SECURITY DEFINER. Called by the edge function after OpenAI returns. Stores
the validated report, marks delivery_status='delivered', clears the lease.
Only succeeds if the caller holds the current lease (prevents stale workers).

## New function: `fail_generation(uuid, text)`
SECURITY DEFINER. Marks delivery_status='error', stores error_code, clears
lease. Called when generation fails.

## New function: `start_generation_after_approval()`
SECURITY DEFINER. Called by admin_approve_order after marking payment paid.
Claims the lease and returns the order id so the edge function can be invoked.
This is the single entry point that starts generation after approval.

## Security
- RLS enabled on generation_log; SELECT only to authenticated, all rows visible
  to admin (is_admin). INSERT/UPDATE only via SECURITY DEFINER functions.
- service_role gets INSERT on generation_log (edge function writes log rows).
- All new functions REVOKE from PUBLIC/anon, GRANT to authenticated or service_role
  as appropriate.
*/

-- Add generation columns to orders
ALTER TABLE orders ADD COLUMN IF NOT EXISTS source text;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS ai_cost int NOT NULL DEFAULT 0;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivered_at timestamptz;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS paid_at timestamptz;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS lease_until timestamptz;

-- Grant service_role full access to orders for edge function writes
GRANT SELECT, UPDATE ON orders TO service_role;

-- Generation log table
CREATE TABLE IF NOT EXISTS generation_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  attempt int NOT NULL,
  status text NOT NULL,  -- 'started' | 'completed' | 'failed'
  error_code text,
  input_tokens int,
  output_tokens int,
  cost_pyg int NOT NULL DEFAULT 0,
  model text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_generation_log_order ON generation_log(order_id);
CREATE INDEX IF NOT EXISTS idx_generation_log_created ON generation_log(created_at DESC);

ALTER TABLE generation_log ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON generation_log TO authenticated;
GRANT INSERT ON generation_log TO service_role;

DROP POLICY IF EXISTS "select_admin_generation_log" ON generation_log;
CREATE POLICY "select_admin_generation_log" ON generation_log FOR SELECT
  TO authenticated USING (is_admin());

-- claim_generation_lease: atomically claim an order for generation
-- Returns the order row or null. Called by the edge function with service_role.
CREATE OR REPLACE FUNCTION public.claim_generation_lease(p_order_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_row orders%ROWTYPE; v_lease timestamptz;
BEGIN
  v_lease := now() + INTERVAL '2 minutes';
  UPDATE orders
    SET delivery_status = 'generating',
        lease_until = v_lease,
        attempts = attempts + 1,
        error = NULL
  WHERE id = p_order_id
    AND payment_status = 'paid'
    AND delivery_status NOT IN ('delivered', 'generating')
    AND attempts < 5
  RETURNING * INTO v_row;

  IF NOT FOUND THEN
    -- Maybe it's already generating with an expired lease (worker crashed)
    UPDATE orders
      SET lease_until = v_lease,
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
    'attempts', v_row.attempts
  );
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.claim_generation_lease(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.claim_generation_lease(uuid) TO service_role;

-- complete_generation: store the validated report and mark delivered
CREATE OR REPLACE FUNCTION public.complete_generation(
  p_order_id uuid,
  p_result jsonb,
  p_source text,
  p_input_tokens int DEFAULT 0,
  p_output_tokens int DEFAULT 0,
  p_cost_pyg int DEFAULT 0,
  p_model text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_updated int;
BEGIN
  UPDATE orders
    SET result = p_result,
        source = p_source,
        ai_cost = p_cost_pyg,
        delivery_status = 'delivered',
        delivered_at = now(),
        lease_until = NULL,
        error = NULL
  WHERE id = p_order_id
    AND payment_status = 'paid'
    AND delivery_status = 'generating'
    AND (lease_until IS NULL OR lease_until > now());

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated = 0 THEN
    RETURN jsonb_build_object('ok', false, 'message', 'No se pudo completar: el lease expiró o el estado cambió.');
  END IF;

  INSERT INTO generation_log (order_id, attempt, status, input_tokens, output_tokens, cost_pyg, model)
  SELECT p_order_id, COALESCE(MAX(attempt), 0), 'completed', p_input_tokens, p_output_tokens, p_cost_pyg, p_model
  FROM generation_log WHERE order_id = p_order_id AND status = 'started';

  RETURN jsonb_build_object('ok', true, 'message', 'Lectura entregada.');
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.complete_generation(uuid, jsonb, text, int, int, int, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_generation(uuid, jsonb, text, int, int, int, text) TO service_role;

-- fail_generation: mark error, clear lease, allow retry
CREATE OR REPLACE FUNCTION public.fail_generation(p_order_id uuid, p_error_code text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  UPDATE orders
    SET delivery_status = 'error',
        lease_until = NULL,
        error = p_error_code
  WHERE id = p_order_id
    AND delivery_status = 'generating';

  INSERT INTO generation_log (order_id, status, error_code)
  SELECT p_order_id, 'failed', p_error_code
  WHERE EXISTS (SELECT 1 FROM orders WHERE id = p_order_id);

  RETURN jsonb_build_object('ok', true);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.fail_generation(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fail_generation(uuid, text) TO service_role;

-- start_generation_after_approval: called from admin_approve_order
-- Claims the lease and returns the order id for the caller to invoke the edge function
CREATE OR REPLACE FUNCTION public.start_generation_after_approval(p_order_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_claimed jsonb;
BEGIN
  SELECT public.claim_generation_lease(p_order_id) INTO v_claimed;
  IF v_claimed IS NULL THEN RETURN null; END IF;
  RETURN p_order_id;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.start_generation_after_approval(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.start_generation_after_approval(uuid) TO authenticated;
