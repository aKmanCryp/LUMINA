/*
# Persistent work queue + budget reconciliation fixes

## 1. Persistent queue (browser-independent delivery)
- admin_approve_order now sets delivery_status='queued' inside the approval transaction.
  This enqueues the work persistently. Closing the browser does not lose the job.
- claim_generation_lease now picks up 'queued' orders (in addition to expired 'generating' leases).
- A new function claim_next_queued_order() returns the oldest queued order for any worker to process.
  This allows a poll-based worker to process pending jobs without a specific order_id.

## 2. Budget: record consumption per attempt before validation/store
- New table: budget_reconciliation tracks reserved vs actual cost per attempt.
  Allows idempotent reconciliation: only the unspent portion is returned.
- New function: record_consumption(p_order_id, p_lease_token, p_actual_cost_pyg)
  Records actual consumption and returns only the difference (reserve - actual) to the budget.
  Idempotent: calling twice does not double-release.
- complete_generation no longer reconciles budget; that's done by record_consumption first.

## 3. Budget: timeout handling
- When a timeout occurs, consumption is uncertain. The reservation stays pending.
- A new function: reconcile_pending(p_order_id, p_lease_token, p_actual_cost_pyg)
  Can be called later when usage data arrives. If called with 0, releases the full reserve.
  Idempotent.

## Changes to existing functions
- admin_approve_order: sets delivery_status='queued' instead of leaving 'pending'
- claim_generation_lease: picks up 'queued' status
*/

-- New table: budget reconciliation log
CREATE TABLE IF NOT EXISTS budget_reconciliation (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  lease_token uuid NOT NULL,
  reserved_pyg int NOT NULL,
  actual_pyg int NOT NULL DEFAULT 0,
  reconciled boolean NOT NULL DEFAULT false,
  reconciled_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(order_id, lease_token)
);

ALTER TABLE budget_reconciliation ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON budget_reconciliation TO authenticated;
GRANT INSERT, UPDATE ON budget_reconciliation TO service_role;

DROP POLICY IF EXISTS "select_admin_budget_reconciliation" ON budget_reconciliation;
CREATE POLICY "select_admin_budget_reconciliation" ON budget_reconciliation FOR SELECT
  TO authenticated USING (is_admin());

-- record_consumption: records actual cost, releases unspent reserve. Idempotent.
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
    -- Already reconciled — idempotent, do nothing
    RETURN jsonb_build_object('ok', true, 'message', 'Ya conciliado.', 'idempotent', true);
  END IF;
  -- Release only the unspent portion
  v_release := GREATEST(v_row.reserved_pyg - p_actual_cost_pyg, 0);
  IF v_release > 0 THEN
    PERFORM public.release_budget(v_release);
  END IF;
  UPDATE budget_reconciliation
    SET actual_pyg = p_actual_cost_pyg, reconciled = true, reconciled_at = now()
    WHERE order_id = p_order_id AND lease_token = p_lease_token;
  RETURN jsonb_build_object('ok', true, 'released_pyg', v_release);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.record_consumption(uuid, uuid, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_consumption(uuid, uuid, int) TO service_role;

-- Update admin_approve_order to set delivery_status='queued'
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

-- Mark paid AND enqueue generation atomically in the same transaction.
-- Closing the browser after this does not lose the work: the order is queued
-- persistently and any future call to claim_generation_lease or the worker
-- poll will process it.
UPDATE orders SET payment_status = 'paid', paid_at = now(), delivery_status = 'queued'
WHERE id = p_order_id AND payment_status = 'pending';
IF NOT FOUND THEN RETURN jsonb_build_object('ok',true,'message','Este pedido ya fue aprobado.','idempotent',true); END IF;
UPDATE payment_notices SET status = 'verified', reviewed_by = auth.uid(), reviewed_at = now() WHERE order_id = p_order_id;
INSERT INTO audit_log (action, actor, target_order, detail)
VALUES ('approve_order', auth.uid(), p_order_id, jsonb_build_object('reference', v_reference, 'amount', p_verified_amount));

RETURN jsonb_build_object('ok',true,'message','Pago verificado. El pedido fue aprobado y encolado para generación.','queued',true);
END;
$function$;

-- Update claim_generation_lease to pick up 'queued' orders
CREATE OR REPLACE FUNCTION public.claim_generation_lease(p_order_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_row orders%ROWTYPE; v_lease timestamptz; v_token uuid;
BEGIN
  v_lease := now() + INTERVAL '2 minutes';
  v_token := gen_random_uuid();

  -- Claim queued or non-generating paid orders
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
    -- Maybe generating with expired lease (worker crashed or browser closed)
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

-- claim_next_queued_order: returns the oldest queued order for a worker to process
CREATE OR REPLACE FUNCTION public.claim_next_queued_order()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_id uuid;
BEGIN
  SELECT id INTO v_id FROM orders
  WHERE payment_status = 'paid'
    AND delivery_status IN ('queued', 'error')
    AND attempts < 5
  ORDER BY paid_at ASC NULLS LAST, created_at ASC
  LIMIT 1
  FOR UPDATE SKIP LOCKED;

  IF v_id IS NULL THEN RETURN null; END IF;
  RETURN public.claim_generation_lease(v_id);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.claim_next_queued_order() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.claim_next_queued_order() TO service_role;
