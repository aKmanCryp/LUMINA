# LÚMINA · Paquete para comenzar la migración a Bolt

Preparado el 24/10/2026 a partir de la versión 5 publicada. Conserva la identidad azul petróleo/lima, las fuentes propias, la oferta de pareja de ₲29.000, los formularios DD/MM/AAAA, las animaciones, el panel de QR y el nuevo diseño marfil de las lecturas.

## Estado real

La interfaz está adaptada a Vite + React + TypeScript y compila. El servidor todavía debe migrarse. Este paquete NO activa ventas, no genera informes reales, no carga tus QR y no inicia sesión con cuentas reales. La portada y el horóscopo editorial de demostración funcionan sin credenciales; las operaciones privadas muestran que la conexión está pendiente. No hay usuarios, pedidos ni pagos ficticios presentados como reales.

## Qué hacer ahora

1. Descomprimí `LUMINA_Bolt_Importacion.zip`.
2. Creá un repositorio **privado** en tu cuenta de GitHub, por ejemplo `lumina-bolt`.
3. Subí el CONTENIDO de la carpeta `lumina-bolt`. `package.json` debe quedar en la raíz del repositorio, junto a `src`, `public`, `docs` y `reference`. No subas `node_modules`, `dist` ni claves.
4. En la pantalla inicial de Bolt, elegí **GitHub** debajo del cuadro de texto, conectá tu cuenta y seleccioná el repositorio. También podés usar **Import from URL** con su URL. Confirmá **Choose this repository**. Si Bolt solicita acceso a GitHub, limitá la autorización al repositorio elegido.
5. Una vez cargado el proyecto, enviá: **«Leé README.md y docs/01_PROMPT_INICIO.txt. Ejecutá únicamente esa primera etapa y conservá el diseño.»**
6. Cuando la vista previa funcione, seguí `docs/02_PROMPT_BACKEND.txt`. Ahí se conectan cuentas, base de datos, QR e IA.
7. Agregá la clave de OpenAI únicamente en **Database → Secrets**, con nombre `OPENAI_API_KEY`, cuando la función del servidor la solicite. No la pegues en prompts, GitHub ni variables `VITE_*`.
8. Completá `docs/03_PRUEBAS_ANTES_DE_VENDER.md` antes de abrir ventas o anuncios.

El ZIP es el paquete de entrega. La ruta de importación documentada por Bolt es GitHub; no se presupone que adjuntar un ZIP al chat importe automáticamente un proyecto completo.

## Desarrollo local

Node >=22.13.0 compatible con Vite 8 (usar preferentemente Node 24 LTS), `npm install`, `npm run dev`. Comprobaciones: `npm run check` y `npm run build`. Es una SPA: el hosting final debe devolver `index.html` en las rutas `/experiencia`, `/mis-lecturas`, `/resultado/:id`, `/admin` y `/legal/:id`.

La compilación y el chequeo TypeScript se ejecutaron con las dependencias ya instaladas del proyecto fuente. No se verificó una instalación nueva desde npm ni se importó aún en una cuenta de Bolt.

## Contenido

- `src/app`: interfaz conservada, componentes, estilos, animaciones y lectura.
- `src/lib`: catálogo, signos, validación de fechas, políticas y adaptador de conexión.
- `public/fonts`: fuentes originales y licencia.
- `reference/sites`: código del servidor original, generador, PDF, reglas de cobros, esquemas SQLite y pruebas. Es referencia de migración, NO un backend listo para ejecutar en Bolt.
- `docs/CONTRATO_MIGRACION.md`: decisiones, rutas y verificaciones necesarias.
- `docs/ORIGEN.json`: versión y commit fuente.
- `docs/SOURCE_FILES_SHA256.json`: huellas de archivos del paquete.

## Datos y secretos

El paquete contiene código y assets. Excluye base de datos, informes de clientes, imágenes bancarias, sesiones, credenciales, archivos de entorno reales, historial Git y configuración privada del hosting. No hay que exportar datos del piloto para crear la base nueva.

## Fuentes oficiales consultadas

- Importación desde GitHub: https://support.bolt.new/integrations/git
- Tecnologías: https://support.bolt.new/reference/supported-technologies
- Funciones del servidor: https://support.bolt.new/bolt-cloud/database/server-functions
- Secrets: https://support.bolt.new/bolt-cloud/database/secrets

Consultadas el 24/10/2026. Los nombres de los menús pueden variar.
