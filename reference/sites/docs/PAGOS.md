# Cobros reales: especificación pendiente de homologación

Investigación verificada al 21/10/2026. No se afilió el comercio, no se obtuvieron credenciales ni se probó un adquirente real. El simulador es propio de ASTROPY; **no es un sandbox oficial de Bancard o Pagopar**.

## Elección para piloto

Priorizar evaluación de uPay/Pagopar e-commerce por API y oferta publicada, confirmando contrato completo, admisión de informes recreativos IA y salida IP. Pagopar y uPay no deben compararse como negocios independientes: el sitio actual deriva e-commerce y suscripciones a Pagopar.

| Alternativa | Publicado | Falta confirmar |
|---|---|---|
| uPay Base | ₲0; links y QR. Sin RUC hay topes. | Si este plan habilita la API de automatización necesaria y sus topes. |
| uPay Pro | ₲45.000; bonificado seis meses según sitio consultado; con RUC. | Condiciones, alcance del API, cargo específico de e-commerce e IVA de comisión. |
| uPay/Pagopar e-commerce | 2% débito/QR local, 3% crédito, 2,9% QR Pix/Argentina; API y recurrencia publicitadas. | Tarifa fija aplicable, impuestos, afiliación y rubro. No asumir que Base incluye esta integración. |
| TPago | ₲22.900/mes IVA incluido, links, QR/tarjetas; landing anuncia API. | Comisión, callbacks, consulta server, recurrencia. Landing exige RUC y onboarding permite RUC o CI: resolver discrepancia. |
| vPOS | ₲74.900/mes IVA incluido; 3% crédito y 2% débito sin IVA. API, medios registrados y posibilidad de tarjetas extranjeras. | Aceptación de rubro, habilitación internacional, contracargos y recurrencia contractual. |

La sección e-commerce publica 3% crédito, mientras la tabla general del mismo sitio informa 2,9% para crédito local. Confirmar por contrato el canal y la tasa aplicable. Su tabla general publica acreditación a 24 horas hábiles en débito/QR local y 48 en crédito/prepaga/QR Pix/Argentina. La caja presupuestada usa tres días de ventas pendientes como hipótesis, sin modelar cada feriado.

## Condición técnica crítica

La documentación de Pagopar pide registrar la IP saliente de la tienda para producción. Workers no proporciona aquí una IP fija propia de ASTROPY. Solicitar una solución soportada por el proveedor o cotizar proxy con egreso fijo. No abrir un servicio extra sin aprobación. Si no existe opción económica, reevaluar TPago/vPOS o backend con IP fija, verificando su contrato técnico.

La documentación advierte que desarrollo/staging puede permitir pagos reales. No probar tarjetas ni transacciones reales por considerar «sandbox» el nombre de un entorno.

## Contrato interno a implementar

1. `createCheckout(order)`: servidor crea la orden externa con número único, PYG, monto inmutable y referencia interna; guarda `provider_order_id`.
2. Redirección al checkout alojado del adquirente. El navegador nunca entrega PAN/CVV a ASTROPY.
3. Recibir callback y autenticarlo conforme al contrato técnico vigente. El webhook real requiere una autorización diferente del control same-origin del navegador.
4. Consultar estado al proveedor desde servidor, aunque haya callback. En Pagopar la consulta figura como obligatoria.
5. Verificar comercio, pedido externo, referencia interna, estado efectivamente pagado, importe, moneda y ausencia de reversa. Si un campo no viene en callback, contrastarlo mediante la respuesta/orden autoritativa según contrato. Un retorno del checkout, screenshot, comprobante subido o `pagado` enviado por el navegador nunca acreditan dinero.
6. Aplicar evento único y transición atómica. Programar generación con un job único por pedido. Responder rápido al proveedor y procesar cola con reintentos/alertas.
7. Entregar informe y comprobante de entrega. Emitir factura tributaria por flujo validado. No usar el PDF recreativo como factura.
8. Consultar y conciliar pagos pendientes, reversas y contracargos. Mantener estados posteriores y costos incluso cuando corresponda devolver la venta.

Faltan tablas/campos específicos del proveedor, firma o validación contractual, endpoint verificador, cola de trabajos, conciliación programada, reembolso real y pruebas de homologación. No hay una firma ficticia presentada como integración lista.

## Criterios de aceptación antes de activar

- Afiliación con actividad declarada y tarifa total por escrito; RUC y facturación definidos.
- Credenciales por secreto, URLs de respuesta HTTPS y solución de IP aprobada.
- Pagos aprobados, pendientes, rechazados, vencidos, cancelados y duplicados; monto/moneda incorrectos bloqueados.
- Notificación falsa y reordenada; callback repetido concurrentemente; caída y reintento; reversa antes/después de entregar.
- Conciliación detecta callback perdido; un pedido solo genera una entrega facturable.
- Autorización expresa del propietario antes de cualquier pago real de homologación.

## Fuentes oficiales

- https://upay.com.py/
- https://www.pagopar.com/faq
- https://www.pagopar.com/politicas-actividades-prohibidas
- https://comercios.bancard.com.py/onboarding/opportunity_product/1
- https://comercios.bancard.com.py/onboarding/opportunity_product/7
- https://www.bancard.com.py/tpago
- https://www.bancard.com.py/vpos
- https://ayuda.ueno.com.py/article/cuales-son-los-tiempos-de-acreditacion-de-las-ventas-con-upay?account_type=individuals&article_type=FAQ
- https://soporte.pagopar.com/portal/es/kb/articles/entornos-pase-a-producci%C3%B3n
- https://soporte.pagopar.com/portal/es/kb/articles/version-ingles-api-integraci%C3%B3n-de-medios-de-pagos
- https://soporte.pagopar.com/portal/es/kb/articles/catastro-tarjetas-pagos-recurrentes-preautorizacion
