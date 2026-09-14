# Conexión de Drive en pruebas — 1.0.6+26

Revisión del 14 de septiembre de 2026. Copia local de **1.0.5+25**, commit
`e70f1ba83a4589aa95949868c28ac104f1cad117`, en
`C:\Users\Javi\Documents\Quinielalab\dist\UnDiaMas-drive-v26`.
Las copias anteriores y la versión de Google Play permanecen independientes.
Esta candidata no está publicada ni enviada a revisión.

## Cambios de esta versión

- Retirada la frase «Si usas las copias en Drive, también incluirán tus fotos.»
  del selector. Se conservan las opciones de cámara y galería y el respaldo de
  fotografías en las copias v2.
- Los errores de Drive se clasifican en configuración, cancelación, permisos,
  conexión, autenticación, disponibilidad del servicio, copia inválida,
  almacenamiento y fallo desconocido. La interfaz muestra mensajes redactados
  por la app; no muestra mensajes internos de Google, rutas ni tokens.
- El diagnóstico registra únicamente la operación y la categoría de fallo.
- Un token nulo o vacío impide iniciar solicitudes HTTP a Drive. Con un token
  válido se mantienen los mismos encabezados que utilizaba `google_sign_in`.
- La cancelación o el fallo de autenticación no se presenta como una copia
  guardada o borrada correctamente.
- Para una copia inválida, el mensaje es «La copia está incompleta o no es
  compatible.». No se recomienda sobrescribirla como respuesta a ese error.

Esta corrección no incorpora sugerencias diarias ni edición de entradas.
Conserva las funciones y las correcciones de fotografías de v25.

## Mensajes anteriores y copias automáticas

Al activar las copias en Perfil, la aplicación exporta inmediatamente todas
las entradas guardadas de `diary_secure`, sin filtro de fecha, junto a los datos
de inicio de `udm_secure`. El ZIP incluye todas las fotografías referenciadas.
El interruptor permanece desactivado hasta que esa primera subida termina
correctamente. No hace falta volver a guardar cada mensaje anterior.

Después, guardar o borrar una entrada actualiza la copia con el Inventario
completo resultante. Una conexión fallida conserva el cambio local y muestra
que Drive sigue pendiente de actualizar. El texto y la foto de un borrador
sin guardar no forman parte de la copia.

