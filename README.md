# Un día más — fotos, fase 1 — 1.0.4+24

Copia independiente de la versión publicada 1.0.3+23 (commit da2d8882386e0ceeca8dbd3c3e6ce9f60b90fb0e). La carpeta v23 permanece intacta. Esta fase es para pruebas locales; no está publicada ni enviada a revisión.

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

El APK usa com.celsoriaapps.undiamas.privacidad, el certificado preview existente y anuncios de prueba. El nombre visible es Un Día Más / One More Day. Puede actualizar la prueba v22 y se instala por separado de la app de Google Play. No desinstales la aplicación publicada.

Las copias preview tienen nombres independientes y no sustituyen las de producción. La conexión real de Drive depende del registro OAuth de ese identificador/certificado; las pruebas del transporte no acreditan una conexión real con una cuenta.

## Verificación y compilación

Flutter 3.32.8, Java 17, API 36 y el pubspec.lock incluido.

```powershell
.\tool\local-photos.ps1 -Mode Pub
.\tool\local-photos.ps1 -Mode Analyze
.\tool\local-photos.ps1 -Mode Test
python -m unittest discover -s tool -p '*_test.py' -v
.\tool\local-photos.ps1 -Mode Build
.\tool\verify-preview.ps1
```

El helper utiliza el runtime local existente y compila sólo el identificador de pruebas. El verificador compara el certificado con el APK v22 y revisa API, permisos, anuncios de prueba y alineación de 16 KiB antes de entregar en dist/. Los registros quedan en build/validation/.

Consulta [el informe y las pruebas manuales](docs/PRUEBA-FOTOS-24.md).

## Datos y compatibilidad

DiaryEntry mantiene el tipo Hive 1 y los campos 0–2. El campo opcional 3 enlaza una fotografía por SHA-256. Fotos y borrador se cifran por separado con AES-GCM y claves derivadas de la clave local existente para cada propósito. El importador admite JPEG, PNG y WebP de hasta 16 MiB y 16 megapíxeles; las fotos se normalizan a JPEG de hasta 1600 px y 2 MiB, eliminando metadatos EXIF. No se envían a AdMob. Se retiran los temporales identificados del selector dentro de la caché privada, conservando siempre el original de la galería.

udm_backup_v2.zip contiene un manifiesto y exactamente las fotografías referenciadas. Se valida todo antes de cambiar Hive y se conservan los archivos anteriores para recuperar una restauración interrumpida. El lector admite udm_backup.json, sin sustituir un v2 inválido por un JSON antiguo. Drive usa HTTPS, sin cifrado propio de extremo a extremo. El borrador no se respalda.

Antes de una futura publicación: revisar las declaraciones de fotos/datos de Google Play, publicar la política revisada y probar cámara, selector y Drive con la firma correspondiente. La [política local](docs/privacy-policy.html) es un borrador; no modifica la página pública.
