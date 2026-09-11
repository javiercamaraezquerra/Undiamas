# Compilación firmada de producción

`.github/workflows/build-apk.yml` sólo admite el repositorio
`javiercamaraezquerra/Undiamas` y las ramas `main` y
`codex/undiamas-production-v23`. Se ejecuta manualmente o por cambios pertinentes
en esas ramas. No publica en Google Play. No se ejecuta para pull requests.

El flujo usa Flutter 3.32.8, JDK 17, SDK 36 y NDK 28.1.13356709, conserva el
lockfile con `flutter pub get --enforce-lockfile` y ejecuta los tests de Flutter
y del verificador. El análisis mantiene los avisos heredados como no fatales;
los errores siguen deteniendo la compilación. No modifica fuentes, recursos,
audio, iconos ni aplica correcciones automáticas.

Necesita los cuatro secretos existentes: `KEYSTORE_BASE64`, `STORE_PASSWORD`,
`KEY_PASSWORD` y `KEY_ALIAS`. No dispone de firma de depuración alternativa.
Comprueba el certificado público antes de compilar, y vuelve a comprobar las
firmas de ambos artefactos después. La huella de subida verificada en Play
Console el 11 de septiembre de 2026 es:

`AB:60:18:9C:5E:41:3D:67:B5:DF:BB:34:7D:D2:FF:4E:58:04:AD:79:63:2A:F6:7E:5E:C5:6F:E7:41:4A:2C:87`

Este certificado de **subida** es distinto del certificado con el que Google
Play firma la aplicación instalada. Un APK firmado con la clave de subida
no demuestra que se pueda instalar sobre la versión distribuida por Play.

Las contraseñas se leen del entorno; el almacén y `android/key.properties`
son temporales. Un paso `always()` los elimina incluso si falla un paso
anterior. Sólo se suben los APK/AAB, el mapa R8 y los informes explícitos.
Los artefactos se retienen 30 días. Una terminación externa del runner depende
de la eliminación de su máquina temporal; el flujo no promete limpieza de
una máquina que ya no pueda ejecutar pasos.

`tool/verify_release.py` usa sólo Python estándar, SDK y JDK. Comprueba paquete,
versión de `pubspec.yaml`, minAPI 24, destino API 36, nombre original `Un Día Más`
y traducción `One More Day`, identificadores de publicidad de producción,
ausencia de variante de pruebas y las tres arquitecturas originales. Compara
los archivos Flutter y las bibliotecas de APK y AAB byte a byte. La verificación
JAR lee cada entrada del AAB para verificar su firma y exige el certificado
de subida en cada archivo fuera de `META-INF`.

El informe `production-release.json` contiene los hashes SHA256 de los
artefactos y de los archivos seguidos por Git, commit, ejecución de GitHub,
metadatos comprobados y versiones configuradas del entorno. El archivo
`production-sha256.txt` añade el hash del mapa R8. Estos datos describen la
procedencia de esa ejecución; no sustituyen la revisión de la fuente aprobada.

Validación local del 11 de septiembre de 2026: 14 pruebas estándar del
verificador; YAML analizado con el paquete `yaml` ya disponible; cuatro SHAs
de acciones comparados con `build/validation/github-action-pins.json`; sintaxis
de siete bloques Bash y tres bloques Python verificada. El AAB 15 descargado
de Play pasó identidad y firma criptográfica (567 archivos firmados); su APK
de Play pasó identidad y comparación de bibliotecas y recursos con ese AAB.
Esta validación no ha ejecutado el workflow en GitHub ni una nueva compilación
Linux, y no comprueba la entrega real de anuncios, Drive o notificaciones.

Para repetir las pruebas del verificador:

```sh
python3 -m unittest discover -s tool -p '*_test.py' -v
```
