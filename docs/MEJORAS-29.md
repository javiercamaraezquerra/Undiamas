# Candidata 1.0.9+29 — mejoras de uso

Autorización del 01/10/2026: evaluar e implementar valoración en Google Play,
invitación tras tres días de uso, última copia y búsqueda del Inventario.
No se ha solicitado publicar esta candidata. Base v28 preservada en su carpeta.

## Decisiones de implementación

- Perfil: acceso permanente «Valorar en Google Play» a la ficha de producción.
- Invitación: tres fechas locales distintas con uso de la aplicación, una sola
  invitación, en una transición entre pestañas que no interrumpa escritura,
  ayudas, bloqueos, permisos, consentimiento o restauración. El contador empieza
  con esta versión: no se infiere de la antigüedad de entradas personales.
- Texto: «Tus comentarios nos ayudan a seguir mejorando Un día más. Gracias
  por dedicarnos un momento». Valorar es voluntario; se puede cerrar sin valorar.
- Se abre Google Play con `url_launcher`, ya existente. No se añade SDK de
  valoraciones, filtro de satisfacción, incentivos ni solicitud de cinco estrellas.
  La app no puede saber si la persona terminó escribiendo una reseña.
- Copias: fecha local de la última subida confirmada por Drive. Un intento o
  descarga/restauración no cuentan como nueva copia. La ausencia de registro
  no significa que no existan copias anteriores a esta versión.
- Inventario: lupa junto al historial; búsqueda por texto sin distinguir tildes
  o mayúsculas, limpiar/cerrar y estado sin coincidencias. Solo filtra la vista;
  no modifica datos, fechas, fotos ni la gráfica.

## Conservación

Sin migración de datos, cambios del adaptador Hive, claves de cifrado,
formato de copias ni colección de reflexiones. Nombre, sol, montañas,
banners, notificaciones, bloqueo y SOS conservan su funcionamiento.
No se añade búsqueda de imágenes, envío de textos a servidores ni analítica.

## Comprobaciones

Resultados del 01/10/2026:

- Suite Flutter completa: **523 pruebas correctas, 2 omitidas, 0 fallos**.
  Las dos omitidas son pruebas existentes de enlaces simbólicos de la limpieza
  de fotos: esta cuenta de Windows no permite crear esos enlaces. No se omiten
  pruebas de las funciones nuevas. Registro: `build/validation/tests-final-v29.txt`.
- Valoración: 35 pruebas de servicio e interfaz; incluye pulsaciones sobre
  una barra de navegación real en tres fechas, lectores de pantalla, teclados,
  consentimiento, bloqueo, rutas superpuestas, fallos de enlace y no repetición.
- Drive: transporte HTTP simulado para subida completa, éxito/fallo/cancelación;
  estado persistente, cambio de cuenta, fechas, fotos y contenido tras restaurar.
  Un fallo del registro local o limpieza temporal posterior no convierte una
  subida ya confirmada por Drive en un fallo de copia.
- Inventario: búsqueda, guardado con filtro activo, borrado por clave original,
  restauración con confirmación obsoleta, borradores y adjuntos. La consulta es
  temporal y se busca únicamente dentro de los textos, no en las fotos.
- 14 pruebas Python de los verificadores: correctas.
- Inspección de capturas Flutter en claro, oscuro y 320 px con texto al 200 %.
  Se corrigió la lectura demasiado estrecha de las tarjetas en pantallas pequeñas
  o con texto ampliado; el diseño de las tarjetas a tamaño normal se conserva.
- Análisis sin errores ni avisos nuevos; se conserva la base histórica de
  advertencias y recomendaciones de estilo en archivos ajenos a estas funciones.
- Reflexiones idénticas a la colección aprobada de v28, SHA-256
  `450f6b756d2d80a6375f06f5477bf00104e00642eb892d98aaae2905703bdd2b`.

