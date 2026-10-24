# QR Mango — operación del piloto LÚMINA

## Cargar códigos

Abrir `/admin`, sección «Tus QR, bajo control». Elegir uno de los tres espacios, el importe exacto, titular real, etiqueta, fecha/hora original y vencimiento que muestra Mango. Subir la imagen original completa, raster de hasta 1 MB. Confirmar autorización, importe y que el QR admite varios cobros durante su vigencia. No usar códigos de un único pago en un checkout compartido. Un espacio por precio permite cubrir ₲19.000, ₲29.000 y ₲49.000. El retiro o reemplazo invalida la imagen anterior en el checkout. Los QR vencidos nunca se presentan para nuevos pagos.

## Conciliar

El cliente informa nombre del remitente y referencia. El pedido queda pendiente. Revisar el movimiento acreditado en la cuenta receptora, importe y referencia real; ingresar ambos desde el panel. La confirmación habilita la preparación del informe, con reintento de entrega si falla. Si no se encuentra el movimiento, devolver el aviso con una explicación para que el cliente lo corrija. No aprobar por captura. Una referencia normalizada no puede pagar dos pedidos del mismo titular.

Si se cobró en una cuenta de otra persona, el titular real debe figurar en la web y existir autorización y acuerdo de conciliación. Verificar con Mango las condiciones de esa cuenta antes del uso comercial. La aplicación no valida dichas condiciones ni el cobro: lo hace el operador mirando el movimiento.

## Entorno y activación

Publicación actual privada, `PAYMENTS_MODE=demo`, `CONTENT_MODE=demo`. El flujo QR puede probarse y sus pedidos se guardan como `manual_qr_test`. No hay códigos reales precargados ni cobros activados.

Para ventas reales: resolver acceso público y roles; completar identidad comercial, atención y políticas; configurar y probar contenido; registrar secreto de IA por el flujo oficial; fijar `ADMIN_USER_IDS` con la identidad del administrador; retirar `DEMO_ADMIN_ACCESS`; y configurar `PAYMENTS_MODE=manual_qr`, `CONTENT_MODE=openai`. Se debe desplegar después de cambiar el entorno. No alterar audiencia hasta verificar todo. `manual_qr` bloquea nuevos pedidos si falta contenido configurado o QR por el importe exacto. Los descuentos por referido se pausan en este modo porque requieren un QR para el importe descontado.

La confirmación manual registra comisión cero como hipótesis indicada por el propietario. Registrar cargos reales si existen y conciliar el panel con el extracto. Las reversas de prueba no devuelven dinero. Un reintegro real requiere la operación correspondiente por el titular y conciliación posterior.

## Limitaciones

No se conecta a Mango, no lee saldos, no renueva QR ni verifica su legibilidad o contenido bancario. Las fechas y el importe dependen del ingreso correcto por administración. El checkout bloquea expirados en servidor y muestra contador informativo del vencimiento del código, sin usarlo como urgencia de venta. No hay garantía de venta ni validación de marca LÚMINA.
