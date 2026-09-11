# Validación histórica de la prueba 20 — 10 de septiembre de 2026

Este informe corresponde exclusivamente a `1.0.2+20`. La prueba 21 permite
capturas y Recientes, y añade los cambios indicados en `AJUSTE-21.md`.
Su validación se registra por separado en `VALIDACION-21.md`.

## Pruebas automáticas

`flutter test --no-pub`: **41 pruebas correctas**, de las cuales 40 corresponden
al bloqueo y a su integración con el Inventario; la otra es la prueba de humo
que ya incluía la base.

Los casos nuevos comprueban:

- Preferencia inicialmente desactivada y lectura de una preferencia ya activada.
- Activación y desactivación únicamente después de autenticarse.
- Cancelación, métodos no disponibles, bloqueo temporal e intentos concurrentes.
- Lectura corrupta y fallos al guardar la preferencia.
- Arranque sin mostrar contenido y espera hasta que Android reanude la app.
- Ida y vuelta completas a la pantalla del PIN, sin repetir el reto.
- Cobertura de rutas secundarias, retorno desde segundo plano y reintento manual.
- Explicación previa, cancelación del diálogo y pantalla pequeña con texto grande.
- `JournalScreen` real con Hive cifrado en un directorio temporal: conserva dos
  entradas anteriores, un borrador y el ánimo elegido, incluso al rechazar el
  desbloqueo. Permite guardar después y conserva las tres entradas al cerrar y
  reabrir las cajas. Mantiene intactos el contador y las otras preferencias.

La prueba del recorrido completo detectó y permitió corregir un segundo reto
innecesario: al volver del PIN, Flutter pasa por `paused → hidden → inactive →
resumed`; el tránsito de regreso ya no se confunde con una nueva salida.

`dart analyze` sobre el controlador, la cubierta, la fila de Perfil y sus tests:
sin incidencias. El análisis global no encuentra errores; conserva 37 avisos de
estilo, deprecaciones o declaraciones sin uso en código de la base. No se ha
ampliado este cambio para limpiar otras pantallas.

El log completo de la ejecución está en `build/validation/flutter-test-final.txt`.

## Android

Se compila la variante `previewRelease` optimizada, con paquete independiente,
target API 36 y mínimo API 24. La primera compilación verificó la integración
Kotlin; una segunda incluye el cierre final del código Dart. Los logs y las
comprobaciones de paquete, firma y alineación quedan en `build/validation`.

También se ha comprobado mediante `assembleProductionRelease --dry-run` que
producción se detiene con un error explícito si faltan sus claves de firma. No
hay alternativa que firme esa variante con la clave de pruebas.

## Lo que no acredita esta validación

Las respuestas de autenticación se simulan en los tests. No hubo una ejecución
del APK en un Android operativo: no había teléfono conectado y el AVD no
consiguió arrancar sin aceleración en este PC. Se cerraron los procesos de ese
intento sin borrar el AVD ni cambiar Windows.

Por tanto, la lectura de huella/rostro, la pantalla real de PIN y la protección de
Recientes/capturas en un fabricante concreto siguen pendientes de prueba en un
móvil. No se afirma que las pruebas automáticas sustituyan esa comprobación.

Todos los registros utilizados eran ficticios. No se abrió ni modificó el
Inventario de una instalación personal ni se publicó ninguna actualización.