La copia se almacena en los datos privados de la aplicación en Drive
(`appDataFolder`); no aparece como un archivo corriente en «Mi unidad».
Se consulta y recupera mediante «Restaurar desde Drive» en Perfil.
Este comportamiento de almacenamiento está descrito en la
[documentación oficial de Drive](https://developers.google.com/workspace/drive/api/guides/appdata).

## Registro OAuth añadido con autorización

Se creó un **cliente Android adicional** en el proyecto Google Cloud
`app-un-dia-mas`, con permiso expreso del propietario:

| Campo | Valor |
| --- | --- |
| Nombre | Un dia mas - pruebas locales |
| Client ID | `483105798652-rgackprjtr7rn047ms53310dmrcfcq2d.apps.googleusercontent.com` |
| Paquete Android | `com.celsoriaapps.undiamas.privacidad` |
| SHA-1 del certificado de la prueba | `A1:7E:6E:0D:B1:A3:0F:D3:6C:A9:DC:E5:74:1D:CF:19:30:13:BF:EA` |

Estos son identificadores públicos de la configuración, no una clave privada.
Los **dos registros originales de producción se conservaron**. No se cambió
el certificado de la prueba ni el de producción. Google advierte que la
propagación puede tardar **de minutos a horas**.

Comprobaciones de sólo lectura en Google Cloud: Google Drive API figura como
**Habilitada**; OAuth conserva el estado **En producción**, para usuarios
externos. No se modificaron esos ajustes. Se volvió a abrir el nuevo cliente
para comprobar que paquete y SHA-1 coinciden con los del APK de prueba.

La app Android se identifica por su paquete y certificado. No se ha introducido
un `clientId` o `serverClientId` en el código, ni modificado los scopes existentes
`drive.file` y `drive.appdata`.
La identificación Android y la diferencia entre certificados de carga y de
firma de Play se contrastaron con la
[documentación oficial de autenticación](https://developers.google.com/android/guides/client-auth).

La creación del cliente confirma la configuración en Google Cloud; todavía no
demuestra un inicio de sesión o una subida satisfactoria desde el APK instalado.

## Separación respecto a producción

| Elemento | Prueba local | Producción |
| --- | --- | --- |
| Paquete | `com.celsoriaapps.undiamas.privacidad` | `com.celsoriaapps.undiamas` |
| Indicador Dart | `UDM_PREVIEW=true` | `UDM_PREVIEW=false` en CI |
| Copia con fotos | `udm_preview_backup_v2.zip` | `udm_backup_v2.zip` |
| Copia JSON antigua | `udm_preview_backup.json` | `udm_backup.json` |
| Anuncios | Banner de prueba | Banner de producción existente |

Los nombres de archivos y la carpeta privada `appDataFolder` no cambian. Las
operaciones de la prueba seleccionan exclusivamente sus nombres de copia.
La configuración Gradle, manifests, CI, verificador de producción, selección
de banner y `pubspec.lock` se contrastaron con HEAD v25 y permanecen iguales.

Producción conserva su ruta de firma: sólo `release`, configuración completa
obligatoria y comprobación en CI contra la huella de carga verificada en Play.
El verificador rechaza un paquete preview, firma de depuración o banner de
prueba como artefacto de producción. No se ha compilado ni subido una nueva
versión de producción en esta tarea.

## Verificación disponible y límites

Resultados confirmados hasta esta revisión:

- Suite completa Flutter: **440 pruebas correctas y 2 omitidas** por los enlaces
  simbólicos no disponibles en Windows, en 2 min 40 s. Registro:
  `build/validation/tests-full-v26.txt`.
- **14 tests Python correctos** de las herramientas de verificación de releases.
- `dart.exe analyze --no-fatal-warnings lib test`: **salida 0**, sin diagnósticos
  nuevos. Se mantienen 34 diagnósticos anteriores: 3 advertencias y 31
  informaciones. Registro: `build/validation/analyze-v26.txt`.
- **50 tests de Drive superados** con la configuración normal.
- Los mismos **50 tests superados con `UDM_PREVIEW=true`**, comprobando también
  la selección de archivos de la prueba.
- **16 tests de interfaz superados**, incluida la retirada de la frase del
  selector.
- **2 pruebas adicionales de integración superadas** tanto en configuración
  normal como en preview: Hive cifrado reabierto con cuatro entradas antiguas
  produce una primera copia con todos sus textos, fechas, ánimos y dos fotos
  únicas. Guardar el borrador añade una quinta entrada y una tercera foto sin
  perder ninguna anterior. La descarga recupera los JPEG exactos comprobados
  por SHA-256. Si falta una foto antigua, no se reemplaza la copia previa.
  Registros: `tests-drive-existing-inventory-v26.txt` y
  `tests-drive-existing-inventory-preview-v26.txt`, en `build/validation/`.
- Auditoría estática de la separación preview/producción y
  `git diff --check`: correctos.

Los grupos específicos originales de Drive e interfaz no se suman al total de
la suite. Las dos pruebas de integración se añadieron después: hay **442 casos
distintos aprobados**, además de los dos omitidos en Windows. Repetir los casos
en configuración preview tampoco incrementa el número de casos distintos.
**Compilación de v26 correcta**, en 16 min 3 s, con
`.\tool\local-photos.ps1 -Mode Build`. La ejecución posterior de
`.\tool\verify-preview.ps1` verificó los 84 archivos de entrada sin cambios
durante la compilación, firma válida e idéntica a v25, versión 1.0.6+26,
nombre visible original, API 36, mínimo API 24 y las tres arquitecturas.
También comprobó permisos, receptores de notificaciones, canales de fotos,
banners de prueba y alineación ZIP/ELF de 16 KiB. Los logs se guardan en
`build/validation/`.

No hay un dispositivo Android conectado. No se ha comprobado una subida real a
Drive ni una restauración real desde una cuenta. Los tests usan transportes y
datos controlados; no prueban la propagación del cliente OAuth ni sustituyen
una prueba desde el móvil.

Entrega validada: `dist/UnDiaMas-1.0.6-26-drive.apk`, junto a `SHA256.txt` y
`verificacion-android.json`. Tamaño: **79.327.640 bytes**.

SHA-256 del APK:
`4AB54813B35767AA28881BB55E196F0F19EBAF35FD41AD44A3E3A5B59F3DDF05`.

SHA-256 del certificado público:
`7DE7CAD99A5403F3318F313571E8A53432158890AC4C77978A16E1B813FE018B`.

## Archivos y comandos de esta revisión

- `lib/screens/journal_screen.dart`: retirada de la frase del selector.
- `lib/services/drive_backup_service.dart`: mensajes, clasificación segura de
  fallos y validación del token antes de conectar.
- `test/drive_backup_service_test.dart`, `test/journal_photo_layout_test.dart`,
  `test/profile_auto_backup_test.dart` y `test/drive_existing_inventory_test.dart`:
  comprobaciones de servicio, interfaz y contenido de copias.
- `pubspec.yaml`, `tool/local-photos.ps1` y `tool/verify-preview.ps1`:
  versión 26 y preparación/verificación de su APK local.
- `README.md` y este informe: alcance, resultados y prueba en el móvil.

Comandos ejecutados: `local-photos.ps1 -Mode Pub`, `local-photos.ps1 -Mode Test`,
`dart.exe analyze --no-fatal-warnings lib test`,
`python -m unittest discover -s tool -p '*_test.py' -v`,
`local-photos.ps1 -Mode Build`, `verify-preview.ps1` y `git diff --check`.
Las dos integraciones adicionales se ejecutaron con `flutter test --no-pub
--concurrency=1`, primero normal y después con `--dart-define=UDM_PREVIEW=true`.

## Prueba breve en el móvil

1. Instalar v26 **encima de la prueba v25**, sin desinstalar ni borrar los datos.
   Abrir la aplicación de pruebas, que sigue separada de la instalada desde
   Google Play. Comprobar las entradas, fotografías y ajustes anteriores.
2. Abrir el selector de fotos: deben aparecer cámara y galería, sin la frase
   de Drive. Guardar una entrada de prueba con texto, ánimo y fotografía;
   volver a abrirla y ampliar la imagen.
3. Si se quiere comprobar Drive, abrir Perfil y activar «Copias automáticas en
   Drive». Leer el consentimiento, elegir la cuenta y permitir el acceso.
   Esperar a que termine la copia inicial; un fallo no debe dejar la opción
   activada como si la copia se hubiera guardado.
4. Si Google aún no reconoce la configuración, dejar tiempo para su propagación
   y volver a intentarlo. No hace falta desinstalar ni borrar los datos para
   esperar ese cambio.
5. **Sólo si se quiere probar la restauración:** usar «Restaurar desde Drive»
   con la misma cuenta y revisar la copia recién creada antes de confirmar.
   Hacerlo inmediatamente, sin añadir cambios locales después de esa copia,
   y confirmar únicamente si el contenido mostrado es el esperado. Comparar
   texto, ánimo, fecha, fotografía y contador después de restaurar.

No hace falta borrar el Inventario ni probar con la app de producción. Una
restauración reemplaza el estado local con el de la copia elegida; por eso la
prueba opcional utiliza la misma copia recién guardada y revisada.

## Alcance de los datos

Se mantienen los modelos Hive, claves locales, cifrado de fotografías y
borradores, formato de archivo v2 y lectura de JSON antiguos. La copia v2
contiene el manifiesto y las fotografías referenciadas; el borrador no se
respalda. Drive utiliza HTTPS, sin cifrado propio de extremo a extremo.

La evidencia de importación, límites de imágenes y pruebas de v25 se conserva
en [PRUEBA-FOTOS-25.md](PRUEBA-FOTOS-25.md). Antes de una futura publicación de
estas funciones siguen pendientes la prueba de cámara/galería y Drive con la
firma correspondiente y la revisión de las declaraciones de datos y política
de privacidad descrita en ese informe.
