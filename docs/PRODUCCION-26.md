# Preparación de producción — 1.0.6+26

Revisión: 14 de septiembre de 2026. **Estado: en preparación.** El propietario
ha autorizado la publicación y aprobado las notas; este informe todavía no
acredita una compilación firmada de producción, envío a revisión o despliegue
de la versión 26.

## Procedencia y notas aprobadas

- Carpeta: `C:\Users\Javi\Documents\Quinielalab\dist\UnDiaMas-produccion-v26`.
- Rama: `codex/undiamas-production-v26`.
- Fuente aprobada: `5109bfd8e8b871f607299151515c3eb8027ff669`, procedente de
  `UnDiaMas-drive-v26`, versión 1.0.6+26.
- Base comparada de producción local: `da2d8882386e0ceeca8dbd3c3e6ce9f60b90fb0e`,
  versión 1.0.3+23. Play Console confirma producción activa **1.0.3 (23)** y
  ausencia de cambios pendientes de publicar al iniciar esta fase.
- Las notas aprobadas se conservan literalmente en
  [release-notes-es-ES-26.txt](release-notes-es-ES-26.txt).

Las novedades respecto a producción 23 son las fotografías opcionales del
Inventario, su visualización en la gráfica del Perfil, el borrador persistente,
las copias con fotografías y las mejoras de importación y mensajes. API 36,
contador, reflexiones, bloqueo y las funciones previas de la gráfica se
conservan. Esta fase no incorpora sugerencias diarias ni edición de entradas.

La preparación modifica la configuración de distribución y su documentación;
la aplicación parte de la fuente aprobada. El commit definitivo y los hashes
de los artefactos se registrarán con la ejecución que los genere.

## Identidad y certificado de carga

Producción conserva `com.celsoriaapps.undiamas`, nombres Un Día Más / One More
Day, mínimo Android 24, destino 36 y tres arquitecturas. El indicador
`UDM_PREVIEW=false` selecciona los anuncios y archivos de copia de producción.

Huella **SHA-256 del certificado público de carga**, contrastada previamente
con Play Console y exigida por CI:

`AB:60:18:9C:5E:41:3D:67:B5:DF:BB:34:7D:D2:FF:4E:58:04:AD:79:63:2A:F6:7E:5E:C5:6F:E7:41:4A:2C:87`

La firma de carga es diferente de la firma con la que Google Play entrega la
aplicación instalada. Un APK firmado con la clave de carga no acredita por sí
solo una actualización instalable sobre la versión de Play. La prueba preview
también tiene su propio paquete y certificado.

Los secretos originales `KEYSTORE_BASE64`, `STORE_PASSWORD`, `KEY_PASSWORD` y
`KEY_ALIAS` se leen sólo en el paso de firma del runner. No se generan claves
nuevas ni se incluyen contraseñas o keystores en los artefactos. La configuración
de Gradle bloquea producción sin firma completa; CI contrasta además la huella
esperada y verifica los artefactos resultantes.

El cliente OAuth adicional creado para `.privacidad` sirve a la prueba local.
Los dos registros originales de producción se conservan; no se ha fijado un
cliente OAuth en el código ni cambiado sus scopes.

## Workflow preparado

`.github/workflows/build-apk.yml` admite el repositorio original y las ramas
`main`, `codex/undiamas-production-v23` y `codex/undiamas-production-v26`, tanto
en el disparador como en la condición del trabajo. Mantiene permisos
`contents: read`, acciones fijadas por SHA y las versiones del entorno:
Flutter 3.32.8, Java 17, Kotlin 1.9.22, SDK 36, NDK 28.1.13356709 y CMake 3.22.1.

El flujo:

1. Conserva el lockfile y ejecuta análisis, tests Flutter y tests Python antes
   de acceder al material de firma.
2. Prepara el keystore existente, exporta únicamente su certificado público y
   contrasta la huella de carga de Play.
3. Compila APK y AAB `productionRelease` con `UDM_PREVIEW=false`.
4. Compila y ejecuta en JVM los ocho grupos de prueba existentes de
   `PhotoImportPolicy`, reutilizando los JAR de Kotlin 1.9.22 que Gradle acaba
   de resolver. No instala otro compilador ni cambia el SDK. La compilación
   Android anterior ya incluye el plugin de fotos completo.
