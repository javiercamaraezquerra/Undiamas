# Un día más — actualización oficial 1.0.9+30

La nueva versión reúne acceso e invitación voluntarios para valorar la app,
fecha de la última copia confirmada en Drive y búsqueda del Inventario por
palabras o por un día del calendario, sin combinar ambos filtros.
Se conservan las 365 reflexiones aprobadas y el esquema de los datos guardados.

La compilación oficial está firmada y verificada: **534 pruebas Flutter,
14 Python y 8 grupos nativos correctos en CI**. Las verificaciones independientes
de APK/AAB y contenido han terminado con resultado **PASS**.
Paquete `com.celsoriaapps.undiamas`, variante `production` y `UDM_PREVIEW=false`.

**EstadoPlay: CAMBIOS EN REVISIÓN.** Enviada a producción el 01/10/2026 a las
22:56 (Madrid), con despliegue al 100 % en los 17 países existentes y publicación
gestionada desactivada. Google publicará cuando complete sus comprobaciones
y apruebe la actualización; aún no se confirma su disponibilidad pública.
La base 1.0.8 (28) ya estaba publicada. No se ha realizado una prueba nueva
de esta revisión en móvil físico ni con una cuenta real de Drive.

[Entrega, hashes y comprobaciones](docs/PRODUCCION-30.md) ·
[Calendario y criterios](docs/MEJORAS-30.md) ·
[Mejoras de uso incluidas](docs/MEJORAS-29.md) ·
[Notas para Google Play](docs/release-notes-es-ES-30.txt).

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
