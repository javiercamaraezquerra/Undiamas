# Un día más — producción 1.0.9 (30)

**EstadoPlay: CAMBIOS EN REVISIÓN.** Envío confirmado el **01/10/2026 a las
22:56 (Europe/Madrid)**. Play Console muestra producción `1.0.9 (30)` e
«Iniciar lanzamiento completo». La compilación y las verificaciones propias
han terminado; las comprobaciones rápidas y la revisión de Google siguen en
curso. No se ha confirmado la aprobación ni la disponibilidad pública de v30.

## Envío a Google Play

- Versión de producción `1.0.9 (30)`, lanzamiento 7, enviada a revisión.
- Despliegue al 100 % en los 17 países de destino existentes.
- Publicación gestionada desactivada: Google publicará cuando complete las
  comprobaciones y apruebe la actualización, sin otro envío pendiente nuestro.
- La revisión previa permitía publicar y confirmó **0 dispositivos que pierden
  compatibilidad** en todos los factores de forma.
- ReTrace y símbolos nativos adjuntos; API mínima 24, destino 36 y tres ABI.
- Al cerrar esta entrega seguían en curso las comprobaciones rápidas de Google.
- Evidencia conservada: `../UnDiaMas-entrega-produccion-v30/play-v30-en-revision.jpg`.

El envío y la indicación previa «Ya se puede publicar» no son una aprobación
final de Google. La versión 28 ya publicada permanece como referencia de
producción durante la revisión.

## Base y procedencia

