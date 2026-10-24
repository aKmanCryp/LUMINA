-- A buyer may only see the payment QR for a pending order they actually own.
CREATE OR REPLACE FUNCTION public.get_qr_for_product(p_product text, p_amount integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_row qr_codes%ROWTYPE; v_allowed boolean;
BEGIN
IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Necesitás iniciar sesión.'; END IF;

SELECT EXISTS (
  SELECT 1 FROM orders o
  WHERE o.user_id = auth.uid()
    AND o.product = p_product
    AND o.amount = p_amount
    AND o.payment_status = 'pending'
) INTO v_allowed;

IF NOT v_allowed AND NOT is_admin() THEN
  RAISE EXCEPTION 'No tenés un pedido pendiente para este plan.';
END IF;

SELECT * INTO v_row FROM qr_codes
WHERE product = p_product AND amount = p_amount AND active = true AND expires_at > now()
ORDER BY created_at DESC LIMIT 1;
IF NOT FOUND THEN RETURN null; END IF;
RETURN jsonb_build_object('id',v_row.id,'slot',v_row.slot,'product',v_row.product,'amount',v_row.amount,
'holder',v_row.holder,'label',v_row.label,'image_data',v_row.image_data,
'generated_at',v_row.generated_at,'expires_at',v_row.expires_at);
END;
$function$;
