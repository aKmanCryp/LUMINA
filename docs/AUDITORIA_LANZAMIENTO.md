# Auditoría de lanzamiento: estado y pendientes

Fecha de la pasada: 2026-11-07.

## Cambios aplicados

- Meta Pixel preparado en `src/lib/meta-pixel.ts`. Se activa solo si existe la variable `VITE_META_PIXEL_ID` (ID numérico del Pixel). Sin ese valor no se carga ningún script de Meta.
  - PageView: al cargar la aplicación.
  - ViewContent: al abrir la página de compra de un plan, con identificador, nombre y precio en guaraníes.
  - InitiateCheckout: al crear un pedido en el formulario, con importe.
  - Purchase: solo cuando el servidor marca el pedido como pagado y el modo es real (`manual_qr`). Se deduplica por pedido en el navegador con un identificador de evento estable (`purchase-<id del pedido>`).
- Pedidos de prueba (`manual_qr_test`) no disparan Purchase.

## Verificaciones realizadas

- `npm run build` (TypeScript + Vite): pasa. Un error de tipos en el módulo del Pixel se corrigió antes de la compilación final.
- Revisión de código del flujo de compra: formulario, validación de datos, pedido, QR vigente, aviso de pago, verificación administrativa y lectura. Sin cambios de lógica.

## Problemas detectados (pendientes)

1. Meta Pixel sin ID: falta el valor de `VITE_META_PIXEL_ID`. Hay que pedirlo al propietario de la cuenta de Meta.
2. Conversions API (Purchase desde el servidor, con deduplicación) no está implementada. Requiere un token de acceso de Meta, que no se inventó. Debe guardarse como secreto del backend.
3. Textos públicos de prueba: la franja superior muestra "MIGRACIÓN · VENTAS DESACTIVADAS" y el formulario indica "datos ficticios" en modo demo. Hay que reemplazarlos al habilitar ventas.
4. Preguntas frecuentes sin plazo de entrega concreto ("El horario de atención y el plazo comercial deben definirse"). Hay que definir el plazo real antes de publicidad.
5. Documentos legales marcados como "Borrador del piloto privado". Deben revisarse antes del uso comercial.
6. La página tiene `noindex,nofollow` y una imagen de vista previa del proveedor de la plataforma. Revisar antes de lanzar.
7. El registro interno de eventos (`events`) devuelve "backend no conectado" y no guarda nada.

## Pendiente de esta pasada

- Verificación de PDFs tras aprobación (sin duplicados): no se ejecutó una prueba end-to-end. Requiere un pedido de prueba con el cron activo.
- Revisión de textos comerciales de planes: no se modificaron. Faltan datos reales de entrega y de plazos.
- Auditoría responsive en 390 px y 803 px: no se ejecutó en navegador. El proyecto no tiene herramienta de capturas.

## Pruebas pendientes del checklist

Ver `docs/03_PRUEBAS_ANTES_DE_VENDER.md`. Ningún punto fue marcado como aprobado en esta pasada.
