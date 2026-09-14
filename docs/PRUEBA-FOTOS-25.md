# Corrección de fotografías — 1.0.5+25

Prueba local que actualiza 1.0.4+24. No publicada ni enviada a GitHub/Google Play.

## Qué se ha corregido

- El importador anterior rechazaba JPEG cuyo último byte no perteneciese al cierre de la imagen, incluidos archivos válidos con vídeo de foto en movimiento o datos añadidos. Ahora localiza el cierre real respetando segmentos, escapes y escaneos progresivos. Los JPEG almacenados y restaurados mantienen el formato estricto anterior.
- Android prepara la imagen en un hilo de trabajo: lee dimensiones, reduce antes de cargar todos los píxeles, aplica orientación, elimina metadatos y devuelve sólo la copia pequeña. Esto amplía compatibilidad frente al decodificador Dart y evita trasladar el original completo a Flutter. La compatibilidad HEIC/AVIF depende de la versión y los decodificadores del dispositivo.
- El retorno del selector espera si una operación temporal ocupa el almacenamiento. Si hubo un borrado o restauración, descarta el resultado antiguo para no recuperar datos que se habían reemplazado.
- Los errores distinguen cámara no disponible, acceso, formato, lectura, tamaño y guardado. El texto se redacta en la app: nunca se muestran rutas privadas ni mensajes internos del sistema.
- Los avisos tienen fondo opaco, texto legible y acciones adaptadas. Cancelar el selector no es un error. Al cambiar una foto, la anterior y el texto se conservan hasta que la nueva copia queda validada y su borrador guardado.
- Cuando hay texto o foto y falta ánimo, aparece «Elige cómo te sientes para guardar tu día» junto al botón.

Son problemas comprobados en el código y en pruebas de regresión. Sin la foto concreta ni registros del móvil, no se atribuyen los dos fallos comunicados a una causa única demostrada.

## Prueba breve en el móvil

1. Instala sobre la prueba anterior, sin desinstalarla. Comprueba que siguen las entradas y fotos ya guardadas.
2. Escribe una frase y selecciona ánimo. Añade una foto de galería; cámbiala dos o tres veces, incluyendo la que dio el aviso.
3. Cancela una selección: deben seguir la foto anterior y el texto.
4. Cambia a cámara, haz una foto y vuelve. Repite con el bloqueo opcional activo.
5. Guarda, vuelve a abrir la entrada y amplía la foto. Comprueba orientación y que no aparecen duplicados.
6. Sin elegir ánimo, añade texto o foto: debe aparecer la explicación junto a Guardar; al elegirlo, desaparece y permite guardar.

Las ubicaciones de banners, el consentimiento, el nombre visible, el sol, las montañas y los formatos de datos/copias siguen los de la prueba anterior. Las sugerencias de fotos diarias corresponden a una fase posterior.

## Verificación

Resultados locales:

- **APK final compilado y verificado el 14/09/2026**: `dist/UnDiaMas-1.0.5-25-fotos-corregidas.apk`, 79.327.648 bytes. `assemblePreviewRelease` terminó correctamente en 16 min 2 s.
- Verificados: nombre original Un Día Más / One More Day, API 36, mínimo API 24, tres arquitecturas, firma igual a v24, alineación ZIP/ELF de 16 KiB y banners de prueba. El canal de fotos está presente en Dart y en Android dentro del APK. No se añadieron permisos de cámara ni acceso general a galería/almacenamiento.
- SHA-256: `8C5BEC420881E17DAE1BEA0553FE9FAB67C80412E5B41646FE974BD0D68DAC8C`. Los **84 archivos de entrada** conservaron sus hashes entre el inicio de la compilación y la verificación final.
- Suite completa Flutter: **402 pruebas pasadas, 2 omitidas** porque Windows no permite crear los enlaces simbólicos requeridos por esos dos casos. Registro `tests-full-final-v25.txt`.
- Tras pulir la clasificación de fallos al escribir la copia cifrada, **27 pruebas de controlador y avisos pasadas**, incluyendo un caso nuevo de acceso denegado al almacenamiento privado. Son **403 casos Flutter distintos verificados** entre ambas ejecuciones. Registro `tests-final-controller-v25.txt`.
- **14 pruebas Python pasadas** para las herramientas de verificación de versiones.
- **8 grupos JVM pasados**: límites, muestreo, orientación y cabeceras JPEG. Plugin Android completo compilado contra API 36, Flutter y Exif 1.3.7.
- Análisis final de `lib` y `test`: sin errores ni avisos nuevos. Persisten los **3 warnings y 31 infos** del código anterior. Registro `analyze-final-v25.txt`.
- Capturas revisadas en tema claro/oscuro, pantalla de 320 px y texto al 200 %; avisos y botones sin desbordamiento. Las imágenes de prueba son sintéticas.

Los registros y las capturas de las verificaciones están en `build/validation/`. El APK y su hash se entregan en `dist/`; `verificacion-android.json` contiene las comprobaciones de firma, paquete, API, permisos y alineación.

No hay Android conectado al PC. Las pruebas automáticas cubren lógica, datos, interfaz y canal de comunicación; las pruebas Kotlin en JVM cubren límites, muestreo, ocho orientaciones y limpieza de metadatos. No acreditan una prueba física de cámara/HEIC, biometría ni Drive.

Comandos ejecutados:

```powershell
.\tool\local-photos.ps1 -Mode Pub
.\tool\local-photos.ps1 -Mode Test -TestLog tests-full-final-v25.txt
.\tool\local-photos.ps1 -Mode Test -TestTargets @('test/journal_composer_controller_test.dart','test/journal_photo_issue_test.dart') -TestLog tests-final-controller-v25.txt
# Con el dart.exe del runtime Flutter 3.32.8:
dart analyze --no-fatal-warnings lib test
python -m unittest discover -s tool -p '*_test.py' -v
.\tool\verify-native-photo-policy.ps1
.\tool\local-photos.ps1 -Mode Build
.\tool\verify-preview.ps1
```

## Archivos de esta corrección

- `lib/services/android_photo_preparer.dart` y `android/app/src/main/kotlin/com/celsoriaapps/undiamas/PhotoImportPlugin.kt`, `PhotoImportPolicy.kt`, `MainActivity.kt`: preparación y registro nativos. `android/app/build.gradle`: dependencia EXIF directa.
- `lib/services/inventory_photo_store.dart`: lectura de JPEG fuente con datos añadidos y excepciones tipadas; conserva el formato de las fotos cifradas.
- `lib/services/journal_composer_controller.dart` y `journal_photo_issue.dart`: coordinación, conservación del borrador y avisos.
- `lib/screens/journal_screen.dart` y `lib/widgets/journal_feedback_card.dart`: presentación del aviso, progreso, acciones y ayuda del ánimo.
- Pruebas de fotos, controlador, interfaz, mensajes, canal nativo y utilidades Kotlin; herramientas de compilación/verificación, `pubspec.yaml`, README y este informe.

La revisión independiente no encontró regresiones materiales en reemplazo, cancelación, borrado/restauración durante la preparación, guardado parcial o cobertura del bloqueo de la app al regresar de cámara.

## Referencias de implementación

La lectura de dimensiones y la reducción antes de cargar los píxeles siguen la [guía de Android para imágenes grandes](https://developer.android.com/topic/performance/graphics/load-bitmap) y las opciones documentadas de [BitmapFactory.Options](https://developer.android.com/reference/android/graphics/BitmapFactory.Options). La preparación produce un JPEG nuevo que pasa la validación y el cifrado existentes.
