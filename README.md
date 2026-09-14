# Un día más — producción 1.0.6+26 en revisión

Esta copia corresponde a la publicación autorizada de la versión probada **1.0.6+26**.
Parte del commit `5109bfd8e8b871f607299151515c3eb8027ff669` de la prueba local;
la versión de producción comprobada en Play al iniciar esta fase es **1.0.3 (23)**.
Rama: `codex/undiamas-production-v26`. A las **00:22 del 15 de septiembre de
2026 (Madrid)**, Play Console confirma **Cambios en revisión**: la versión 26
y la declaración de seguridad de los datos se enviaron a Google. El AAB de
producción está firmado, verificado y subido; **la versión aún no está
disponible públicamente**. La publicación gestionada está desactivada, por lo
que Google publicará el lanzamiento completo cuando lo apruebe.

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

La [ejecución de CI 34902056060](https://github.com/javiercamaraezquerra/Undiamas/actions/runs/34902056060)
del commit `678a178c6050ea71657a4c1e15f2aaf2a3b1db5b` completó **444 pruebas
Flutter, 14 Python y 8 grupos de pruebas nativas** correctamente. Los dos
casos de enlaces simbólicos omitidos en Windows se ejecutaron en Linux.
El análisis conserva 3 advertencias y 31 informaciones anteriores, sin
diagnósticos nuevos.

El APK y el AAB de producción firmados superaron la verificación independiente
de identidad, certificado, contenido y alineación de 16 KiB. Play confirmó
API 36, mínimo 24, tres arquitecturas y ningún dispositivo excluido respecto
a producción 23. La política de privacidad está publicada y la declaración
de datos está enviada a revisión junto con la versión.

La entrega estable local está en la carpeta hermana `UnDiaMas-entrega-produccion-v26`,
fuera de `build`; los artefactos remotos corresponden a la ejecución de CI enlazada.
El [informe de producción 26](docs/PRODUCCION-26.md) registra procedencia,
hashes y límites de la verificación. Quedan pendientes las comprobaciones y
la revisión de Google, la disponibilidad pública y la prueba de actualización
desde Play conservando el Inventario y las preferencias.

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
