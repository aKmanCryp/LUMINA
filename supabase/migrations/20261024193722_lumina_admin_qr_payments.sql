/*
# Admin panel, QR codes, payment notices, server-side order creation

## Purpose
Implements the full QR payment + admin verification flow:
1. Orders created via SECURITY DEFINER function — server sets price.
2. Clients cannot set amount, user_id, or statuses.
3. Admin uploads up to 3 QR codes, each assigned to a plan.
4. Clients see only active QR matching their product's exact price.
5. "Ya pagué" creates a payment notice — never approves the order.
6. Only admin can approve orders after verifying payment.
7. References cannot be reused across verified orders.
8. Approval is atomic and idempotent.
9. QR codes expire max 4 hours from original generation.

## New Tables: qr_codes, payment_notices, audit_log
## New Functions: create_order, get_qr_for_product, submit_payment_notice,
  admin_approve_order, admin_reject_notice, admin_upload_qr, admin_disable_qr,
  admin_get_dashboard
## Security: orders INSERT revoked from clients; all writes via SECURITY DEFINER functions.
*/

-- === qr_codes table ===
CREATE TABLE IF NOT EXISTS qr_codes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slot integer NOT NULL UNIQUE CHECK (slot BETWEEN 1 AND 3),
  product text NOT NULL CHECK (product IN ('lectura','compatibilidad','premium')),
  amount integer NOT NULL CHECK (amount > 0),
  holder text NOT NULL,
  label text NOT NULL DEFAULT 'Mango',
  image_data text NOT NULL,
  generated_at timestamptz NOT NULL,
  expires_at timestamptz NOT NULL,
  active boolean NOT NULL DEFAULT true,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  replaced_at timestamptz
);

ALTER TABLE qr_codes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "select_admin_qr_codes" ON qr_codes;
CREATE POLICY "select_admin_qr_codes" ON qr_codes FOR SELECT TO authenticated USING (is_admin());

DROP POLICY IF EXISTS "insert_admin_qr_codes" ON qr_codes;
CREATE POLICY "insert_admin_qr_codes" ON qr_codes FOR INSERT TO authenticated WITH CHECK (is_admin());

DROP POLICY IF EXISTS "update_admin_qr_codes" ON qr_codes;
CREATE POLICY "update_admin_qr_codes" ON qr_codes FOR UPDATE TO authenticated USING (is_admin()) WITH CHECK (is_admin());

DROP POLICY IF EXISTS "delete_admin_qr_codes" ON qr_codes;
CREATE POLICY "delete_admin_qr_codes" ON qr_codes FOR DELETE TO authenticated USING (is_admin());

GRANT SELECT, INSERT, UPDATE, DELETE ON qr_codes TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON qr_codes TO service_role;

-- === payment_notices table ===
CREATE TABLE IF NOT EXISTS payment_notices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  payer text NOT NULL,
  reference text NOT NULL,
  status text NOT NULL DEFAULT 'review' CHECK (status IN ('review','verified','rejected')),
  reviewed_by uuid,
  reviewed_at timestamptz,
  reject_note text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_payment_notices_order ON payment_notices(order_id);

ALTER TABLE payment_notices ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "select_own_payment_notices" ON payment_notices;
CREATE POLICY "select_own_payment_notices" ON payment_notices FOR SELECT TO authenticated
  USING (is_admin() OR EXISTS (SELECT 1 FROM orders o WHERE o.id = payment_notices.order_id AND o.user_id = auth.uid()));

GRANT SELECT ON payment_notices TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON payment_notices TO service_role;

-- === audit_log table ===
CREATE TABLE IF NOT EXISTS audit_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  action text NOT NULL,
  actor uuid,
  target_order uuid,
  target_qr uuid,
  detail jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "select_admin_audit_log" ON audit_log;
CREATE POLICY "select_admin_audit_log" ON audit_log FOR SELECT TO authenticated USING (is_admin());

GRANT SELECT ON audit_log TO authenticated;
GRANT SELECT, INSERT ON audit_log TO service_role;

-- === Revoke direct INSERT on orders from authenticated ===
REVOKE INSERT (product, payload) ON orders FROM authenticated;

