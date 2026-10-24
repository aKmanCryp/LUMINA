-- Server-side validation of the order payload. Mirrors validateOrder() in the client
-- so the age gate, the consent flags and the field shapes are enforced even when the
-- RPC is called directly, and stores a normalised payload instead of the raw blob.
CREATE OR REPLACE FUNCTION public.lumina_valid_name(p_name text)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $f$
  SELECT p_name IS NOT NULL
     AND length(btrim(p_name)) BETWEEN 2 AND 40
     AND btrim(p_name) ~ '^[[:alpha:][:space:].''’-]+$';
$f$;
REVOKE EXECUTE ON FUNCTION public.lumina_valid_name(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.lumina_valid_name(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.lumina_valid_birth(p_birth text)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SET search_path TO 'public' AS $f$
DECLARE v_d date; v_today date;
BEGIN
  IF p_birth IS NULL OR p_birth !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN RETURN false; END IF;
  BEGIN v_d := p_birth::date; EXCEPTION WHEN others THEN RETURN false; END;
  IF to_char(v_d, 'YYYY-MM-DD') <> p_birth THEN RETURN false; END IF;
  v_today := (now() AT TIME ZONE 'America/Asuncion')::date;
  IF v_d < DATE '1900-01-01' OR v_d > v_today THEN RETURN false; END IF;
  RETURN v_d <= (v_today - INTERVAL '18 years');
END;
$f$;
REVOKE EXECUTE ON FUNCTION public.lumina_valid_birth(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.lumina_valid_birth(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.create_order(p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
v_product text; v_amount int; v_user_id uuid := auth.uid(); v_row orders%ROWTYPE;
v_prices jsonb := '{"lectura":19000,"compatibilidad":29000,"premium":49000}'::jsonb;
v_name text; v_name2 text; v_birth text; v_birth2 text; v_theme text; v_referral text;
v_clean jsonb;
BEGIN
IF v_user_id IS NULL THEN RAISE EXCEPTION 'Necesitás iniciar sesión para crear un pedido.'; END IF;
IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN
  RAISE EXCEPTION 'Revisá el formulario.';
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
