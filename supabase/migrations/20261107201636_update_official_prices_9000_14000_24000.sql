/*
# Actualiza los precios oficiales de los tres productos

1. Qué cambia
- Lectura personal (lectura): de 19.000 a 9.000 Gs.
- Entre dos estrellas (compatibilidad): de 29.000 a 14.000 Gs.
- Tu universo personal (premium): de 49.000 a 24.000 Gs.

2. Funciones modificadas (solo el mapa de precios)
- create_order: el importe de cada pedido nuevo se toma del mapa del servidor.
- admin_upload_qr: el importe de cada QR cargado se toma del mismo mapa.
- Resto de la lógica sin cambios: validaciones, cupo de ventas, referidos, seguridad y permisos.

3. Datos históricos
- No se modifica ningún pedido existente. Sus importes quedan tal como se cobraron.
- No se modifica ningún QR existente. Los QR cargados con el importe anterior dejan de coincidir con el nuevo precio y deben reemplazarse desde el panel administrativo.

4. Seguridad
- Las funciones mantienen SECURITY DEFINER, search_path fijo y los mismos permisos de ejecución.
- El importe sigue fijado por el servidor; el cliente no puede enviarlo.

5. Notas
- Migración idempotente: CREATE OR REPLACE sobre las mismas firmas.
*/

CREATE OR REPLACE FUNCTION public.admin_upload_qr(p_slot integer, p_product text, p_amount integer, p_holder text, p_label text, p_image_data text, p_generated_at timestamp with time zone, p_expires_at timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_old_id uuid; v_new_id uuid; v_max_expiry timestamptz;
v_holder text; v_label text; v_prices jsonb := '{"lectura":9000,"compatibilidad":14000,"premium":24000}'::jsonb;
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

CREATE OR REPLACE FUNCTION public.create_order(p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
v_product text; v_amount int; v_user_id uuid := auth.uid(); v_row orders%ROWTYPE;
v_prices jsonb := '{"lectura":9000,"compatibilidad":14000,"premium":24000}'::jsonb;
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
