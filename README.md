# Un día más — fotos corregidas, fase 1 — 1.0.5+25

Copia independiente de la prueba 1.0.4+24 (commit 842012f1ebe34b12075f8e380e6623fc80ffd018), que parte de producción 1.0.3+23. Las carpetas anteriores permanecen intactas. Esta fase es para pruebas locales; no está publicada ni enviada a revisión.

Esta corrección prepara las imágenes con Android antes de importarlas, admite JPEG con datos adicionales de foto en movimiento, espera las operaciones temporales de almacenamiento al volver de la cámara y muestra avisos legibles con acciones para continuar. Conserva el adjunto anterior si falla el cambio y explica cuándo falta elegir el ánimo para guardar.

## Cambios

- Una fotografía opcional por entrada, desde cámara o galería.
- Texto o fotografía junto al ánimo; miniatura visible y vista ampliable.
- Borrador cifrado al usar la cámara y cambiar de pestaña.
- Borrado de adjuntos sin borrar originales de la galería ni fotos usadas por otras entradas.
- Fotografías también en el detalle de la gráfica del Perfil.
- Copias v2 con fotos y lectura de los JSON antiguos.
- Explicación de financiación con anuncios en Perfil; banners y consentimiento sin cambios.

Las ideas diarias se reservan para la siguiente fase. Se conservan diseño, reflexiones, herramientas, notificaciones y bloqueo opcional.

## Edición de prueba

El APK usa com.celsoriaapps.undiamas.privacidad, el certificado preview existente y anuncios de prueba. El nombre visible es Un Día Más / One More Day. Actualiza la prueba v24 conservando sus datos y se instala por separado de la app de Google Play. Instálalo sobre la prueba anterior, sin desinstalarla.

Las copias preview tienen nombres independientes y no sustituyen las de producción. La conexión real de Drive depende del registro OAuth de ese identificador/certificado; las pruebas del transporte no acreditan una conexión real con una cuenta.

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

El helper utiliza el runtime local existente y compila sólo el identificador de pruebas. El verificador compara el certificado con el APK v24 y revisa API, permisos, anuncios de prueba y alineación de 16 KiB antes de entregar en dist/. Los registros quedan en build/validation/.

Consulta [el informe y las pruebas manuales de esta corrección](docs/PRUEBA-FOTOS-25.md). Las pruebas JVM verifican límites, geometría y limpieza del JPEG; no sustituyen una prueba del decodificador y la cámara en Android.

## Datos y compatibilidad

DiaryEntry mantiene el tipo Hive 1 y los campos 0–2. El campo opcional 3 enlaza una fotografía por SHA-256. Fotos y borrador se cifran por separado con AES-GCM y claves derivadas de la clave local existente para cada propósito. Android prepara los formatos que pueda decodificar el sistema, con límites de origen de 128 MiB, 128 megapíxeles y 20.000 px por lado. Lee dimensiones antes de cargar los píxeles, muestrea hasta 3200 px y entrega únicamente un JPEG reducido a Dart. En otras plataformas sigue el importador JPEG/PNG/WebP de hasta 16 MiB y 16 megapíxeles.

Las copias guardadas siguen siendo JPEG de hasta 1600 px y 2 MiB, con orientación aplicada, fondo blanco para transparencias y sin metadatos EXIF/GPS. No se envían a AdMob. Se retiran los temporales identificados del selector dentro de la caché privada, conservando siempre el original de la galería. El preparador Android sólo lee archivos regulares de esa caché; no crea copias temporales adicionales ni solicita permisos nuevos.

udm_backup_v2.zip contiene un manifiesto y exactamente las fotografías referenciadas. Se valida todo antes de cambiar Hive y se conservan los archivos anteriores para recuperar una restauración interrumpida. El lector admite udm_backup.json, sin sustituir un v2 inválido por un JSON antiguo. Drive usa HTTPS, sin cifrado propio de extremo a extremo. El borrador no se respalda.

Antes de una futura publicación: revisar las declaraciones de fotos/datos de Google Play, publicar la política revisada y probar cámara, selector y Drive con la firma correspondiente. La [política local](docs/privacy-policy.html) es un borrador; no modifica la página pública.
