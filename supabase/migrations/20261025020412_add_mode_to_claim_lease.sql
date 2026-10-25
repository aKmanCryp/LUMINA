/*
# Add mode to claim_generation_lease return value

## Why
The process-queue edge function needs to know the order's `mode` to decide
whether to use simulation. Simulation must only apply to `mode='test'` orders.
Real orders (mode='qr' or any other value) must never receive simulated content,
even when SIMULATION_MODE is active.

## Changes
- `claim_generation_lease` now includes `mode` in its returned JSON object.
- `claim_next_queued_order` delegates to `claim_generation_lease`, so it also
  returns `mode` automatically — no change needed to that function.

## Security
- No new grants or policies. `mode` is an existing column on `orders`.
- The function is SECURITY DEFINER, callable by service_role (edge function)
  and authenticated (deliver-reading edge function with JWT). Both are
  server-side contexts.
*/

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
    AND delivery_status IN ('queued', 'error', 'pending')
    AND attempts < 5
  RETURNING * INTO v_row;

  IF NOT FOUND THEN
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
    'lease_token', v_token,
    'mode', v_row.mode
  );
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.claim_generation_lease(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.claim_generation_lease(uuid) TO authenticated, service_role;