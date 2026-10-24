# Contrato de migración

## Destino y alcance

Interfaz portable Vite/React ya preparada. Servidor nuevo en funciones de Bolt y base de datos provista por el proyecto. Si se elige Supabase, usar su SDK/sesiones y RLS con validación del servidor; no es una conexión ya implementada. Confirmar primero qué proveedor ofrece la cuenta. No hay obligación de contratar ambos proveedores.

Mantener PYG entero, precios fijados en servidor y zona America/Asuncion. El producto principal comercial es pareja; no cambiar IDs persistidos lectura/compatibilidad/premium. No exponer el backend original de Sites ni sus autenticaciones de desarrollo como servicio de clientes.

## Archivos que guían la implementación

| Área | Fuente | Cambio requerido |
|---|---|---|
| UI | src/app y src/lib/domain.ts | Preservar diseño y validaciones; conectar sesiones y servidor |
| API original | reference/sites/lib/server.ts | Portar SQL/transacciones, autenticación y almacenamiento |
| Cuentas | reference/sites/app/chatgpt-auth.ts | Sustituir por proveedor de clientes de Bolt; no confiar en esas cabeceras |
| Base | reference/sites/db/schema.ts, drizzle/*.sql | Traducir al motor destino; diseñar permisos y relaciones |
| QR | reference/sites/lib/qr.ts | Mantener fechas, importes, referencias y reglas; nuevo storage privado |
| IA | reference/sites/lib/generator.ts | Secrets de servidor, revisión actual de modelo/costos y pruebas |
| PDF | reference/sites/lib/pdf.ts | Reutilizar generador portable con verificación del propietario |
| Acceso HTTP | src/lib/client.ts | Sustituir por SDK/funciones con sesión; ajustar también descargas |
| Legal | src/lib/legal.ts | Borradores pendientes de datos reales y revisión |

## Contrato HTTP actual

Los siguientes paths se interpretan relativos al backend. Mantener semántica aunque el SDK cambie el transporte. `src/lib/client.ts` por sí solo no implementa JWT ni RLS.

| Método | Ruta | Alcance |
|---|---|---|
| GET | health, daily, payments/config | Público, sin secretos ni información de clientes |
| GET | me | Sesión real; devuelve name, referralCode, admin, mode |
| POST | events | Evento validado, limitado; nunca fechas de nacimiento |
| POST | orders | Cliente autenticado; Idempotency-Key; precios del servidor |
| GET | orders | Solo pedidos del propietario, con paginación |
| GET | orders/:id | Solo propietario; formato Order de la UI |
| POST | orders/:id/qr | Propietario; QR por importe exacto y vigente |
| GET | orders/:id/qr-image | Propietario; archivo privado o URL temporal autorizada |
| GET/POST | orders/:id/payment-report | Propietario; aviso no confirma pago |
| POST | orders/:id/retry | Propietario de pedido pagado; límite y lease |
| GET | orders/:id/pdf | Propietario + pagado + entregado; no URL pública permanente |
| GET/POST | admin/qr | Solo administrador |
| GET | admin/qr/:slot/image | Solo administrador |
| POST | admin/qr/:slot/disable | Solo administrador |
| GET | admin/payment-reports | Solo administrador |
| POST | admin/manual-payment/:id | Solo administrador; aprobación o rechazo con trazabilidad |
| GET | admin/dashboard, admin/export | Solo administrador; CSV protegido contra fórmulas |
| POST | admin/expenses | Solo administrador; Idempotency-Key |

Formato Order: id, product, amount, discount, payload, paymentStatus, deliveryStatus, result, createdAt, error, attempts, mode. Usar errores JSON {error:mensaje} con código HTTP correspondiente. `report` respeta el tipo Report de domain.ts. Métodos de uploads, descarga de QR, imágenes y PDF pueden usar transporte distinto siempre que se conserve autorización.

## Persistencia y estados

Tablas de referencia: profiles, orders, payment_events, daily_cache, expenses, events, rate_limits, qr_codes, qr_intents y manual_payments. Agregar roles confiables, FKs, índices y políticas del motor destino. Propietarios no pueden modificar importes, estado de pago, rol ni resultado final desde el navegador.

Pago pendiente → aviso en revisión → confirmación administrativa → pagado. Estado de entrega separado: pending/generating/delivered/error. Repetir aprobación no duplica generación. La deduplicación de referencia debe aplicarse en base/transacción, no solo en JS. Bloquear nuevos pedidos en producción si no hay contenido real habilitado o QR válido por su importe.

La reversa del piloto solo simulaba un reembolso: no implementa devolución bancaria. Definir la conciliación de reintegros reales antes de vender; nunca mostrar una devolución bancaria como realizada por cambiar un estado local.

## Seguridad y experiencia

Roles y propiedad se validan en servidor, en cada lectura o escritura. No confiar en IDs, roles o precios enviados por el cliente. Rate limit de pedidos, consultas y generación. Validar MIME real/tamaño de imágenes. Auditar las consultas masivas, exportaciones y logs. Evitar PII y claves en logs. No migrar el usuario local-demo ni el acceso administrativo del piloto privado.

Cookies de sesión y/o JWT deben integrarse con las funciones; CORS debe permitir solo orígenes autorizados. Si la sesión es por cookie, conservar defensa CSRF. Si es por JWT, verificarlo en servidor. En descargas con JWT, usar fetch autenticado + Blob o URLs firmadas breves después de verificar acceso; no depender de un enlace <a> que no envíe Authorization.

Completar el proveedor de autenticación, correo de acceso/recuperación, dominio, soporte, plazo de verificación de pagos y políticas antes de invitar compradores. No presentar la etapa 1 como sistema terminado ni como ventas operativas.
