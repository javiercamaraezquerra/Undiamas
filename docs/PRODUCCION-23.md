# Preparación de producción 1.0.3+23

Revisión del 11 de septiembre de 2026. Candidata; este documento no acredita una publicación de la versión 23 en Play.

## Procedencia y alcance

Origen: copia local `UnDiaMas-privacidad-v22`, APK 1.0.2+22 aprobado por el usuario. Esa carpeta se conserva. Esta carpeta parte de sus fuentes y no sustituye las mejoras locales por la antigua rama principal de GitHub.

La base de Git para revisar los cambios es `40b344efcddc57888cbdc5d48986b208e1ce4d4a` del repositorio `javiercamaraezquerra/Undiamas`. La rama es `codex/undiamas-production-v23`.

Cambios adicionales respecto a la prueba 22:

- Versión 1.0.3+23; distribución de producción con nombre y paquete originales.
- Consentimiento nativo UMP antes de los anuncios y acceso a sus opciones desde Perfil cuando Google lo requiere; enlace a la política de privacidad.
- Se mantienen App ID AdMob `ca-app-pub-4402835110551152~8514445452` y banner `ca-app-pub-4402835110551152/9099084606`, con sus ubicaciones anteriores.
- Los fallos de autorización de Drive se propagan al borrado; la subida del mismo JSON se realiza desde memoria, sin generar un nuevo temporal sin cifrar.
- Política precisa sobre datos locales, Drive y AdMob. No cambia el formato de copia.
- Workflow reproducible, herramientas fijadas y comprobación del certificado.

No se ha añadido selección de edad ni modificado la audiencia, conforme a la instrucción del usuario. Esta revisión técnica no equivale a certificar todos los requisitos legales aplicables a cada territorio o a la publicidad para menores.

## Comparación con la producción real

Play Console muestra 1.0.1 (15), identificador `com.celsoriaapps.undiamas`, API de destino 36, mínimo 24 y tres arquitecturas. El AAB original descargado tiene SHA256 `82DFB06BCFA31D3F509819902556E4C86A45AD5A319805411AED18032BFB9B22`.

Certificado público de SUBIDA: `AB60189C5E413D67B5DFBB347DD2FF4E5804AD79632AF67E5EC56FE7414A2C87`.

Certificado de la aplicación INSTALADA POR PLAY: `45503C8377CD39E98080136DA0480D0DB96EFC1BAA1A9721DFA468E2A82B8437`. SHA1: `8A6BB50CC4CFA2081ED0853C52AEA1494DB41194`.

Son certificados distintos: un APK firmado con la clave de subida no sustituye directamente la instalación firmada por Google Play.

Se conservan nombres de cajas Hive, adaptadores, clave `hive_key` y configuración de almacenamiento seguro. Las pruebas de migración usan datos inventados escritos con adaptadores independientes de la versión 15. No se han leído ni alterado datos personales de un teléfono.

## Validación ejecutada

- `flutter pub get --offline --enforce-lockfile`: correcto.
- `flutter test --no-pub --reporter expanded`: 265/265 aprobadas.
- `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings`: cero errores, 3 advertencias y 36 observaciones preexistentes.
- 4 pruebas visuales: 20 capturas, 390 px y 360 px/texto 200%, claro/oscuro.
- 6 pruebas de actualización desde almacenamiento/exportación de la versión 15.
- 11 pruebas del servicio Drive y 11 de los enlaces del Perfil incluidas en la suite.
- Revisión independiente de almacenamiento, interfaz y consentimiento/bloqueo.
- Verificador de publicación: 14/14 pruebas Python; YAML, siete bloques Bash y tres bloques Python válidos; cuatro acciones fijadas a revisiones verificadas. Detalles en `CI-produccion.md`.
- Compilación Android de comprobación `assemblePreviewRelease`: correcta, incluida optimización R8. APK 1.0.3+23 aislado, 77.407.754 bytes, SHA256 `685C4A9106B52D6393CBA4DF74B2759BFA92D3A1ABA456C1FF07407B7724FC22`. Firma de pruebas igual a 22, mínimo 24/destino 36, tres ABI, alineación ZIP y segmentos ELF de 64 bits compatibles con 16 KiB. Informe `build/validation/qa-verificacion-android-v23.json`. No es el artefacto destinado a Play.
- Cuatro verificaciones del grafo de Gradle: producción rechaza el modo publicitario de pruebas; producción sin clave exige la firma original; preview rechaza el modo publicitario incorrecto y acepta su modo/clave válidos. La detección usa tareas de artefacto AGP para no confundir los intermediarios compartidos de Flutter. No se empaqueta ni firma preview en el grafo de producción. Informe `build/validation/qa-production-guards-v23.json`.

Logs locales en `build/validation`. Las simulaciones de red y autenticación no demuestran por sí solas que una petición real de anuncio o Drive funcione.

## Configuración externa realizada

- AdMob: aplicación acreditada y lista; banner real coincidente y centro de políticas sin problemas. La actividad de versiones anteriores no demuestra la entrega de anuncios en la candidata 23.
- Mensaje europeo «Un día más · consentimiento europeo» publicado para esta app, español e inglés, aceptar/no consentir/gestionar opciones. No se cambió Detapeo.
- Política corregida publicada en `https://sites.google.com/view/undiamas-privacy`. Se conserva un respaldo del HTML anterior en la carpeta de auditoría.
- Play: añadida ubicación aproximada por la IP usada por AdMob, con finalidades publicidad, análisis y prevención de fraude. Cambio guardado en Resumen de publicación; pendiente de enviarlo a revisión junto con la actualización.

## Pendiente antes de completar la publicación

1. Enviar esta rama local a GitHub y ejecutar el workflow con los secretos de firma originales. El usuario ha completado la autorización de Git en este PC; no se ha encontrado la clave privada de subida local.
2. Generación y validación del APK/AAB 23 firmados por el certificado de subida.
3. Prueba de actualización desde Play, incluida autorización real de Drive, consentimiento y carga de anuncios, y recorrido nativo de bloqueo/notificaciones. No había dispositivo Android ni emulador acelerado disponible en esta revisión. Recorrido preparado en `COMPROBACION-PLAY-23.md`.
4. Subida del AAB correcto, revisión de Play y despliegue a producción autorizado por el usuario. No confundir «enviado a revisión» con «disponible en Play».

Límites heredados: el traspaso de datos entre teléfonos puede depender del fabricante de Android y del Keystore; la copia manual en Drive sigue siendo necesaria para una recuperación portable. Esta versión evita generar nuevos JSON temporales al subir, pero no certifica la eliminación de temporales que versiones antiguas dejaran.
