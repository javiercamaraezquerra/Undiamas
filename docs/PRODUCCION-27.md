# Preparación de producción 1.0.7+27

## Base confirmada

Play Console muestra **1.0.6 (26), disponible en Google Play, lanzamiento
completo**, con última actualización del canal el 15 de septiembre de 2026.
No hay cambios pendientes de publicación. El código base local y `main`
coinciden en `222e45f4fb9ad4b68eda81b9e6e662d89b31459b`.

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

Pendientes: CI de producción, comparación del recurso empaquetado, firma y
metadatos del AAB, compatibilidad y envío en Play Console. No se ha enviado
todavía la versión 27.

Las pruebas automatizadas no garantizan ausencia absoluta de fallos ni
sustituyen la comprobación de una actualización distribuida por Google Play.
La actualización de producción debe instalarse desde Play sin desinstalar
la app para conservar los datos de usuario.
