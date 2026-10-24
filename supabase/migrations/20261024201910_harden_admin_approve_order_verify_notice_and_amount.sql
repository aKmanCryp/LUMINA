-- Approval must verify what it claims to verify: a notice must exist for the order,
-- the reference the operator checked must be the one the buyer submitted, and the
-- verified amount must equal the order total.
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

UPDATE orders SET payment_status = 'paid' WHERE id = p_order_id AND payment_status = 'pending';
IF NOT FOUND THEN RETURN jsonb_build_object('ok',true,'message','Este pedido ya fue aprobado.','idempotent',true); END IF;
UPDATE payment_notices SET status = 'verified', reviewed_by = auth.uid(), reviewed_at = now() WHERE order_id = p_order_id;
INSERT INTO audit_log (action, actor, target_order, detail)
VALUES ('approve_order', auth.uid(), p_order_id, jsonb_build_object('reference', v_reference, 'amount', p_verified_amount));
RETURN jsonb_build_object('ok',true,'message','Pago verificado. El pedido fue aprobado.');
END;
$function$;
