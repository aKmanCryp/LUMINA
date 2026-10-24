-- The QR image is rendered in an <img> and offered as a download link to every buyer,
-- so the stored value must be a bounded image data URL and not an arbitrary string.
CREATE OR REPLACE FUNCTION public.admin_upload_qr(p_slot integer, p_product text, p_amount integer, p_holder text, p_label text, p_image_data text, p_generated_at timestamp with time zone, p_expires_at timestamp with time zone)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_old_id uuid; v_new_id uuid; v_max_expiry timestamptz;
        v_holder text; v_label text; v_prices jsonb := '{"lectura":19000,"compatibilidad":29000,"premium":49000}'::jsonb;
BEGIN
IF NOT is_admin() THEN RAISE EXCEPTION 'Solo un administrador puede cargar QR.'; END IF;
IF p_slot NOT BETWEEN 1 AND 3 THEN RAISE EXCEPTION 'El espacio debe ser 1, 2 o 3.'; END IF;
IF p_product NOT IN ('lectura','compatibilidad','premium') THEN RAISE EXCEPTION 'Plan no válido.'; END IF;

-- The amount always comes from the server-side price list, never from the caller.
p_amount := (v_prices->>p_product)::int;

v_holder := btrim(coalesce(p_holder, ''));
v_label  := btrim(coalesce(p_label, ''));
IF length(v_holder) < 3 OR length(v_holder) > 80 THEN RAISE EXCEPTION 'El titular debe tener entre 3 y 80 caracteres.'; END IF;
IF length(v_label) < 2 OR length(v_label) > 40 THEN RAISE EXCEPTION 'La etiqueta debe tener entre 2 y 40 caracteres.'; END IF;

IF p_generated_at IS NULL OR p_expires_at IS NULL THEN RAISE EXCEPTION 'Indicá la generación y el vencimiento.'; END IF;
IF p_image_data IS NULL
   OR p_image_data !~ '^data:image/(png|jpeg|webp);base64,[A-Za-z0-9+/=[:space:]]+$' THEN
  RAISE EXCEPTION 'La imagen del QR no es válida. Usá PNG, JPG o WebP.';
END IF;
IF length(p_image_data) > 2000000 THEN
  RAISE EXCEPTION 'La imagen del QR es demasiado grande. Usá un archivo de hasta 1 MB.';
END IF;

v_max_expiry := p_generated_at + INTERVAL '4 hours';
IF p_expires_at > v_max_expiry THEN RAISE EXCEPTION 'El vencimiento no puede superar las 4 horas desde la generación original.'; END IF;
IF p_expires_at <= now() THEN RAISE EXCEPTION 'El QR ya está vencido.'; END IF;
UPDATE qr_codes SET active = false, replaced_at = now() WHERE slot = p_slot AND active = true RETURNING id INTO v_old_id;
INSERT INTO qr_codes (slot, product, amount, holder, label, image_data, generated_at, expires_at, active, created_by)
VALUES (p_slot, p_product, p_amount, v_holder, v_label, p_image_data, p_generated_at, p_expires_at, true, auth.uid())
RETURNING id INTO v_new_id;
INSERT INTO audit_log (action, actor, target_qr, detail)
VALUES ('qr_upload', auth.uid(), v_new_id, jsonb_build_object('slot', p_slot, 'product', p_product, 'amount', p_amount, 'replaced', v_old_id));
RETURN jsonb_build_object('ok',true,'id',v_new_id,'message','QR guardado.');
END;
$function$;
