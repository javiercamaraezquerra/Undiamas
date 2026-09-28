# Un día más — actualización 1.0.7+27

Nueva colección de 365 reflexiones diarias, inspiradas en principios de la
terapia cognitivo-conductual aplicados a la recuperación de adicciones.

La base es el commit `222e45f4fb9ad4b68eda81b9e6e662d89b31459b` de la
versión 1.0.6+26. Play Console confirma que esa versión está disponible en
producción con lanzamiento completo. La actualización 27 está en preparación;
su compilación y publicación se registrarán en [PRODUCCION-27.md](docs/PRODUCCION-27.md).

## Alcance de esta actualización

- Se sustituye únicamente `assets/data/reflections.json` y se incrementa
  la versión a `1.0.7+27`.
- Se mantiene la lista de 365 textos Markdown en el mismo orden de calendario.
  El 29 de febrero conserva la reflexión del 28 de febrero.
- Se incluyen los textos aprobados del 26 de abril y del 2 de noviembre.
- Los textos tienen 228–277 palabras, contando cuerpo y pregunta.

No hay cambios en el código de la aplicación, dependencias, permisos, firma,
publicidad, consentimiento, inventario, fotografías, copias, bloqueo o
notificaciones. Las frases breves de Inicio (`quotes.json`) también se conservan.
La actualización no necesita migrar ni borrar datos.

[Notas para Google Play](docs/release-notes-es-ES-27.txt).

## Compilación y comprobaciones

Se conserva el workflow `.github/workflows/build-apk.yml`: desde `main`
ejecuta análisis, pruebas Flutter/Python, compilación de producción, pruebas
nativas Kotlin y verificación de firmas, identidad y contenido. Usa los
secretos de firma existentes y no publica automáticamente en Play.

- Paquete: `com.celsoriaapps.undiamas`; nombre: Un Día Más / One More Day.
- Flutter 3.32.8, Java 17, API de destino 36 y mínima 24.
- Tres arquitecturas originales y dependencias fijadas por `pubspec.lock`.
- Variante `production`, con `UDM_PREVIEW=false`.

```sh
flutter pub get --enforce-lockfile
flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings
flutter test --no-pub --reporter expanded
python3 -m unittest discover -s tool -p '*_test.py' -v
flutter build appbundle --release --flavor production --no-pub --dart-define=UDM_PREVIEW=false
flutter build apk --release --flavor production --no-pub --dart-define=UDM_PREVIEW=false
```

La firma requiere la configuración original preparada por CI. No se admite
una clave de prueba para esta actualización. Después de compilar, además del
verificador existente, se comparará el hash del JSON aprobado con el recurso
incluido en el APK y el AAB.

`test/reflections_asset_test.dart` verifica el calendario completo, los años
bisiestos y la lectura del contenido real en 320×640, con escala de texto 1 y 2,
en modo claro y oscuro. Se mantienen las pruebas anteriores de notificaciones
y conservación de datos.

## Historial

La entrega anterior y sus comprobaciones están documentadas en
[PRODUCCION-26.md](docs/PRODUCCION-26.md). Sus estados de envío a revisión
describen aquella fecha; Play Console ya confirma su disponibilidad pública.
