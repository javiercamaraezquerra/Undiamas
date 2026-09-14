# Prueba de fotografías — fase 1

Base: producción 1.0.3+23. Candidata local: 1.0.4+24. Sin subir a GitHub ni Google Play.

## Para probar en el móvil

1. Instala el APK de prueba y ábrelo desde el instalador para distinguirlo de la app publicada.
2. En Inventario, escribe una frase, elige ánimo y añade una foto de la galería.
3. Cambia o quita el adjunto; cancelar el selector debe conservar el mensaje.
4. Guarda y toca la foto para verla completa y ampliarla.
5. Guarda otra entrada con foto y ánimo, sin texto.
6. Haz una foto con la cámara. Con el bloqueo activo, comprueba la vuelta a la app.
7. Cambia de pestaña con un borrador y vuelve: texto, ánimo y foto deben conservarse.
8. Abre esa entrada desde la gráfica del Perfil y comprueba el adjunto.
9. Borra una entrada de prueba. Las demás y el original de la galería deben conservarse.
10. Comprueba Perfil: explicación de anuncios, nombre original y banners habituales.

Las copias preview tienen nombres propios y no reemplazan producción. Si Drive muestra un error de autenticación, conserva el mensaje: requiere revisar OAuth de la edición de prueba; no demuestra un fallo del formato de respaldo. No desinstales la app publicada.

## Verificaciones

- APK final: `dist/UnDiaMas-1.0.4-24-fotos-fase1.apk` (81.064.196 bytes). Compilación `assemblePreviewRelease` correcta y verificador APK correcto, 14/09/2026.
- Verificados en el APK: nombre original, API 36, Android mínimo 7.0/API 24, tres arquitecturas, firma igual a la prueba v22, alineación de 16 KiB y banners de prueba. Sin permisos de acceso general a galería/almacenamiento ni permisos nuevos de alarmas exactas. Metadatos: `dist/verificacion-android.json`.
- SHA-256 del APK: `BCF8983790079360F6F0677243744C2E4AEB028F8564FCE6AFABF3D6E59CFEDC`. Los 76 archivos de entrada de compilación mantuvieron sus hashes entre el inicio de compilación y la comprobación final.
- Suite Flutter completa: **369 pruebas pasadas y 2 omitidas**. Las omitidas requieren crear enlaces simbólicos, algo que esta cuenta de Windows no permite. Registro: `build/validation/tests-full-final-v24.txt`.
- Herramientas de comprobación de versiones: **14 pruebas Python pasadas**. Registro: `build/validation/tests-python-v24.txt`.
- Análisis estático: **sin errores ni advertencias nuevas**. Quedan 3 advertencias y 31 avisos informativos del código anterior; registro: `build/validation/analyze-v24.txt`.
- Probados: lectura de cajas antiguas sin fotos, persistencia cifrada, borrador, cancelación y recuperación del selector, borrado de fotos compartidas, fallos de escritura, restauración con otra clave local y rechazo de copias incompletas o dañadas.
- Revisadas capturas con el fondo y tema originales; prueba de pantalla de 320 px, texto al 200 % y teclado sin desbordamiento. Las capturas usan una imagen de prueba generada, sin fotos personales.
- No se han probado una cámara física, la autenticación biométrica nativa ni una cuenta real de Drive. Las pruebas automatizadas simulan esos servicios y comprueban la lógica y los datos.

Comandos finales:

```powershell
.\tool\local-photos.ps1 -Mode Test -TestLog tests-full-final-v24.txt
.\tool\local-photos.ps1 -Mode Analyze
python -m unittest discover -s tool -p '*_test.py' -v
.\tool\local-photos.ps1 -Mode Build
.\tool\verify-preview.ps1
```

## Archivos principales

- `lib/screens/journal_screen.dart`, `lib/services/journal_composer_controller.dart` y `lib/widgets/inventory_photo_attachment.dart`: editor, selección y visualización.
- `lib/models/diary_entry.dart` y su adaptador: campo opcional de fotografía compatible con los registros anteriores.
- `lib/services/inventory_photo_store.dart`, `inventory_encrypted_file.dart`, `journal_draft_store.dart` y `picker_photo_cache_cleaner.dart`: cifrado, borrador y limpieza de temporales propios.
- `lib/services/inventory_backup_archive.dart`, `drive_backup_service.dart` y `hive_restore_service.dart`: copias con fotos y restauración segura.
- `lib/widgets/profile_privacy_links.dart`: explicación de anuncios. `mood_entry_detail_sheet.dart`: foto en el detalle de la gráfica.
- `lib/main.dart`, `lib/screens/profile_screen.dart` y los servicios de almacenamiento: integración con apertura, recuperación y borrado completo.
- `pubspec.yaml`, `pubspec.lock`, manifiesto preview, descripciones de permisos de iOS, documentación, pruebas y herramientas locales.

## Límites de la fase

- Una foto por entrada; hasta 1600 px por lado, objetivo de 700 KiB y techo de 2 MiB.
- El importador admite JPEG, PNG y WebP de hasta 16 MiB y 16 megapíxeles; reduce y comprime la copia dentro de la app. Una imagen demasiado grande se rechaza conservando el mensaje.
- Respaldo máximo de 512 MiB/5000 fotos. Si se excede, informa y conserva la copia anterior.
- El borrador se descarta al iniciar una restauración confirmada; cancelar no lo descarta.
- Mientras termina la copia automática de una entrada, el editor espera para conservar la consistencia de los datos.
- Cada copia de esta fase contiene el inventario completo. Con muchas fotografías aumentan el tiempo y los datos de subida; hay que medirlo en el móvil con una colección representativa antes de aprobar producción.
- Sugerencias diarias pendientes de una segunda fase.
- Prueba física de cámara/selector/biometría pendiente: no hay un Android conectado al PC.
- Política de privacidad revisada sólo localmente; publicación y declaraciones de Play pendientes hasta aprobar producción.
