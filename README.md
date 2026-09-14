# Un día más — conexión de Drive en pruebas — 1.0.6+26

Copia independiente de la prueba **1.0.5+25**, commit `e70f1ba83a4589aa95949868c28ac104f1cad117`, que parte de producción 1.0.3+23. Las carpetas anteriores permanecen intactas. Esta versión es para pruebas locales; no está publicada ni enviada a revisión.

Esta corrección retira la frase sobre Drive del selector de fotos y sustituye los errores técnicos de conexión por mensajes legibles. También impide enviar solicitudes a Drive cuando Google devuelve un token de acceso nulo o vacío. El mensaje para una copia inválida es «La copia está incompleta o no es compatible.».

Con permiso expreso del propietario, se ha añadido en Google Cloud el cliente OAuth Android correspondiente al paquete y certificado de la prueba. Los dos registros originales de producción se conservan. Google indica que el cambio puede tardar de minutos a horas en propagarse; aún no se ha comprobado una subida real desde un móvil. Identificación del cliente, alcance y prueba manual en [PRUEBA-DRIVE-26.md](docs/PRUEBA-DRIVE-26.md).

## Funciones que se conservan

- Una fotografía opcional por entrada, desde cámara o galería.
- Texto o fotografía junto al ánimo; miniatura visible y vista ampliable.
- Borrador cifrado al usar la cámara y cambiar de pestaña.
- Borrado de adjuntos sin borrar originales de la galería ni fotos usadas por otras entradas.
- Fotografías también en el detalle de la gráfica del Perfil.
- Copias v2 con fotos y lectura de los JSON antiguos.
- Explicación de financiación con anuncios en Perfil; banners y consentimiento sin cambios.

Se conservan la preparación de imágenes Android y las correcciones de importación de v25, además del diseño, reflexiones, herramientas, notificaciones y bloqueo opcional. Las sugerencias diarias y la edición de entradas no forman parte de esta corrección.

## Edición de prueba

El APK usa `com.celsoriaapps.undiamas.privacidad`, el certificado preview existente y anuncios de prueba. El nombre visible es Un Día Más / One More Day. Está preparado para actualizar la prueba v25 y se instala por separado de la app de Google Play. Instálalo encima de v25, sin desinstalarla ni borrar datos, y comprueba que siguen el Inventario y las fotos.

Las copias preview tienen nombres independientes y no sustituyen las de producción. No se han cambiado los scopes, nombres de archivos, firmas, CI ni anuncios de producción, ni se ha fijado un `clientId` o `serverClientId` en la app. El registro OAuth adicional habilita la identidad de pruebas; los tests del transporte no acreditan por sí solos una conexión real con una cuenta.

## Verificación y compilación

Flutter 3.32.8, Java 17, API 36 y el pubspec.lock incluido.

```powershell
.\tool\local-photos.ps1 -Mode Pub
.\tool\local-photos.ps1 -Mode Analyze
.\tool\local-photos.ps1 -Mode Test
python -m unittest discover -s tool -p '*_test.py' -v
.\tool\verify-native-photo-policy.ps1
.\tool\local-photos.ps1 -Mode Build
.\tool\verify-preview.ps1
```

El helper utiliza el runtime local existente y compila sólo el identificador de pruebas. El verificador compara el certificado con el APK v25 y revisa API, permisos, anuncios de prueba y alineación de 16 KiB antes de entregar en `dist/`. Los registros quedan en `build/validation/`.

Estado de esta revisión: suite completa con **440 pruebas correctas y 2 omitidas** por enlaces simbólicos no disponibles en Windows; **14 tests Python** correctos. También se verificaron **50 tests de Drive** con configuración normal y los mismos **50 con configuración preview**, además de **16 tests de interfaz**. Estos grupos no se suman al total de la suite. Análisis correcto, sin diagnósticos nuevos: persisten 3 advertencias y 31 informaciones anteriores. La compilación de v26 terminó correctamente en 16 min 3 s y el APK pasó el verificador de firma, contenido, permisos y compatibilidad. Resultado y SHA-256 en [el informe de v26](docs/PRUEBA-DRIVE-26.md). No hay dispositivo Android conectado ni una subida real a Drive verificada.

El [informe anterior de fotografías](docs/PRUEBA-FOTOS-25.md) conserva la evidencia específica de v25. Sus resultados no se presentan como una compilación o prueba física de v26.

La comprobación posterior solicitada sobre mensajes antiguos añade dos integraciones correctas en modo normal y preview: copia inicial de todas las entradas guardadas, actualización con una entrada nueva, descarga con recuperación exacta de fotos y protección de la copia anterior si falta una foto. En total son **442 casos distintos aprobados**, además de los dos omitidos. Estas pruebas adicionales no requirieron modificar el código de la aplicación.

## Datos y compatibilidad

DiaryEntry mantiene el tipo Hive 1 y los campos 0–2. El campo opcional 3 enlaza una fotografía por SHA-256. Fotos y borrador se cifran por separado con AES-GCM y claves derivadas de la clave local existente para cada propósito. Android prepara los formatos que pueda decodificar el sistema, con límites de origen de 128 MiB, 128 megapíxeles y 20.000 px por lado. Lee dimensiones antes de cargar los píxeles, muestrea hasta 3200 px y entrega únicamente un JPEG reducido a Dart. En otras plataformas sigue el importador JPEG/PNG/WebP de hasta 16 MiB y 16 megapíxeles.

Las copias guardadas siguen siendo JPEG de hasta 1600 px y 2 MiB, con orientación aplicada, fondo blanco para transparencias y sin metadatos EXIF/GPS. No se envían a AdMob. Se retiran los temporales identificados del selector dentro de la caché privada, conservando siempre el original de la galería. El preparador Android sólo lee archivos regulares de esa caché; no crea copias temporales adicionales ni solicita permisos nuevos.

`udm_backup_v2.zip` en producción y `udm_preview_backup_v2.zip` en la prueba contienen un manifiesto y exactamente las fotografías referenciadas. Se valida todo antes de cambiar Hive y se conservan los archivos anteriores para recuperar una restauración interrumpida. El lector admite los JSON antiguos del entorno correspondiente, sin sustituir un v2 inválido por un JSON antiguo. Drive usa HTTPS, sin cifrado propio de extremo a extremo. El borrador no se respalda.

Antes de una futura publicación: revisar las declaraciones de fotos/datos de Google Play, publicar la política revisada y probar cámara, selector y Drive con la firma correspondiente. La [política local](docs/privacy-policy.html) es un borrador; no modifica la página pública.
