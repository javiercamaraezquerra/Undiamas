# Producción 1.0.7+27: enviada a revisión

## Base confirmada

En la comprobación inicial, Play Console mostraba **1.0.6 (26), disponible en Google Play, lanzamiento
completo**, con última actualización del canal el 15 de septiembre de 2026.
No había cambios pendientes de publicación. El código base local y `main`
coincidían en `222e45f4fb9ad4b68eda81b9e6e662d89b31459b`.

## Cambio autorizado

Se reemplaza la colección anual de reflexiones y se incrementa `pubspec.yaml`
a `1.0.7+27`. La colección aprobada incluye las entradas del 26 de abril y
del 2 de noviembre, revisadas junto con el resto del año.

SHA-256 del JSON aprobado:
`ca04c166875f96992ecbe699e4da1be5c849d3487a5e9d92b0fed515e27693c4`.

No se modifica ningún archivo de `lib`, Android, dependencias ni otros recursos.
No se cambian claves, identificadores o estructuras de almacenamiento. Se
añade una prueba del contenido real y documentación de la actualización.

## Validación y publicación

La colección ha superado la revisión editorial y los controles de 365 fechas,
formato Markdown, extensión y repeticiones. Su hash coincide con el recurso
copiado a la app.

Validación local completada:

- 453 pruebas Flutter aprobadas; dos casos de enlaces simbólicos omitidos en
  Windows se ejecutarán en Linux. La suite incluye 11 pruebas nuevas de
  calendario y lectura del recurso real, también con texto ampliado y tema oscuro.
- Análisis completo sin errores: tres advertencias y 31 informaciones en
  código previo que no se ha modificado; ningún diagnóstico en el test nuevo.
- 14 pruebas Python del verificador de CI y 14 del verificador independiente
  aprobadas.
- `git diff --check` correcto y sin cambios en código de aplicación, Android,
  lockfile, workflow ni otros recursos.

## Compilación y verificación final

- Commit compilado: `c31b7abfde25a1757c1e9be4b737708c717b52b4`.
- [GitHub Actions 36489097981](https://github.com/javiercamaraezquerra/Undiamas/actions/runs/36489097981),
  intento 1: **SUCCESS**, 455 pruebas Flutter, 14 Python y 8 Kotlin/JVM aprobadas.
- Verificación independiente posterior a la descarga: **PASS**. Identidad,
  firmas APK/AAB, publicidad de producción, API mínima 24 y objetivo 36,
  permisos, bibliotecas nativas y alineación estática de 16 KiB correctos.
- Comparación con el APK 26: mismos requisitos de dispositivos y tres ABI.
- Los 365 textos del APK y del AAB son exactamente los aprobados. Git normaliza
  los 367 finales de línea externos del JSON de CRLF a LF; el contenido de las
  cadenas no cambia. El hash del recurso empaquetado y del blob Git es
  `9ec1625411852bda481bc543282a37f7a5024c023b013e13c27caec2e41340ba`.
- SHA-256 AAB: `1416cde1c01895c83d41924a5a1738c8d76601d4e46842d047f73cf6064d15bf`.
- SHA-256 APK: `3b2100045b50df96828fbac84a26df7b93b37aa4d6ba0fa817dd91643c582f58`.

## Envío a Google Play

Enviado el **29 de septiembre de 2026 (Europe/Madrid)**. Play Console muestra
**Cambios en revisión**, producción **1.0.7 (27)** e **Iniciar lanzamiento completo**.
Se conserva el 100 % de lanzamiento en los países de destino actuales, con
publicación gestionada desactivada. Se publicará automáticamente tras aprobarse.

Google aceptó el AAB, con archivo ReTrace y símbolos nativos adjuntos, y confirmó
**0 dispositivos que pierden compatibilidad** (19.194 compatibles). Al cerrar
esta tarea siguen en curso sus comprobaciones rápidas previas a la revisión.
El envío no implica aprobación ni disponibilidad inmediata en la tienda.

La entrega local `../UnDiaMas-entrega-produccion-v27` conserva APK, AAB, notas,
mapping, hashes, informes de CI/verificación y captura del estado en Play.
El código de aplicación corresponde al commit compilado; el registro posterior
del envío solo modifica documentación.

Las pruebas automatizadas no garantizan ausencia absoluta de fallos ni
sustituyen la comprobación de una actualización distribuida por Google Play.
La actualización de producción debe instalarse desde Play sin desinstalar
la app para conservar los datos de usuario.