-- === Function: create_order ===
CREATE OR REPLACE FUNCTION create_order(p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_product text; v_amount int; v_user_id uuid := auth.uid(); v_row orders%ROWTYPE;
  v_prices jsonb := '{"lectura":19000,"compatibilidad":29000,"premium":49000}'::jsonb;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Necesitás iniciar sesión para crear un pedido.'; END IF;
  v_product := p_payload->>'product';
  IF v_product IS NULL OR NOT (v_product IN ('lectura','compatibilidad','premium')) THEN
    RAISE EXCEPTION 'Producto no disponible.';
  END IF;
  v_amount := (v_prices->>v_product)::int;
  INSERT INTO orders (user_id, product, amount, discount, payload, payment_status, delivery_status, mode)
  VALUES (v_user_id, v_product, v_amount, 0, p_payload, 'pending', 'pending', 'manual_qr')
  RETURNING * INTO v_row;
  RETURN jsonb_build_object('id',v_row.id,'product',v_row.product,'amount',v_row.amount,'discount',v_row.discount,
    'payload',v_row.payload,'payment_status',v_row.payment_status,'delivery_status',v_row.delivery_status,
    'created_at',v_row.created_at,'error',v_row.error,'attempts',v_row.attempts,'mode',v_row.mode);
END;
$$;
REVOKE EXECUTE ON FUNCTION create_order(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION create_order(jsonb) TO authenticated;

-- === Function: get_qr_for_product ===
CREATE OR REPLACE FUNCTION get_qr_for_product(p_product text, p_amount int)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_row qr_codes%ROWTYPE;
BEGIN
  SELECT * INTO v_row FROM qr_codes
  WHERE product = p_product AND amount = p_amount AND active = true AND expires_at > now()
  ORDER BY created_at DESC LIMIT 1;
  IF NOT FOUND THEN RETURN null; END IF;
  RETURN jsonb_build_object('id',v_row.id,'slot',v_row.slot,'product',v_row.product,'amount',v_row.amount,
    'holder',v_row.holder,'label',v_row.label,'image_data',v_row.image_data,
    'generated_at',v_row.generated_at,'expires_at',v_row.expires_at);
END;
$$;
REVOKE EXECUTE ON FUNCTION get_qr_for_product(text, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_qr_for_product(text, int) TO authenticated;

-- === Function: submit_payment_notice ===
CREATE OR REPLACE FUNCTION submit_payment_notice(p_order_id uuid, p_payer text, p_reference text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_order orders%ROWTYPE; v_existing payment_notices%ROWTYPE; v_dup_count int;
BEGIN
  SELECT * INTO v_order FROM orders WHERE id = p_order_id AND user_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'No se encontró este pedido o no tenés acceso.'; END IF;
  SELECT COUNT(*) INTO v_dup_count FROM payment_notices pn
  WHERE pn.reference = p_reference AND pn.order_id != p_order_id AND pn.status = 'verified';
  IF v_dup_count > 0 THEN RAISE EXCEPTION 'Esta referencia ya fue verificada en otro pedido. No se puede reutilizar.'; END IF;
  INSERT INTO payment_notices (order_id, payer, reference, status)
  VALUES (p_order_id, p_payer, p_reference, 'review')
  ON CONFLICT (order_id) DO UPDATE SET payer = EXCLUDED.payer, reference = EXCLUDED.reference,
    status = 'review', reviewed_by = NULL, reviewed_at = NULL, reject_note = NULL
  RETURNING * INTO v_existing;
  RETURN jsonb_build_object('ok',true,'message','Aviso registrado. Lo verificaremos en la cuenta receptora. El aviso no confirma el pago.','notice_id',v_existing.id,'status',v_existing.status);
END;
$$;
REVOKE EXECUTE ON FUNCTION submit_payment_notice(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION submit_payment_notice(uuid, text, text) TO authenticated;

-- === Function: admin_approve_order ===
CREATE OR REPLACE FUNCTION admin_approve_order(p_order_id uuid, p_reference text, p_verified_amount int)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_order orders%ROWTYPE; v_dup_count int;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Solo un administrador puede aprobar pedidos.'; END IF;
  SELECT * INTO v_order FROM orders WHERE id = p_order_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Pedido no encontrado.'; END IF;
  IF v_order.payment_status = 'paid' THEN RETURN jsonb_build_object('ok',true,'message','Este pedido ya estaba aprobado.','idempotent',true); END IF;
  IF v_order.payment_status != 'pending' THEN RAISE EXCEPTION 'Este pedido no está pendiente de aprobación.'; END IF;
  SELECT COUNT(*) INTO v_dup_count FROM payment_notices
  WHERE reference = p_reference AND order_id != p_order_id AND status = 'verified';
  IF v_dup_count > 0 THEN RAISE EXCEPTION 'Esta referencia ya fue usada en otro pedido verificado.'; END IF;
  UPDATE orders SET payment_status = 'paid' WHERE id = p_order_id AND payment_status = 'pending';
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',true,'message','Este pedido ya fue aprobado.','idempotent',true); END IF;
  UPDATE payment_notices SET status = 'verified', reviewed_by = auth.uid(), reviewed_at = now() WHERE order_id = p_order_id;
  INSERT INTO audit_log (action, actor, target_order, detail)
  VALUES ('approve_order', auth.uid(), p_order_id, jsonb_build_object('reference', p_reference, 'amount', p_verified_amount));
  RETURN jsonb_build_object('ok',true,'message','Pago verificado. El pedido fue aprobado.');
END;
$$;
REVOKE EXECUTE ON FUNCTION admin_approve_order(uuid, text, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_approve_order(uuid, text, int) TO authenticated;

-- === Function: admin_reject_notice ===
CREATE OR REPLACE FUNCTION admin_reject_notice(p_order_id uuid, p_note text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Solo un administrador puede rechazar avisos.'; END IF;
  UPDATE payment_notices SET status = 'rejected', reviewed_by = auth.uid(), reviewed_at = now(), reject_note = p_note
  WHERE order_id = p_order_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'No hay aviso para este pedido.'; END IF;
  INSERT INTO audit_log (action, actor, target_order, detail)
  VALUES ('reject_notice', auth.uid(), p_order_id, jsonb_build_object('note', p_note));
  RETURN jsonb_build_object('ok',true,'message','Aviso devuelto para revisión.');
END;
$$;
REVOKE EXECUTE ON FUNCTION admin_reject_notice(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_reject_notice(uuid, text) TO authenticated;

-- === Function: admin_upload_qr ===
CREATE OR REPLACE FUNCTION admin_upload_qr(
  p_slot int, p_product text, p_amount int, p_holder text, p_label text,
  p_image_data text, p_generated_at timestamptz, p_expires_at timestamptz
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_old_id uuid; v_new_id uuid; v_max_expiry timestamptz;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Solo un administrador puede cargar QR.'; END IF;
  IF p_slot NOT BETWEEN 1 AND 3 THEN RAISE EXCEPTION 'El espacio debe ser 1, 2 o 3.'; END IF;
  IF p_product NOT IN ('lectura','compatibilidad','premium') THEN RAISE EXCEPTION 'Plan no válido.'; END IF;
  v_max_expiry := p_generated_at + INTERVAL '4 hours';
  IF p_expires_at > v_max_expiry THEN RAISE EXCEPTION 'El vencimiento no puede superar las 4 horas desde la generación original.'; END IF;
  IF p_expires_at <= now() THEN RAISE EXCEPTION 'El QR ya está vencido.'; END IF;
  UPDATE qr_codes SET active = false, replaced_at = now() WHERE slot = p_slot AND active = true RETURNING id INTO v_old_id;
  INSERT INTO qr_codes (slot, product, amount, holder, label, image_data, generated_at, expires_at, active, created_by)
  VALUES (p_slot, p_product, p_amount, p_holder, p_label, p_image_data, p_generated_at, p_expires_at, true, auth.uid())
  RETURNING id INTO v_new_id;
  INSERT INTO audit_log (action, actor, target_qr, detail)
  VALUES ('qr_upload', auth.uid(), v_new_id, jsonb_build_object('slot', p_slot, 'product', p_product, 'amount', p_amount, 'replaced', v_old_id));
  RETURN jsonb_build_object('ok',true,'id',v_new_id,'message','QR guardado.');
END;
$$;
REVOKE EXECUTE ON FUNCTION admin_upload_qr(int, text, int, text, text, text, timestamptz, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_upload_qr(int, text, int, text, text, text, timestamptz, timestamptz) TO authenticated;

-- === Function: admin_disable_qr ===
CREATE OR REPLACE FUNCTION admin_disable_qr(p_slot int)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Solo un administrador puede retirar QR.'; END IF;
  UPDATE qr_codes SET active = false WHERE slot = p_slot AND active = true RETURNING id INTO v_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'No hay un QR activo en ese espacio.'; END IF;
  INSERT INTO audit_log (action, actor, target_qr, detail)
  VALUES ('qr_disable', auth.uid(), v_id, jsonb_build_object('slot', p_slot));
  RETURN jsonb_build_object('ok',true,'message','QR retirado del checkout.');
END;
$$;
REVOKE EXECUTE ON FUNCTION admin_disable_qr(int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_disable_qr(int) TO authenticated;

-- === Function: admin_get_dashboard ===
CREATE OR REPLACE FUNCTION admin_get_dashboard()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_qr_codes jsonb; v_notices jsonb; v_orders jsonb; v_pending_count int; v_delivered_count int;
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
        u.email as user_email FROM orders o LEFT JOIN auth.users u ON u.id = o.user_id
        ORDER BY o.created_at DESC LIMIT 100) o;

  SELECT COUNT(*) INTO v_pending_count FROM orders WHERE payment_status = 'pending';
  SELECT COUNT(*) INTO v_delivered_count FROM orders WHERE delivery_status = 'delivered';

  RETURN jsonb_build_object('qr_codes',v_qr_codes,'notices',v_notices,'orders',v_orders,
    'pending',v_pending_count,'delivered',v_delivered_count);
END;
$$;
REVOKE EXECUTE ON FUNCTION admin_get_dashboard() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_get_dashboard() TO authenticated;

-- === Indexes ===
CREATE INDEX IF NOT EXISTS idx_qr_codes_product_amount_active ON qr_codes(product, amount, active);
CREATE INDEX IF NOT EXISTS idx_payment_notices_status ON payment_notices(status);
CREATE INDEX IF NOT EXISTS idx_payment_notices_reference ON payment_notices(reference);
CREATE INDEX IF NOT EXISTS idx_audit_log_actor ON audit_log(actor);