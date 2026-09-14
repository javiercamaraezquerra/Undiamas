# Un día más — preparación de producción 1.0.6+26

Esta copia prepara la publicación autorizada de la versión probada **1.0.6+26**.
Parte del commit `5109bfd8e8b871f607299151515c3eb8027ff669` de la prueba local;
la versión de producción comprobada en Play al iniciar esta fase es **1.0.3 (23)**.
Rama: `codex/undiamas-production-v26`. Estado: **en preparación**; este documento
no acredita todavía un AAB de producción firmado ni una publicación de v26.

El propietario confirmó en el móvil las copias y restauraciones de Drive y la
conservación de mensajes y fotografías. También aprobó la publicación y el
[texto de novedades](docs/release-notes-es-ES-26.txt). Esa comprobación de la
prueba local se distingue de la futura actualización distribuida por Play.

## Novedades respecto a producción 23

- Una fotografía opcional por entrada del Inventario, desde cámara o galería,
  con miniatura, ampliación y acceso desde la gráfica del Perfil.
- Borrador cifrado que conserva texto, ánimo y foto al cambiar de pantalla.
- Copias de Drive con fotografías y lectura de las copias JSON anteriores.
- Preparación de imágenes Android y mensajes de error más claros.
- Explicación de la financiación mediante anuncios en Perfil, sin cambiar
  anuncios ni consentimiento.

Se mantienen contador, reflexiones, herramientas, notificaciones, bloqueo y
registros existentes. Las sugerencias diarias y la edición de entradas no
forman parte de esta versión.

## Identidad y compilación de producción

- Paquete: `com.celsoriaapps.undiamas`; nombre: Un Día Más / One More Day.
- Flutter 3.32.8, Java 17, AGP 8.10.1, Gradle 8.11.1 y NDK 28.1.13356709.
- API de destino 36, mínimo 24 y tres arquitecturas: `armeabi-v7a`, `arm64-v8a`
  y `x86_64`.
- `pubspec.lock` conservado y `UDM_PREVIEW=false` en producción.

El workflow `.github/workflows/build-apk.yml` admite `main`,
`codex/undiamas-production-v23` y `codex/undiamas-production-v26`, por cambios
pertinentes o ejecución manual. Compila APK y AAB con los cuatro secretos de
firma existentes del repositorio y valida la huella de carga de Play. No
publica automáticamente en Google Play ni utiliza firma de depuración como
alternativa.

```sh
flutter build appbundle --release --flavor production --no-pub --dart-define=UDM_PREVIEW=false
flutter build apk --release --flavor production --no-pub --dart-define=UDM_PREVIEW=false
```

Estos comandos requieren la configuración original de firma. El proceso de CI
la prepara temporalmente, comprueba las firmas e identidad del resultado y
retira los archivos privados. Después de compilar ejecuta las pruebas JVM de
la política de fotos con el mismo compilador Kotlin 1.9.22 resuelto por Gradle.

La variante preview sigue siendo una aplicación independiente con sufijo
`.privacidad`, certificado de pruebas y nombres de copias distintos. Su APK
no se debe subir como actualización de producción.

## Evidencia y estado

La fuente aprobada de v26 dispone de **442 casos Flutter distintos aprobados**,
además de **2 omitidos** por enlaces simbólicos no disponibles en Windows, y
**14 pruebas Python** correctas. El análisis no añade diagnósticos: conserva
3 advertencias y 31 informaciones anteriores. El APK preview fue compilado y
verificado, incluidas firma, API, contenido y alineación de 16 KiB.

El AAB de producción debe verificarse por separado, incluida su alineación de
16 KiB, y después comprobarse el resultado de la revisión y publicación en
Play. La política de fotografías y las declaraciones de datos se revisan en
esta preparación. El [informe de producción 26](docs/PRODUCCION-26.md) registra
procedencia, certificado, comprobaciones y pasos pendientes.

La evidencia de desarrollo permanece en [PRUEBA-DRIVE-26.md](docs/PRUEBA-DRIVE-26.md)
y [PRUEBA-FOTOS-25.md](docs/PRUEBA-FOTOS-25.md); describe sus respectivas pruebas
y fechas, no una publicación de este AAB.

## Conservación de datos

El adaptador Hive mantiene el tipo 1 y los campos 0–2; la foto ocupa el campo
opcional 3. Los registros anteriores siguen siendo legibles. Se conservan el
alias de la clave local y las preferencias. Las fotografías y el borrador se
cifran por separado con claves derivadas para cada propósito.

Producción utiliza `udm_backup_v2.zip` para datos y fotografías y admite las
copias antiguas `udm_backup.json`. Preview utiliza nombres `udm_preview_*`.
Las copias se validan antes de aplicar una restauración; el borrador no se
incluye en Drive. Las copias de Drive usan HTTPS, sin cifrado propio de extremo
a extremo. Las fotos no se envían a AdMob.

La actualización desde Play se instala sobre la aplicación de producción sin
desinstalar ni borrar datos. Los datos de preview pertenecen a otra instalación
y no se trasladan automáticamente a producción.
