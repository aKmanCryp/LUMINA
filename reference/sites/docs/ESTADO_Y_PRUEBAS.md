# Estado y pruebas

21/10/2026. Solo datos ficticios. No hubo compras, altas pagas ni gasto publicitario.

## Desarrollado y comprobado en vista previa local

- Interfaz responsive revisada en escritorio y en iframe de 390 px, con la misma aplicación y media queries reales.
- Doce signos con diseño, fecha de Asunción, cuatro áreas y caché diario en D1.
- Lectura y compatibilidad con formularios y precio inmutable. Prototipo premium con seis módulos y notas locales.
- Pedidos durables, estados de pago/entrega, simulación de aprobación, rechazo, cancelación y reembolso.
- Historial privado, entrega sin recargo al reintentar, descarga PDF privada y tarjeta PNG.
- Panel con ingresos/costos separados, publicidad manual, estimación de comisión/IVA, productos, recurrentes y referidos.
- CSV de pedidos y gastos, sin datos de nacimiento y con prevención de fórmulas en campos de texto.
- Código de referido: 10% B/C en el primer pedido de otra cuenta, tope ₲3.000, 5 usos/código/mes y reserva concurrente. Sin recompensas monetarias.
- Cuatro borradores de políticas, señalización de simulador y aviso recreativo.

## Evidencia de pruebas

La página temporal de QA ejecutó **42 verificaciones de integración** contra las rutas reales de la vista previa y D1 local. Se retiró del directorio público; se conserva su fuente en `tests/browser-harness.html` para reproducción controlada. El script Python de integración queda como alternativa para una instalación donde su servidor local sea accesible por HTTP.

Se comprobaron caché de 12 signos, precio, idempotencia, conflicto de clave, bloqueo de PDF sin pago, rechazo, aislamiento de pedidos/PDF entre usuarios sintéticos, edad y fecha inválidas, consentimiento, nombre HTML, aprobaciones concurrentes, resultado inmutable, PDF válido, cinco/seis módulos, error forzado y reintento, cancelación terminal, fecha inválida de gasto, webhook real cerrado, reversa y bloqueo de descarga posterior, registro idempotente de gastos, CSV seguro, gasto negativo, conciliación aritmética del panel, historiales separados, autorreferido y segunda reserva de descuento.

Además pasaron **12 comprobaciones de dominio**: cumpleaños de 18 años, fecha imposible, límites convencionales de signos, cambio de día UTC/Asunción, número de signos, caché determinista, producto inválido y escape CSV. `tests/domain.mjs` no requiere API paga.

Se revisaron visualmente las dos páginas del PDF premium de ejemplo, con extracción de texto y `pdfinfo`. El PDF es A4, sin JavaScript ni formulario. Se revisó el flujo UI de formulario, rechazo, aprobación y resultado en navegador. TypeScript y compilación se verifican antes de empaquetar.

## Límites de verificación

La integración se probó con identidades sintéticas del entorno local. No se probaron credenciales, notificaciones ni pagos de un adquirente. No se hicieron llamadas a OpenAI: el adaptador preparado requiere prueba real, evaluación editorial y control presupuestario. No se verificó entrega a clientes públicos ni autenticación comercial ajena a Sites. La publicación privada se verifica mediante el resultado del servicio de despliegue, sin afirmar pruebas de pago reales en ese entorno.

No hubo prueba de carga, pentest, auditoría profesional, restauración de backups ni accesibilidad automatizada completa. La revisión móvil es de layout en 390 px, no una matriz de dispositivos físicos. Compartir archivos depende de Web Share del dispositivo; cuando no existe se descarga PNG para enviarlo manualmente. No se publicó contenido en WhatsApp o Instagram.

## Pendientes antes de ventas

| Componente | Estado |
|---|---|
| IA de lecturas | Adaptador escrito; sin clave, consumo ni prueba externa |
| Horóscopo diario por API IA | Caché editorial funciona; generador IA y job diario pendientes |
| Pagos reales | Sin afiliación, credenciales, verificador ni homologación |
| Factura DNIT | Sin emisor habilitado ni integración; PDF no fiscal |
| Público y roles | Piloto privado; falta diseño de acceso de clientes y roles explícitos |
| Cola y reintentos automáticos | Bloqueo e intento manual implementados; cola/alertas pendientes |
| Referidos comerciales | Código demo funciona; identidad/antiabuso de público y recompensas pendientes |
| Suscripciones | No implementadas; requieren evidencia de recompra y contrato de cobro |
| Carta natal | No implementada ni ofrecida; requiere motor astronómico validado |
| Retención y privacidad | Borradores y minimización implementados; canal de derechos/purga/backups pendientes |
| Marketing | Plan y textos listos; sin campañas, píxeles ni mensajería |

Las métricas del panel son de prueba. Su comisión es una hipótesis del 3,3%; el resultado aparta IVA supuesto sin créditos fiscales y no incluye impuestos a la renta ni tiempo propio. El CAC del panel mezcla clientes/canales y requiere atribución real antes de decidir inversión. Los listados del panel usan hasta 1.000 registros y CSV hasta 10.000; paginar antes de escalar.