- Paquete oficial: `com.celsoriaapps.undiamas`.
- Base: `1.0.8+28`, comprobada como publicada al 100 % el 01/10/2026.
- Base documental: `060b327cf793a24c4b226ff3b4d23ce6fed71f9a`.
- Commit compilado: `8181e2dc90aeb4001f65a37ba1da01b046d9b989`.
- [GitHub Actions 36923075991](https://github.com/javiercamaraezquerra/Undiamas/actions/runs/36923075991),
  intento 1: **SUCCESS**.
- Artefacto descargado: `11192619357`. SHA-256 del ZIP original de Actions:
  `794ea138a1587722597d0e3ec0a9e44c24b612392edd76a23dc4ae30d720b711`.
- Variante `production`, `UDM_PREVIEW=false` y firma de subida existente.

Las correcciones posteriores a la implementación de producto afectan solo al
fixture de la prueba visual: resolución de fuentes reales del SDK mediante
`FLUTTER_ROOT`, nombres exactos del ZIP en Linux y desplazamiento hasta controles
que aún no estaban construidos. No se relajaron las comprobaciones ni se cambió
el workflow para superar los dos primeros intentos de CI. Los resultados que
acreditan esta entrega pertenecen a la ejecución final indicada arriba.

## Cinco mejoras incluidas

1. **Valorar desde Perfil.** Acceso permanente a la ficha oficial de Google Play.
   La acción es voluntaria y no envía una reseña por sí misma.
2. **Invitación opcional.** Una sola invitación tras usar la app en tres fechas
   locales distintas, en una transición entre pestañas que no interrumpa
   escritura, ayudas, bloqueo, permisos, consentimiento o restauración. El
   contador comienza con esta versión; no se infiere de entradas personales.
3. **Última copia confirmada.** Perfil muestra la fecha de la última subida
   confirmada por Drive desde este móvil. Un intento fallido o una restauración
   no actualizan esa fecha. No tener un registro local no significa que no
   existan copias anteriores.
4. **Búsqueda por palabras.** Lupa para filtrar el texto del Inventario sin
   distinguir tildes o mayúsculas, con limpieza de la consulta y explicación
   cuando no hay coincidencias. Las fotografías no se analizan.
5. **Calendario del Inventario.** Permite elegir un día o buscar por palabras,
   sin combinar ambos filtros. Aceptar una fecha limpia la búsqueda; abrir la
   lupa quita la fecha; cancelar conserva el filtro previo. Se mantiene la
   correspondencia con el día que muestra cada tarjeta.

En pantallas estrechas con texto ampliado, el selector se abre en modo escrito
respetando el tamaño solicitado. Se puede alternar a la cuadrícula; solo esa
cuadrícula limita su escala al 140 % para separar los siete días. Al volver a
escribir se recupera la escala elegida y se conserva la fecha seleccionada.

## Preservación de datos y configuración

Los filtros solo cambian la vista. No reescriben entradas, fechas, claves,
fotos ni borradores. Se mantienen adaptadores y esquema Hive, claves de
cifrado, formato de copias y mecanismo de restauración; no se requiere una
migración. Se añaden los registros locales necesarios para la invitación y
para la fecha de la última subida confirmada, sin inventar fechas de copias
históricas.

El código Android, permisos, dependencias y configuración de compilación siguen
iguales a v28. Se mantienen nombre, sol, montañas, posiciones de banners,
configuración oficial de publicidad y Drive, notificaciones, bloqueo, SOS y
gráfica. La firma de subida sigue siendo distinta de la firma con la que Google
Play distribuye la instalación existente: actualizar desde Play sin desinstalar.

Las **365 reflexiones** coinciden byte a byte entre colección aprobada, fuente,
commit, APK, AAB y versión 28, incluidos el 26 de abril y el 2 de noviembre.
SHA-256: `450f6b756d2d80a6375f06f5477bf00104e00642eb892d98aaae2905703bdd2b`.
También son idénticos los demás recursos propios empaquetados: citas, audio,
imagen de las montañas e imagen del sol. El único recurso generado de Flutter
que cambia frente a v28 es la fuente MaterialIcons recortada, por los iconos
utilizados por las nuevas funciones.

## Comprobaciones terminadas

- CI final: **534 pruebas Flutter correctas, 0 omitidas y 0 fallos**;
  14 pruebas Python y 8 grupos de pruebas nativas Kotlin correctos.
- Analizador: 0 errores; se conservan las 3 advertencias y 31 recomendaciones
  históricas, sin diagnósticos nuevos por estas mejoras.
- Suite local previa: 532 correctas y 2 omitidas por enlaces simbólicos de
  Windows. Esos casos sí se ejecutaron en la CI final de Linux.
- Después del ajuste visual: 9 pruebas de calendario; tras corregir el fixture
  para CI, 7 pruebas de búsqueda con fuentes reales correctas.
- Verificadores independientes: 20 pruebas Python correctas.
- Widgets reales con datos sintéticos inspeccionados en claro, oscuro y
  320×640 con texto al 200 %, incluido teclado y alternancia del selector.
- Verificación independiente APK/AAB: **PASS**. Firma original de subida,
  identidad oficial, API mínima 24 y destino 36, tres arquitecturas originales,
  publicidad de producción, permisos y contenido coherentes entre APK y AAB.
- AAB: 647 entradas firmadas verificadas. Alineación estática ZIP/ELF de
  16 KiB y configuración `PAGE_ALIGNMENT_16K` correctas.
- Comparación estática con v28: mismos requisitos de dispositivos y ABI;
  ningún dispositivo anterior queda excluido por requisitos del manifiesto.
  Play confirmó además 0 dispositivos que pierden compatibilidad.
- Verificación de contenido aprobada: **PASS**, con igualdad exacta de las
  365 reflexiones y de los cinco recursos propios empaquetados.

No se ha realizado una prueba nueva de esta revisión en teléfono físico, con
una cuenta real de Drive ni en un dispositivo de páginas de memoria de 16 KiB.
Las pruebas de transporte simulado, los widgets renderizados y la inspección
estática del binario no equivalen a esas pruebas. La app tampoco puede saber
si la persona terminó enviando una reseña en Google Play. Las comprobaciones
no garantizan ausencia absoluta de fallos.

## Artefactos conservados

Entrega local: `../UnDiaMas-entrega-produccion-v30`.

| Archivo | Bytes | SHA-256 |
| --- | ---: | --- |
| UnDiaMas-1.0.9-30-produccion.aab | 65.820.828 | 2672e83146d1eb2bbf58f4a3f07bc6e8238aa775dd23e2fe1117410cdabd97f9 |
| UnDiaMas-1.0.9-30-produccion.apk | 79.641.216 | 38f334b004910a9644b15c5db82588a648ee1d9840df766c7f4605f7ce733463 |
| UnDiaMas-1.0.9-30-codigo.zip | 14.079.439 | 3c52ce0e907bc56886d472e9ec35dfaddb6bb48ba212e904d5a068bfa43adc7d |
| mapping.txt | 51.657.885 | 24cc68f48fa3e660f55e5c2da7668cbe447bd23dee19f563ce17bbedafb97a0d |

La entrega incluye `COMMIT.txt`, `github-run.json`, `SHA256.txt`, notas,
`verificacion-ci.json`, `verificacion-independiente.json` y
`verificacion-contenido.json`, además de la captura del estado en Play.
El ZIP de código conserva el commit compilado;
los registros posteriores de publicación son documentación de la entrega.

## Repetir la verificación local

Estos comandos requieren el checkout del **commit compilado** indicado arriba.
Los verificadores locales están en `build/validation`, ignorado por Git;
no necesitan contraseñas ni acceder a almacenes privados. Tras un commit de
solo documentación, usar de nuevo un checkout del commit compilado para que
la comprobación estricta de procedencia siga teniendo sentido.

```powershell
$taskPython = 'C:\Users\Javi\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$taskApk = '.\build\production-download-v30\app\outputs\flutter-apk\app-production-release.apk'
$taskAab = '.\build\production-download-v30\app\outputs\bundle\productionRelease\app-production-release.aab'
$taskBaseline = '..\UnDiaMas-entrega-produccion-v28\UnDiaMas-1.0.8-28-produccion.apk'

& $taskPython -B .\build\validation\verify_production_artifacts.py `
  --apk $taskApk --aab $taskAab `
  --ci-report .\build\production-download-v30\validation\production-release.json `
  --expected-commit 8181e2dc90aeb4001f65a37ba1da01b046d9b989 `
  --expected-run-id 36923075991 --expected-run-attempt 1 `
  --baseline-apk $taskBaseline `
  --output-dir .\build\validation\verificacion-independiente-v30
if ($LASTEXITCODE -ne 0) { throw 'Falló la verificación independiente' }

& $taskPython -B .\build\validation\verify_content_v30.py `
  --apk $taskApk --aab $taskAab `
  --expected-commit 8181e2dc90aeb4001f65a37ba1da01b046d9b989 `
  --baseline-apk $taskBaseline `
  --output .\build\validation\content-v30.json
if ($LASTEXITCODE -ne 0) { throw 'Falló la comprobación de contenido' }
```

El workflow de producción conserva Flutter 3.32.8, Java 17, SDK 36 y
NDK 28.1.13356709. Los modos `Build` de los scripts locales `local-v29.ps1` y
`local-v30.ps1` generan pruebas aisladas; no se usan para esta entrega oficial.

## Notas para Google Play

Encuentra tus entradas del Inventario buscando por palabras o eligiendo un día en el calendario. Consulta la fecha de tu última copia confirmada en Drive. Ahora puedes valorar Un día más desde Perfil; tras varios días de uso, también te invitaremos a compartir tu opinión para ayudarnos a seguir mejorando. Gracias por acompañarnos.
