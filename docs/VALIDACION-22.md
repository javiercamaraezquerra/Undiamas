# Validación local de la candidata 1.0.2+22

Fecha: 11 de septiembre de 2026. Base: prueba `1.0.2+21`, conservada en su carpeta.
Alcance: [gráfica de Perfil y consulta de entradas](GRAFICA-22.md).

## Estado de las comprobaciones

| Comprobación | Resultado disponible |
| --- | --- |
| Suite completa final, tras el último ajuste visual | **212/212 pruebas aprobadas** |
| Casos relacionados con la gráfica, incluidos en la suite | **39**: 12 de interfaz, 3 de estado vacío, 19 del modelo temporal, 4 de integración de Perfil y 1 de privacidad |
| Render adicional final de Perfil real | **2/2 pruebas aprobadas**, claro y oscuro; capturas de Perfil y detalle revisadas sin recortes |
| Análisis dirigido de los 8 archivos revisados | **Sin incidencias** |
| `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` | **Exit 0: 0 errores, 3 warnings y 38 avisos informativos** |
| Compilación y verificación del APK 22 | **BUILD SUCCESSFUL in 14m 8s**; APK verificado según `dist/verificacion-android.json` |
| Ejecución en móvil/emulador Android operativo | No realizada; no hay dispositivo conectado |

Las 41 incidencias globales se desglosan en 39 heredadas de la prueba 21
(3 warnings y 36 avisos informativos) y 2 avisos nuevos de llaves en el renderer
de pruebas `build/validation/profile_graph_preview_test.dart`. Ninguna está
en los 8 archivos comprobados mediante el análisis dirigido. El análisis global
no se presenta como una revisión sin incidencias de todo el proyecto.

Las pruebas incluyen periodos de calendario y cambios de hora, huecos entre
registros, entradas coincidentes sin fusionarlas, lectura de texto completo,
datos inválidos, Inventario vacío y actualización tras borrar o restaurar.
El test de privacidad utiliza el bloqueo real de la app con autenticación
simulada: comprueba interacción y semántica bloqueadas, autenticación fallida
y sustitución de datos mientras la app está cubierta, sin volver a mostrar la
entrada anterior al desbloquear.

Los renders son del motor Flutter en pruebas de widgets. No acreditan la
ejecución en un teléfono, la entrega real de notificaciones, la biometría/PIN
del sistema ni una operación real de Drive. No se ha publicado la candidata en
Google Play ni se afirma cumplimiento general de sus políticas.

## Alcance y conservación

`build/validation/source-diff-v22.txt` y `preserved-files-v22.json` identifican
exactamente **4 archivos de código productivo** añadidos o modificados:

- `lib/widgets/mood_trend_chart.dart`
- `lib/widgets/mood_entry_detail_sheet.dart`
- `lib/utils/mood_timeline.dart`
- `lib/screens/profile_screen.dart`

El informe comprueba **63 archivos idénticos a la prueba 21**, incluidos código
de otras pantallas, servicios de guardado/borrado/restauración, bloqueo,
notificaciones, modelos/adaptadores, recursos, archivos nativos, Gradle y
`pubspec.lock`. La gráfica escucha las operaciones de datos y la caja: invalida
su detalle al cambiar o dejar de estar disponible el Inventario. Esta revisión
no modifica esos servicios ni el formato de los datos.

La consulta es de solo lectura: no promedia, fusiona ni reescribe entradas.
Las pruebas usan datos ficticios. No se ha borrado ni alterado el Inventario
real del usuario; la instalación de producción permanece separada.

## Registros y APK entregado

Registros en `build/validation/`: `tests-offline-v22.txt`,
`tests-targeted-v22.txt`, `tests-mood-timeline-v22.txt` y
`tests-profile-renders-v22.txt`; capturas en `previews/`. Los archivos
`tests-ui-first-v22.txt` y las tandas iniciales son diagnósticos históricos;
el resultado final es la repetición completada después de acortar la leyenda
y hacer compacto el modal de lectura de entradas cortas.
`dart-source-hashes-v22.json` identifica las **39 fuentes Dart**, cuyos hashes
se han cotejado con las fuentes validadas. La base y el APK de la prueba 21
se han comprobado y permanecen intactos.
`delivery-final-v22.json` registra que APK compilado, APK entregado y hash
del informe Android coinciden, y que las 39 fuentes siguen siendo las validadas.

APK: `dist/UnDiaMas-privacidad-1.0.2-22.apk`. El informe
`dist/verificacion-android.json`, del 11 de septiembre de 2026 a las 00:16:28
+02:00, confirma:

| Propiedad del APK | Resultado verificado |
| --- | --- |
| Paquete y versión | `com.celsoriaapps.undiamas.privacidad`, `1.0.2+22` |
| API mínima / destino | 24 / 36 |
| Arquitecturas | `armeabi-v7a` (ARM32), `arm64-v8a` (ARM64), `x86_64` |
| Firma | Válida; mismo certificado que la prueba 21 |
| Alineación ZIP de 16 KiB | Correcta |
| Alineación de segmentos LOAD de ELF de 64 bits a 16 KiB | Correcta |
| Notificaciones y reprogramación tras reinicio | Permiso y recepción declarados |
| Permisos de alarmas exactas o pantalla completa | Ausentes |
| Tamaño | 77.325.630 bytes |
| Prueba de ejecución en dispositivo | `DeviceRuntimeTested: false` |

SHA-256 del APK:
`2BD0330079A7FEF2A846B388A25985CDAB90D3CA6F652C76A86B8A26B9B1F11F`.

`../undiamas-runtime/offline-app-v22.ps1`, `generar-apk-v22.ps1` y
`verify-apk-v22.ps1` permiten repetir la generación y verificación local.
No publican la app. Las instrucciones para actualizar sobre la prueba 21 sin
desinstalar están en `dist/LEEME-PRUEBA.txt`. La verificación del paquete no
sustituye la comprobación pendiente en un dispositivo Android real.
