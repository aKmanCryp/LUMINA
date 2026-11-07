/*
# Corrige el tipo de los ajustes del panel administrativo

1. Problema
- El presupuesto de IA (ai_budget_pyg) quedó guardado como texto ("0") en vez de número.
- El panel administrativo calcula el tablero con ese valor y fallaba al convertirlo, por lo que el tablero, la carga de QR y los métodos de pago mostraban un error genérico.

2. Cambios
- Normaliza el valor existente de ai_budget_pyg a número entero.
- admin_set_setting valida y convierte el valor antes de guardarlo:
  - sales_enabled debe ser verdadero o falso.
  - ai_budget_pyg debe ser un número entero en guaraníes.
- Sin cambios en permisos, políticas RLS ni en la lógica de pagos.

3. Notas
- Migración idempotente: en una base nueva no hay filas que normalizar.
*/

UPDATE app_settings
SET value = to_jsonb((value #>> '{}')::bigint), updated_at = now()
WHERE key = 'ai_budget_pyg' AND jsonb_typeof(value) = 'string' AND (value #>> '{}') ~ '^[0-9]+$';

CREATE OR REPLACE FUNCTION public.admin_set_setting(p_key text, p_value jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
IF NOT is_admin() THEN RAISE EXCEPTION 'Solo un administrador puede cambiar la configuración.'; END IF;
IF p_key NOT IN ('sales_enabled', 'ai_budget_pyg') THEN
RAISE EXCEPTION 'Configuración no permitida. cron_secret y project_url se configuran como secretos del backend, no desde el panel.';
END IF;

IF p_key = 'sales_enabled' THEN
IF jsonb_typeof(p_value) = 'string' AND (p_value #>> '{}') IN ('true', 'false') THEN
p_value := to_jsonb((p_value #>> '{}')::boolean);
ELSIF jsonb_typeof(p_value) <> 'boolean' THEN
RAISE EXCEPTION 'El estado de ventas debe ser verdadero o falso.';
END IF;
ELSE
IF (p_value #>> '{}') IS NULL OR (p_value #>> '{}') !~ '^[0-9]{1,12}$' THEN
RAISE EXCEPTION 'El presupuesto de IA debe ser un número entero en guaraníes.';
END IF;
p_value := to_jsonb((p_value #>> '{}')::bigint);
END IF;

INSERT INTO app_settings (key, value, updated_at)
VALUES (p_key, p_value, now())
ON CONFLICT (key) DO UPDATE SET value = excluded.value, updated_at = now();
RETURN jsonb_build_object('ok', true, 'key', p_key, 'value', p_value);
END;
$function$;
