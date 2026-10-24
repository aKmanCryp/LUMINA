CREATE OR REPLACE FUNCTION public.submit_payment_notice(p_order_id uuid, p_payer text, p_reference text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_order orders%ROWTYPE; v_existing payment_notices%ROWTYPE; v_dup_count int;
        v_payer text; v_reference text;
BEGIN
SELECT * INTO v_order FROM orders WHERE id = p_order_id AND user_id = auth.uid();
IF NOT FOUND THEN RAISE EXCEPTION 'No se encontró este pedido o no tenés acceso.'; END IF;

-- Only a pending order can receive (or re-receive) a payment notice. This keeps a
-- verified notice from being reset back to 'review', which would launder its reference.
IF v_order.payment_status <> 'pending' THEN
  RAISE EXCEPTION 'Este pedido ya no acepta avisos de pago.';
END IF;

v_payer := btrim(coalesce(p_payer, ''));
v_reference := btrim(coalesce(p_reference, ''));
IF length(v_payer) < 2 OR length(v_payer) > 80 THEN
  RAISE EXCEPTION 'Ingresá el nombre de quien transfirió (2 a 80 caracteres).';
END IF;
IF length(v_reference) < 3 OR length(v_reference) > 60 THEN
  RAISE EXCEPTION 'Ingresá el número de referencia (3 a 60 caracteres).';
END IF;

-- A reference is single use: reject it if it is verified anywhere else, or if it is
-- attached to any other order that is already paid.
SELECT COUNT(*) INTO v_dup_count FROM payment_notices pn
JOIN orders o ON o.id = pn.order_id
WHERE upper(btrim(pn.reference)) = upper(v_reference)
  AND pn.order_id <> p_order_id
  AND (pn.status = 'verified' OR o.payment_status = 'paid');
IF v_dup_count > 0 THEN
  RAISE EXCEPTION 'Esta referencia ya fue verificada en otro pedido. No se puede reutilizar.';
END IF;

INSERT INTO payment_notices (order_id, payer, reference, status)
VALUES (p_order_id, v_payer, v_reference, 'review')
ON CONFLICT (order_id) DO UPDATE SET payer = EXCLUDED.payer, reference = EXCLUDED.reference,
status = 'review', reviewed_by = NULL, reviewed_at = NULL, reject_note = NULL
RETURNING * INTO v_existing;
RETURN jsonb_build_object('ok',true,'message','Aviso registrado. Lo verificaremos en la cuenta receptora. El aviso no confirma el pago.','notice_id',v_existing.id,'status',v_existing.status);
END;
$function$;