Durante las pruebas se corrigió un caso real: la retirada del cuadro de
valoración al bloquearse la app necesitaba solicitar un nuevo frame para no
esperar otro toque. También se corrigieron los fixtures que mezclaban el reloj
simulado de Flutter con colas creadas fuera de él. Las comprobaciones no se
relajaron para hacerlas pasar.

APK de prueba compilado y verificado el 01/10/2026 a las 21:43 (Madrid):
`dist/UnDiaMas-1.0.9-29-mejoras.apk`, 79.608.956 bytes. SHA-256:
`aebdd37c16dd573bc045646c38b300e9ccb5f012d0497dc92fddf351f551f313`.
Firma válida e idéntica a la prueba anterior, identidad aislada, nombre visible
Un Día Más, API 36, tres arquitecturas y publicidad de prueba confirmadas.
Permisos revisados, 90 archivos de entrada intactos durante la compilación,
reflexiones aprobadas idénticas dentro del APK y alineación ZIP/ELF de 16 KiB
verificada. Informe: `dist/verificacion-android.json`. Estas comprobaciones
estáticas no equivalen a haber ejecutado el APK en un dispositivo de 16 KiB.

Límites: no se ha probado en un móvil físico ni conectado con una cuenta real
de Drive en esta revisión. El emulador API 36 instalado no pudo arrancar porque
falta aceleración de hardware; no se ha modificado la configuración del PC para
habilitarla. Las pruebas de interfaz renderizan los widgets reales de Flutter,
pero no sustituyen comprobar la APK en el teléfono.

## Cómo revisar esta candidata

1. Instalar el APK sobre la app de pruebas existente. La firma y el paquete de
   esa app se verifican; no desinstalar la aplicación publicada para instalarlo.
2. Buscar un texto del Inventario (también sin tildes), limpiar/cerrar y comprobar
   que los mensajes y fotografías mantienen su contenido y su fecha.
3. En Perfil, comprobar la fecha tras una copia confirmada. Las versiones previas
   no registraban este dato: hasta la primera copia con v29 puede indicar
   «Sin fecha de copia registrada en este móvil», aunque exista una copia antigua.
4. «Valorar en Google Play» abre la ficha de la aplicación y no envía ninguna
   reseña por sí solo. El aviso automático cuenta tres días distintos desde
   esta versión y solo aparece una vez, en un cambio de pestaña adecuado.

La fecha se refiere a la última subida confirmada **desde este móvil**. No se
consulta ni autentica con Drive al abrir Perfil. Un restablecimiento completo
de datos elimina también estos registros locales; restaurar un inventario de
Drive no reinicia el historial de la invitación ni inventa una copia nueva.

## Archivos y reproducción

Implementación en `lib/services/{play_review_service,drive_backup_status_store,
journal_search_query}.dart`, sus widgets, `journal_screen.dart`,
`profile_screen.dart`, `bottom_nav_bar.dart`, `main.dart` y
`drive_backup_service.dart`. Pruebas nuevas en `test/` con esos mismos nombres;
notas de actualización en `release-notes-es-ES-29.txt`.

Toolchain conservado: Flutter 3.32.8, JDK 17, SDK 36, NDK 28.1.13356709.
`tool/local-v29.ps1 -Mode Test` ejecuta la suite; `-Mode Analyze` analiza y
`-Mode Build` compila la variante `preview` usando el certificado existente.
`tool/verify-preview-v29.ps1` verifica y copia el APK a `dist`.
El script es específico de este PC; no se ha cambiado el workflow de producción.

## Documentación de referencia consultada

- https://developer.android.com/guide/playcore/in-app-review
- https://support.google.com/googleplay/android-developer/answer/9898684?hl=es

Google recomienda abrir la ficha de Play para una acción explícita de valorar,
porque su cuadro nativo tiene cuotas y puede no mostrarse. El cuadro de esta
versión es una invitación propia y opcional, no una imitación de la tarjeta nativa.
