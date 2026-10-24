/*
# Update admin_get_dashboard with generation status and AI cost

Adds source, ai_cost, delivery_status detail, and generation log entries
to the dashboard response so the admin can monitor generation health.
*/

CREATE OR REPLACE FUNCTION public.admin_get_dashboard()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_qr_codes jsonb; v_notices jsonb; v_orders jsonb; v_pending_count int; v_delivered_count int; v_gen_errors int; v_ai_cost int;
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

RETURN jsonb_build_object('qr_codes',v_qr_codes,'notices',v_notices,'orders',v_orders,
'pending',v_pending_count,'delivered',v_delivered_count,'gen_errors',v_gen_errors,'ai_cost',v_ai_cost);
END;
$function$;
