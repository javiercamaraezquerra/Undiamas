# Validación local de la candidata 1.0.2+21

Fecha: 10 de septiembre de 2026. Base: prueba 20, commit
`743a1b7d8cbc39a85407a44c7b9efb29ec34e7da`, conservada sin cambios en su carpeta.
El alcance está en [AJUSTE-21.md](AJUSTE-21.md).

## Resultado

| Verificación | Resultado |
| --- | --- |
| Dependencias offline con lockfile exigido | Correcta; sin cambiar versiones |
| `flutter test --no-pub --reporter expanded` | **176/176 aprobadas** |
| Análisis focal de servicios, bloqueo y tests | Sin incidencias |
| `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` | Sin errores; 3 warnings y 36 avisos informativos de estilo/deprecaciones |
| Render del Inventario y diálogo corto, claro/oscuro a 390 px | Dos pruebas de widgets aprobadas; imágenes revisadas |
| Compilación Dart de release para ARM32, ARM64 y x86_64 | Terminó; generó sus bibliotecas e imágenes Flutter |
| `assemblePreviewRelease` offline | **Completado: BUILD SUCCESSFUL in 12m 12s** |
| APK final, firma, manifiesto empaquetado y alineación | **Verificados**, según `dist/verificacion-android.json` |
| Ejecución en un móvil o emulador Android operativo | No realizada; `DeviceRuntimeTested: false`, sin dispositivo conectado |

Los avisos globales no se presentan como una revisión limpia de todo el proyecto.
La pantalla de recuperación, cifrado/migración/restauración, claves estables de
borrado, conservación de borradores, gráfico vacío, bloqueo y notificaciones
tienen pruebas específicas. El detalle de las 58 pruebas de notificaciones y
sus límites figura en [NOTIFICACIONES-21.md](NOTIFICACIONES-21.md).

## Registros y conservación

Los registros están en `build/validation/`: `tests-offline-v21.txt`,
`analyze-privacy-v21.txt`, `analyze-project-v21.txt`, `build-offline-v21.txt` y
`journal-preview-light-v21.txt` / `journal-preview-dark-v21.txt`.
`source-diff-v21.txt` enumera archivos cambiados y añadidos frente a la prueba
20; `dart-source-hashes-v21.json` identifica las fuentes Dart probadas.

`preserved-files-v21.json` confirma que siguen idénticos los recursos de la app,
el lockfile, el modelo/adaptador de Inventario y el controlador de autenticación.
No se ha modificado el inventario real ni publicado nada en Play o GitHub.

La imagen vigente del aviso corto es
`build/validation/previews/journal-delete-390-light-v21.png` (también hay modo
oscuro). La imagen previa `journal-delete-320-text2-v21.png` es histórica y
contiene el texto anterior; no representa esta revisión. La prueba previa de
320 px con texto al 200 % detectó un desbordamiento heredado en la fila de ánimo
del fondo; no se afirma haber validado toda la app en todos los tamaños de letra.

## APK entregado y verificación del paquete

La compilación y la verificación final han terminado. La denegación de un
intento anterior ya no describe el estado de entrega. El APK está en
`dist/UnDiaMas-privacidad-1.0.2-21.apk`; las instrucciones para actualizar la
prueba 20 sin desinstalar están en `dist/LEEME-PRUEBA.txt`.

El informe `dist/verificacion-android.json`, generado el 10 de septiembre de
2026 a las 23:08:35 +02:00, registra:

| Propiedad del APK | Resultado |
| --- | --- |
| Paquete | `com.celsoriaapps.undiamas.privacidad`, separado de producción |
| Versión | `1.0.2+21` |
| Android mínimo / destino | API 24 / API 36 |
| Arquitecturas | `arm64-v8a`, `armeabi-v7a`, `x86_64` |
| Firma | Verificada; mismo certificado que la prueba 20 |
| Alineación ZIP de 16 KiB | Verificada |
| Alineación LOAD de ELF de 64 bits a 16 KiB | Verificada |
| Permiso de notificaciones | Presente |
| Reprogramación tras reinicio | Declarada |
| Permisos de alarma exacta o pantalla completa | Ausentes |
| Tamaño | 77.014.226 bytes |

SHA-256 del APK:
`2CC004FF5B682DB39084D3553988C3B4AD3BE331807F6DAC688ADB42A369420B`.

SHA-256 del certificado:
`7DE7CAD99A5403F3318F313571E8A53432158890AC4C77978A16E1B813FE018B`.

`../undiamas-runtime/Generar-APK-21.cmd` y `verify-apk-v21.ps1` siguen
disponibles para repetir la generación/verificación local. No publican la app.

La doble comprobación de alineación sigue la documentación de
[Android sobre páginas de 16 KB](https://developer.android.com/guide/practices/page-sizes).
Ni compilar ni comprobar el paquete sustituye la
[prueba pendiente en el móvil](PRUEBA-MOVIL-21.md). No se ha verificado aquí la
entrega real de notificaciones, la autenticación biométrica/PIN ni una operación
real de Google Drive. Tampoco se ha subido ni publicado esta versión en Play.
