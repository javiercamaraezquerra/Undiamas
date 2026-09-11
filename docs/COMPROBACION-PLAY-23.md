# Comprobación de la actualización distribuida por Play

Pendiente de realizar con el AAB 1.0.3+23 firmado. Esta lista no acredita resultados.

La prueba de actualización debe instalarse desde un canal de pruebas de Google
Play sobre `com.celsoriaapps.undiamas` 1.0.1 (15), sin desinstalarla ni borrar sus
datos. La app de prueba con sufijo `.privacidad` es independiente; sus datos no
se trasladan automáticamente a la app de Play. El APK firmado con la clave de
subida tampoco sustituye directamente al firmado por Google Play.

Antes de actualizar, comprobar una copia de seguridad disponible y anotar sin
exponer su contenido el número de entradas y los ajustes que se van a contrastar.

1. Tras actualizar, comprobar inventario, fechas, gráfica, fecha de inicio,
   preferencias y acceso a las mismas reflexiones y recursos. Cerrar y reabrir.
2. Comprobar el nombre original en el lanzador y en los ajustes de notificaciones.
3. Activar el bloqueo opcional: cancelar la autenticación debe mantener la app
   cerrada y completarla debe permitir entrar. Repetir al volver desde segundo
   plano. Desactivarlo debe devolver el acceso normal. Las capturas siguen
   permitidas.
4. En una cuenta/dispositivo de pruebas admitido por AdMob, verificar las opciones
   de consentimiento y que la app sigue funcionando al rechazar, sin conexión
   y al volver del segundo plano. Comprobar carga de anuncios de prueba y acceso
   a sus opciones cuando corresponda. No pulsar anuncios reales propios.
5. Comprobar la autorización real de Drive y la creación de una copia. Probar
   restauración y fallos destructivos sólo con datos ficticios en un entorno de
   pruebas, nunca provocándolos sobre el inventario personal.
6. Comprobar permisos, recepción y apertura del recordatorio, y persistencia tras
   reiniciar/actualizar. El sistema puede retrasar las alarmas inexactas.
7. Revisar el informe previo al lanzamiento de Play, compatibilidad de dispositivos,
   firma, API 36 y ausencia de errores que afecten a esta actualización antes de
   enviarla a producción.

Registrar dispositivo/Android, versión anterior, versión instalada y resultado
de cada recorrido. Una prueba simulada o un informe sin datos no equivale a una
comprobación satisfactoria en el teléfono.
