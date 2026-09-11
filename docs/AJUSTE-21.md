# Prueba 21: capturas, restauración, Inventario y notificaciones

Base aceptada: `1.0.2+20`, commit
`743a1b7d8cbc39a85407a44c7b9efb29ec34e7da`. Versión de esta copia: `1.0.2+21`.

## Capturas y bloqueo

Se permiten capturas y grabaciones y se elimina íntegramente el párrafo señalado
del diálogo de activación. Recientes puede mostrar la última pantalla
desbloqueada. Al volver, la autenticación debe finalizar correctamente antes de
aceptar interacción. Salir de una sesión ya bloqueada no descubre contenido
anterior. No cambia el controlador de autenticación ni su preferencia.

## Restaurar desde Drive

1. Perfil solicita permiso para descargar la copia.
2. Se valida toda la copia sin escribir: estructura, ajustes, tipos, fechas reales
   y ánimo entre 0 y 4. Una copia malformada no sustituye el inventario.
3. Un diálogo muestra cantidades actual y entrante, informa de la sustitución
   y de la fecha de inicio. Una copia con cero entradas lleva un aviso explícito.
   Cancelar conserva los datos actuales.
4. Al confirmar se guarda y sincroniza a disco una instantánea local cifrada de
   los datos anteriores y sus claves. Solo después comienza la sustitución.
5. Se comprueban y sincronizan los datos antes de marcar la operación completada.
   Un fallo parcial intenta recuperar los originales. Si no puede confirmar la
   recuperación, la interfaz impide editar datos y permite reintentar.
6. Al arrancar, una restauración pendiente se recupera antes de abrir las
   pantallas normales. Los avisos de logros se ajustan a la fecha restaurada;
   un fallo de programación no se presenta como fallo del inventario.

Se conserva el formato de Drive existente (`udm` y `diary`), los adaptadores Hive
y la clave de cifrado. La nueva caja `restore_recovery_secure` contiene el estado
temporal de recuperación cifrado con la misma clave. No se incorpora a Drive.
Las operaciones locales se coordinan para evitar guardados/borrados durante una
restauración. La limpieza total de datos incluye esta nueva caja antes de borrar
la clave.

La apertura de las cajas impide el truncado automático ante un checksum
incorrecto. Si falta la clave pero quedan archivos cifrados, no se genera otra
clave ni se abre una instalación vacía sobre esos archivos. La pantalla de
recuperación también cubre errores de apertura. La migración de instalaciones
antiguas sin cifrar conserva claves y valores, reanuda subconjuntos compatibles
y no borra la fuente hasta comprobar el destino; las discrepancias se detienen
conservando ambas copias. Las rutas de notificaciones se aplazan mientras los
datos están ocupados o pendientes de recuperación.

## Eliminar una entrada

En Inventario, abre el menú de tres puntos de una entrada y elige **Eliminar
entrada**. Se pide confirmación y se elimina únicamente su clave estable,
conservando las demás entradas, el contador y el borrador que estés escribiendo.
También se puede eliminar una entrada recién guardada. No hay borrado por un
gesto accidental ni se elimina nada al cancelar.

Con copias automáticas activadas se intenta actualizar Drive después. Si falla,
la eliminación local se conserva y se avisa de que la copia anterior sigue
pendiente de actualizar. No se promete eliminar el contenido de copias antiguas
que no se hayan actualizado. Guardar o borrar no se ejecuta dos veces mientras
la primera operación está pendiente. El gráfico de Perfil muestra un estado
vacío cuando ya no quedan entradas, sin inventar un valor de ánimo.

## Notificaciones

Se corrigen la solicitud del permiso con la API real de la biblioteca instalada,
el registro nativo de la zona horaria, el permiso normal de reinicio y la apertura
de la reflexión al tocar un aviso con la app terminada. Los avisos esperan al
desbloqueo para abrir contenido. La programación respeta apagados posteriores,
cambios de fecha de inicio y el estado real del permiso del sistema.

Las reflexiones se planifican a las 9:00 de cada fecha local, sin desplazar la hora
al cambiar verano/invierno. Se conserva el contenido de las 365 reflexiones;
el 29 de febrero usa el texto del 28 para mantener el resto del calendario.
Se mantiene el título concreto en cada aviso y el horizonte de 60 días. Se
renueva al volver a la app otro día, cambiar zona/permisos o preferencias, sin
programar en paralelo ni entrar en bucles al bloquearse.

Se conservan canales e IDs y se usan alarmas inexactas, sin permisos de alarmas
exactas ni pantalla completa. Las limitaciones de entrega de Android y las
fuentes oficiales se detallan en `NOTIFICACIONES-21.md`. No se ha realizado una
prueba real de entrega en un móvil ni una publicación en Google Play.

## Copia y distribución

La base 15 y la prueba 20 se conservan. Por los permisos de esta sesión, esta
copia y sus herramientas están dentro de `Quinielalab/dist`, que ya estaba
excluido del repositorio. No se cambia el código de QuinielaLab.

Paquete: `com.celsoriaapps.undiamas.privacidad`. Nombre: **Un día más · Privacidad**.
La firma se ha verificado y coincide con la prueba 20 para actualizarla sin desinstalar.
La app de Google Play conserva su instalación y datos independientes. No se
publica nada. El APK de prueba está generado y verificado; los resultados y
límites de ejecución en el móvil figuran en `VALIDACION-21.md`.

Se han descartado las propuestas de borrador persistente, edición y búsqueda
de entradas, filtro de favoritos, ajustes de accesibilidad y ejercicio guiado
de grounding. No están incluidas en esta prueba.