5. Verifica paquete, versión, firmas, anuncios de producción, arquitecturas,
   recursos y correspondencia de contenidos entre APK y AAB.
6. Retira los archivos privados temporales y entrega sólo APK, AAB, mapa R8,
   informe de procedencia, hashes y registro de pruebas nativas.

Este workflow **no publica en Google Play**. La compilación firmada, la subida,
el envío a revisión y la disponibilidad en producción son estados distintos.

El verificador de producción comprueba identidad, firma y contenido, pero no
incluye por sí mismo la comprobación completa de alineación de 16 KiB. Hay que
realizarla sobre el **AAB de producción exacto**, además de las comprobaciones
que ya pasó el APK preview.

## Comprobaciones ya realizadas sobre la fuente aprobada

- **442 casos Flutter distintos aprobados**: suite inicial con 440 correctos y
  2 omitidos por enlaces simbólicos no disponibles en Windows, más dos
  integraciones adicionales. Repetir un caso en preview no aumenta este total.
- **14 tests Python** del verificador de versiones correctos.
- Drive: 50 tests en modo normal y los mismos en preview; 16 tests de interfaz.
  Las integraciones adicionales comprueban copia inicial del Inventario
  anterior, guardado de una entrada nueva, descarga exacta de fotos y rechazo
  de una subida incompleta conservando la copia anterior.
- Análisis con salida 0: no hay diagnósticos nuevos; persisten 3 advertencias y
  31 informaciones previas.
- APK preview v26 compilado y validado: 79.327.640 bytes, firma igual a v25,
  API 36/mínimo 24, tres arquitecturas y alineación ZIP/ELF de 16 KiB. SHA-256:
  `4AB54813B35767AA28881BB55E196F0F19EBAF35FD41AD44A3E3A5B59F3DDF05`.
- El propietario confirmó en su móvil que funcionan Drive, restauración y
  mensajes/fotografías. Es una comprobación de la aplicación de pruebas; la
  entrega de producción firmada por Play se comprobará por separado.

Validación local del workflow de esta preparación: estructura y condiciones
YAML correctas, sintaxis de ocho pasos Bash y cuatro bloques Python comprobada.
El bloque JVM incorporado se ejecutó sin modificaciones con JDK 17 y los JAR
existentes: **ocho grupos de pruebas aprobados**. Comprueba política, geometría
y limpieza de JPEG; no ejecuta el decodificador Bitmap de Android. Registro:
`build/validation/native-photo-policy-ci.txt`.

Los informes históricos [PRUEBA-DRIVE-26.md](PRUEBA-DRIVE-26.md) y
[PRUEBA-FOTOS-25.md](PRUEBA-FOTOS-25.md) conservan resultados, comandos y límites
de cada fase. El workflow todavía no se ha ejecutado remotamente desde esta
rama; la validación local no acredita una compilación firmada de producción.

## Pendiente de registrar durante la publicación autorizada

1. Commit definitivo, ejecución de CI y resultados sobre la fuente exacta.
2. AAB y APK de producción firmados, mapa R8, hashes y
   `build/validation/production-release.json`.
3. Alineación de 16 KiB del AAB de producción y comprobaciones de Play sobre
   API, dispositivos admitidos y versión.
4. Política de privacidad pública y declaraciones de datos revisadas para las
   fotografías y copias v2. La política local de la fase de pruebas era un
   borrador; no acredita por sí sola su publicación.
5. Subida del AAB correcto con las notas aprobadas, resultado de la revisión y
   estado de disponibilidad de producción, sin confundirlos.
6. Actualización distribuida por Play sobre la versión 23, conservando el
   Inventario y sus preferencias sin desinstalar ni borrar datos.

Las copias de producción son `udm_backup_v2.zip` y, para lectura compatible,
`udm_backup.json`. Preview utiliza nombres propios. Los datos de ambas
instalaciones no se trasladan automáticamente entre ellas.
