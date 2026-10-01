# Un día más — candidata local 1.0.9+29

Mejoras autorizadas el 01/10/2026: acceso voluntario a Google Play desde
Perfil, invitación opcional tras tres días distintos de uso, fecha de la
última copia confirmada en Drive y búsqueda local en el Inventario.

Base: `060b327cf793a24c4b226ff3b4d23ce6fed71f9a` (1.0.8+28).
Esta candidata se desarrolla en una carpeta independiente y no se ha enviado
a Google Play. Alcance, criterios y pruebas: [MEJORAS-29.md](docs/MEJORAS-29.md).
La colección de reflexiones de v28 se conserva sin cambios.

APK de prueba preparado y verificado: `dist/UnDiaMas-1.0.9-29-mejoras.apk`.
523 pruebas Flutter correctas y 2 omitidas por limitación de Windows; 14 pruebas
Python correctas. Pendiente la prueba en el móvil y con una cuenta real de Drive.

## Entrega anterior: 1.0.8+28

Reflexiones diarias revisadas para seguir mejor el hilo: escenas más concretas,
ideas mejor conectadas y preguntas claras. Conservan su tono cercano y su
inspiración en principios de la terapia cognitivo-conductual aplicados a la
recuperación de adicciones.

La base es `ae3358c62d4d521328dc5f14f0be68bfd330cc6f`, versión 1.0.7+27,
confirmada como disponible en Google Play antes de preparar esta entrega.
La actualización se ha enviado a revisión para producción el 01/10/2026.
Google completará las comprobaciones y, si la aprueba, se publicará al 100 %
automáticamente. Estado y evidencias: [PRODUCCION-28.md](docs/PRODUCCION-28.md).

## Alcance

Se sustituye `assets/data/reflections.json` por la colección aprobada y se
incrementa la versión. Son 365 reflexiones: 183 revisadas y 182 conservadas,
con 232–277 palabras de cuerpo y pregunta. Se mantienen fechas, títulos y
orden, incluidos los textos especiales del 26 de abril y 2 de noviembre.
El 29 de febrero sigue usando la reflexión del 28 de febrero.

El código de aplicación, las dependencias, los permisos, el nombre, la firma,
el Inventario, las fotos, Drive, la publicidad y las notificaciones se conservan.
No hay migraciones ni borrado de datos. Las citas de Inicio siguen iguales.

[Notas para Google Play](docs/release-notes-es-ES-28.txt).

## Compilación y comprobaciones

Se conserva `.github/workflows/build-apk.yml`, que desde `main` ejecuta
análisis, pruebas Flutter/Python, compilación firmada de producción, pruebas
nativas Kotlin y verificación de identidad, firmas y contenido. No publica
por sí solo en Google Play.

- Paquete `com.celsoriaapps.undiamas`; nombre Un Día Más / One More Day.
- Flutter 3.32.8, Java 17, API de destino 36 y mínima 24.
- Dependencias fijadas por `pubspec.lock`; tres arquitecturas originales.
- Variante `production`, con `UDM_PREVIEW=false` y firma de subida existente.

```sh
flutter pub get --enforce-lockfile
flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings
flutter test --no-pub --reporter expanded
python3 -m unittest discover -s tool -p '*_test.py' -v
flutter build appbundle --release --flavor production --no-pub --dart-define=UDM_PREVIEW=false
flutter build apk --release --flavor production --no-pub --dart-define=UDM_PREVIEW=false
```

Las pruebas del recurso real comprueban calendario ordinario y bisiesto,
contenido empaquetado y lectura completa de las entradas seleccionadas en
320×640, con texto normal y ampliado, en temas claro y oscuro. Después de
compilar se debe comparar el recurso del APK y AAB con la colección aprobada.
La firma de subida difiere de la firma de distribución de Google Play; el APK
firmado por CI no acredita una actualización sobre la instalación de Play.

## Historial

[Versión 27](docs/PRODUCCION-27.md) · [Versión 26](docs/PRODUCCION-26.md)
