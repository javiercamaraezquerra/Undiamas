# Preparación de fotos Android, v25

`PhotoImportPlugin`, registrado por `MainActivity`, expone el canal
`undiamas/photos` y el método `prepare({path: String})`. Devuelve bytes JPEG
en memoria; Dart calcula el identificador y usa `InventoryPhotoStore.importPrepared`
para validar y cifrar la imagen sin volver a comprimirla. El archivo seleccionado
se conserva hasta que la capa Dart ejecuta su limpieza de caché existente.

## Límites y conservación

- Entrada: archivo regular dentro de `context.cacheDir`, como los devueltos por
  `image_picker`. Las rutas se comparan después de resolverlas; los alias Android
  `/data/data` y `/data/user/0` son válidos si resuelven a la misma caché. Se rechazan
  rutas fuera de ella. `O_NOFOLLOW`, apertura no bloqueante y comparación de
  dispositivo/inodo evitan aceptar un enlace o un archivo sustituido durante la
  comprobación. El descriptor se abre sólo para lectura y siempre se cierra.
- Máximo de entrada: 128 MiB, 128 millones de píxeles y 20.000 píxeles por lado.
  La consulta de dimensiones ocurre antes de reservar el bitmap de píxeles.
- Decodificación con muestreo en potencias de dos hasta un máximo de 3.200 píxeles
  por lado. También se comprueban las dimensiones y la memoria del bitmap real.
  El límite de píxeles ARGB de entrada muestreada es aproximadamente 39 MiB;
  el bitmap de salida añade como máximo 9,8 MiB. El códec del dispositivo y la
  compresión usan memoria adicional, por lo que esto no promete un pico total fijo.
- Las ocho orientaciones EXIF y la reducción se aplican en un único dibujo sobre
  fondo blanco. Se genera JPEG de hasta 1.600 píxeles por lado, sin ampliación.
  Se prueba calidad 85, 75, 65 y 55 buscando 700 KiB; en calidad 55 se admite un
  máximo final de 2 MiB. Se eliminan metadatos APP1–APP15 y comentarios de la salida.
- Android determina qué formatos puede decodificar, incluidos HEIC/AVIF cuando
  el dispositivo los admite. La foto se conserva como imagen fija JPEG; animación,
  vídeo de una Motion Photo, transparencia y metadatos no forman parte del adjunto.
  Metadatos de orientación ausentes o ilegibles se tratan como orientación normal.
- No hay permisos nuevos ni escritura de JPEG sin cifrar en disco. El plugin no
  toca el inventario ni reemplaza la foto previa; esas operaciones corresponden
  al commit validado de Dart.

Un executor de un hilo y una sola solicitud en espera acota el trabajo pendiente.
Al desconectar el motor se descartan tareas en cola y callbacks antiguos. Se
comprueba la cancelación entre pasos y se liberan bitmaps mediante `finally`.
Una decodificación Android que ya ha comenzado puede terminar antes de descartarse;
no se presenta `requestCancelDecode` como cancelación garantizada.

Los errores devueltos son códigos estables, sin rutas ni excepciones internas:
`photo_unreadable`, `photo_unsupported`, `photo_too_large`, `photo_storage` y
`photo_prepare_failed`. Los errores de lectura/archivo inexistente no se confunden
con falta de espacio; `photo_storage` se reserva para `ENOSPC`.

## Verificación

Ejecutar desde esta copia:

```powershell
./tool/verify-native-photo-policy.ps1
```

El script usa Kotlin 1.9.22 y dependencias ya disponibles en este equipo.
Los ocho grupos JVM verifican límites y desbordamientos, muestreo en una malla
de dimensiones, memoria máxima, las ocho orientaciones sobre una imagen
asimétrica, reducción, eliminación de EXIF/ICC/comentarios y rechazo de salida
JPEG truncada. Además compila el plugin real contra API 36, Flutter y Exif 1.3.7.
Los registros quedan en `build/validation/native-photo-*-v25.txt`.

Estas pruebas no ejecutan `BitmapFactory`, `Canvas`, EXIF ni la caché de Android.
El APK requiere comprobar en un teléfono: JPEG normal, foto grande 48/108 MP,
foto girada, PNG transparente, HEIC/AVIF si existen, Motion Photo, cambio de foto,
cancelación del selector y repetición tras salir/volver a la aplicación.

## Fuentes primarias consultadas

- [BitmapFactory.Options, Android Developers](https://developer.android.com/reference/android/graphics/BitmapFactory.Options):
  `inJustDecodeBounds` consulta dimensiones sin reservar píxeles; `inSampleSize`
  utiliza potencias de dos; `inScaled` puede desactivarse; `inPreferredColorSpace`
  permite solicitar sRGB desde API 26. La cancelación de decodificación dejó de
  tener efecto desde API 24.
- [BitmapFactory, Android Developers](https://developer.android.com/reference/android/graphics/BitmapFactory):
  `decodeFileDescriptor` permite reutilizar el descriptor, devuelve nulo cuando
  no puede decodificar y acepta opciones de lectura de dimensiones y muestreo.
- [AndroidX ExifInterface, Android Developers](https://developer.android.google.cn/reference/androidx/exifinterface/media/ExifInterface):
  el constructor con descriptor lee etiquetas y no lo rebobina; el llamante
  conserva la responsabilidad de cerrarlo. Se usa la dependencia directa 1.3.7.
- [Motion Photo format, Android Developers](https://developer.android.google.cn/media/platform/motion-photo-format?hl=en):
  una Motion Photo puede contener una imagen principal JPEG/HEIC/AVIF y vídeo
  adicional. Esto motiva normalizar con el decodificador de Android antes del
  almacenamiento JPEG estricto; no identifica por sí solo la causa de una foto
  concreta del usuario que no se haya podido inspeccionar.
