# Pruebas antes de vender

Todavía no ejecutadas en Bolt. Registrar resultado, evidencia y fecha por punto; los checks no implican que ya pasaron.

- [ ] Instalación limpia, chequeo TypeScript y build del proyecto importado.
- [ ] Vista previa en escritorio, 390 px y 803 px; sin desborde horizontal.
- [ ] Alta/login/recuperación de dos cuentas de cliente y una cuenta administrativa real.
- [ ] Cliente B no puede consultar, editar ni descargar el pedido/PDF de A, aunque conozca su ID.
- [ ] Cliente no puede elevarse a administrador por formulario, metadatos o llamada directa.
- [ ] Alterar precio, producto, fecha imposible, mayoría de edad o consentimiento se rechaza en servidor.
- [ ] Se pueden cargar tres QR válidos; un vencido, uno sin el importe exacto o una imagen inválida no se ofrecen para pagar.
- [ ] Subir un QR no renueva sus cuatro horas originales. Se verifica que admite varios cobros durante su vigencia.
- [ ] Avisar un pago o subir una captura no entrega lectura ni PDF.
- [ ] Rechazo y corrección del aviso funcionan; no se exige pagar otra vez si ya informó una operación.
- [ ] Una referencia no acredita dos pedidos. Dos aprobaciones concurrentes generan una sola entrega.
- [ ] IA real entrega 4/5/6 secciones según producto; se revisa calidad con al menos diez ejemplos y combinaciones de signos/temas.
- [ ] La API no recibe fecha de nacimiento completa. La clave no aparece en JavaScript, red del navegador ni repositorio.
- [ ] Falla/timeout de IA conserva el pago y se recupera sin cobrar de nuevo; no quedan trabajos perdidos.
- [ ] Registrar tiempo y costo por generación con el modelo y tarifa efectivamente elegidos.
- [ ] Descargas PDF, imágenes QR y CSV funcionan con la sesión y no filtran datos a otra cuenta.
- [ ] El índice sigue el scroll, las pestañas se alcanzan en móvil y las notas premium persisten en el mismo navegador.
- [ ] Apertura de tres segundos omisible, no repetida innecesariamente y con reducción de movimiento.
- [ ] Rutas de simulación y accesos de desarrollo no existen en producción.
- [ ] Identidad, facturación, soporte, plazos, privacidad y reembolsos están completados con datos reales.
- [ ] Se definieron retención/borrado, backups y una recuperación probada.
- [ ] Una compra real controlada desde otro celular confirma ingreso bancario → aprobación → lectura → PDF → recuperación posterior.
- [ ] Se concilian pedido, monto acreditado, costo de IA y cualquier reintegro.
- [ ] El propietario autoriza la apertura comercial después de revisar estos resultados.

Comenzar publicidad después de la compra controlada. Medir visita → inicio de pedido → pago confirmado → entrega. No enviar nombres ni fechas de nacimiento a plataformas publicitarias.