## Actualización 22/10/2026 — LÚMINA y cobro QR manual

Marca visual provisional LÚMINA (la identidad y URL del proyecto se conservan). Portada enfocada en la lectura de ₲19.000, muestra interactiva, tipografías locales, azul petróleo/lima, animaciones con reducción de movimiento y CTA fijo móvil.

- R2 `BUCKET` para imágenes y tres espacios persistentes en D1. Importe fijo, titular real, etiqueta, fecha original y vencimiento de hasta cuatro horas. No se renueva la vigencia al subir el archivo.
- Imágenes raster PNG/JPEG/WebP de hasta 1 MB; SVG y solicitudes extensas bloqueadas. Acceso de administración protegido; imagen de checkout exige propiedad del pedido y QR vigente.
- Solo se muestran códigos habilitados y vigentes por el importe exacto. Se retiran al vencer o deshabilitar. El pedido conserva una instantánea de la cuenta mostrada.
- Aviso con remitente y referencia, revisión administrativa, rechazo con motivo y corrección. Un aviso mantiene el pago pendiente y no habilita PDF.
- Confirmación con importe y referencia vistos en Mango; referencia normalizada única por titular, operación atómica e idempotente, y bloqueo de autoaprobación del simulador en pedidos QR.
- Costo de comisión QR registrado en cero por configuración del piloto, según lo informado por el propietario; no es verificación contractual de Mango.
- **PAYMENTS_MODE=demo** conservado: los pedidos QR se marcan `manual_qr_test`, sin compras ni movimientos reales. No se cargaron QR bancarios reales. El entorno local usa imágenes «TEST ONLY» y titulares ficticios.
- El código incluye `manual_qr` para una futura activación con contenido real configurado y roles de administración explícitos. El respaldo `DEMO_ADMIN_ACCESS=owner-private` solo admite el entorno demo privado y debe retirarse antes de ampliar audiencia.
- La carga exige confirmar autorización del titular, importe y que el QR es reutilizable durante su vigencia. Esto no verifica condiciones de Mango. Los códigos de un solo uso no se deben publicar de forma compartida.

Pruebas específicas nuevas: 20 validaciones de QR/fechas/referencias y 39 verificaciones de integración contra las rutas reales, D1 y R2 locales. Se comprueban acceso, carga, retiro, vencimiento, importe, duplicados y concurrencia. No hubo llamadas pagas ni validación de códigos de Mango. La web no genera QR dentro de la billetera; su renovación y conciliación siguen siendo manuales.

Regresión ejecutada en esta actualización: las 42 comprobaciones de integración previas y las 12 de dominio también pasaron. Se probó además la carga mediante el selector de archivos del panel con una imagen ficticia y se revisó su representación en checkout.

La revisión del flujo UI confirmó la secuencia completa con datos ficticios: cargar imagen en el panel → crear pedido → ver QR/titular/importe → informar referencia → estado de espera → confirmar desde administración y entregar.


## Ajustes de experiencia — 22/10/2026

- Emblemas de signos animados en el resumen de compra, con órbitas, destellos y movimiento suave por producto.
- Botón «Revisar mi pedido» con brillo periódico, halo y movimiento leve de flecha, sin desplazamiento de layout; estado ocupado desactiva el efecto y muestra indicador.
- Ambas fechas de nacimiento se escriben con máscara DD/MM/AAAA, calendario validado y control de edad. La API sigue recibiendo ISO AAAA-MM-DD; no cambia el esquema ni el formato guardado.
- La espera del aviso QR muestra cartas y signos en movimiento con texto explícito de verificación pendiente. La apertura de la lectura ocurre solo al existir pago confirmado e informe entregado, dura aproximadamente tres segundos y puede omitirse. La sesión recuerda las lecturas abiertas para evitar repetir la espera.
- Los módulos aparecen una vez al entrar en la pantalla, con IntersectionObserver. Sin JavaScript o sin soporte, el texto permanece visible. El foco de teclado también revela la sección.
- Se respeta prefers-reduced-motion: movimientos desactivados y apertura directa del informe.

Verificación de esta actualización: TypeScript, doce casos de fechas (incluidos meses/días ambiguos, año bisiesto, fechas imposibles y pegado ISO), formulario de compatibilidad con ambos nacimientos, duración observada de apertura de 3.057 y 3.040 segundos, reapertura sin espera y aparición de módulos al desplazarse. Revisión local en escritorio y viewport de 390 px (375 px útiles por barra), sin desbordamiento horizontal. Se usaron nombres, referencias e imágenes ficticias; no se realizó ningún pago ni llamada de IA. No se amplió audiencia ni se modificó la conciliación de cobros.

El flujo QR completo volvió a comprobarse con aviso pendiente, confirmación administrativa ficticia y apertura observada de 3.032 segundos. La revisión móvil de la espera confirmó 375 px de contenido en 375 px de viewport útil.
