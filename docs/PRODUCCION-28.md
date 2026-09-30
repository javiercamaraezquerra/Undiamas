# Un día más — entrega de producción 1.0.8 (28)

Envío confirmado el **1 de octubre de 2026, 00:01 (Europe/Madrid)**.

## Estado en Google Play

Play Console muestra **Cambios en revisión**, producción **1.0.8 (28)**,
**Iniciar lanzamiento completo**. Se ha confirmado el envío de un único cambio,
con despliegue al 100 % en todos los países de destino existentes.

La publicación gestionada está desactivada. Google publicará la actualización
cuando supere sus comprobaciones y la revisión. Al registrar esta entrega,
las comprobaciones rápidas seguían en curso; el envío no significa que ya esté
aprobada ni disponible públicamente. La versión 1.0.7 (27) estaba disponible
antes del envío y no se retiró manualmente.

## Procedencia

- Aplicación: `com.celsoriaapps.undiamas`, versión `1.0.8+28`.
- Base: `ae3358c62d4d521328dc5f14f0be68bfd330cc6f`, versión 1.0.7+27.
- Commit compilado: `d1d46cd9bcea1d5b2829f2d26a63d5fff9566da2`.
- [GitHub Actions 36781392931](https://github.com/javiercamaraezquerra/Undiamas/actions/runs/36781392931), intento 1: **SUCCESS**.
- El commit posterior de documentación registra este envío sin cambiar el binario.

## Cambio aprobado

Se integran las reflexiones revisadas para facilitar el hilo de lectura y la
comprensión. La colección mantiene 365 posiciones: 183 textos revisados y
182 conservados literalmente; 91.048 palabras y 232–277 palabras por entrada
contando cuerpo y pregunta. Fechas y títulos idénticos a la versión anterior.
Las reflexiones del 26 de abril y 2 de noviembre se conservan completas.

El código de aplicación, almacenamiento, Inventario, fotos, cifrado, Drive,
publicidad, notificaciones, permisos, nombre y diseño no cambian. No requiere
migraciones ni reinstalación. La actualización debe llegar mediante Google
Play para mantener la firma de distribución de la instalación existente.

## Comprobaciones terminadas

- 29 pruebas locales específicas de reflexiones, calendario y notificaciones.
- CI: 458 pruebas Flutter, 14 pruebas Python y 8 pruebas de política nativa Kotlin.
- Análisis: 0 errores, 3 advertencias y 31 avisos informativos heredados.
- Lectura del contenido real a 320×640, texto normal y al 200 %, claro y oscuro;
  se comprueban todos los párrafos de las dos fechas especiales, la entrada más
  larga de la colección y la reflexión revisada del 30 de septiembre.
- Verificación independiente de APK/AAB: **PASS**. Firma de subida original,
  identidad, API mínima 24 y destino 36, tres arquitecturas, publicidad de
  producción, permisos, alineación ZIP/ELF de 16 KiB y PAGE_ALIGNMENT_16K.
- Las 365 cadenas empaquetadas coinciden exactamente con la colección aprobada.
  APK, AAB y commit incluyen los mismos bytes del JSON. Todos los demás recursos
  Flutter son idénticos a la versión 27.
- Play confirma **0 dispositivos que pierden compatibilidad**; 19.186 dispositivos
  compatibles según el catálogo al enviar. Mapa ReTrace y símbolos nativos adjuntos.

La verificación binaria es estática; no se ha realizado una prueba nueva en un
móvil físico ni en un dispositivo de páginas de memoria de 16 KiB. El código de
la aplicación y del almacenamiento se conserva respecto a la base publicada.

## Artefactos

| Archivo | Bytes | SHA-256 |
| --- | ---: | --- |
| UnDiaMas-1.0.8-28-produccion.aab | 65.726.249 | a11a1ce3435f9825a663441d7c95d056bafe9f185bf14272a847498225b45a04 |
| UnDiaMas-1.0.8-28-produccion.apk | 79.493.556 | 92ffc6b4647de6f9edaf729a822507cb36b9d05fb4325e60ced4693eef22c8e3 |

SHA-256 de la colección aprobada y empaquetada:
`450f6b756d2d80a6375f06f5477bf00104e00642eb892d98aaae2905703bdd2b`.

La carpeta de entrega conserva los binarios, notas, mapa R8, registro CI,
`sha256.json`, `reflections-packaged-v28.json`, informes de verificación y
`play-console-en-revision.png`. La firma de subida es distinta de la firma
con la que Google Play distribuye la aplicación instalada.

## Notas enviadas para esta versión

Reflexiones diarias revisadas para una lectura más clara y cercana, con ejemplos mejor conectados y preguntas más fáciles de comprender y comentar. Conservan su enfoque inspirado en principios de la terapia cognitivo-conductual aplicados a la recuperación de adicciones.
