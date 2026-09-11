# Prueba en el móvil: versión 1.0.2+21

La candidata se llama **Un día más · Privacidad** y usa el paquete
`com.celsoriaapps.undiamas.privacidad`. Es independiente de la aplicación de
Google Play. Instalar encima de la prueba 20, sin desinstalar ni borrar sus
datos. La verificación de entrega ha confirmado que el APK usa la misma firma
que la prueba 20.

## Recorrido breve

1. Comprobar que siguen las entradas, ajustes y fecha de inicio de la prueba
   anterior. Crear una entrada ficticia para las comprobaciones siguientes.
2. Activar el bloqueo en Perfil. Hacer una captura, abrir Recientes y volver:
   el contenido de Recientes puede mostrarse como antes; entrar en la app
   requiere autenticación. Cancelarla debe dejar la app bloqueada. Desactivar
   el ajuste devuelve el acceso normal.
3. Abrir el menú de una entrada y elegir **Eliminar entrada**. Cancelar primero
   y comprobar que sigue ahí. Después eliminar sólo la entrada ficticia. Las
   demás entradas y un borrador que se esté escribiendo deben conservarse.
   La confirmación tiene un único párrafo. Con copias automáticas, se intenta
   actualizar Drive; un fallo se avisa sin deshacer el borrado local.
4. Para probar una restauración, usar una copia de datos ficticios de esta
   instalación. Revisar el resumen antes de confirmar. Cancelar no sustituye
   nada. Confirmar sustituye el inventario por el de la copia, con recuperación
   local si la escritura falla. No usar el inventario de producción para
   provocar fallos de prueba.
5. Activar/apagar los avisos en Perfil y comprobar el permiso de Android. La
   prueba de recepción, reinicio y apertura de la reflexión se detalla en
   [NOTIFICACIONES-21.md](NOTIFICACIONES-21.md). Los recordatorios usan alarmas
   inexactas; no se promete una recepción al segundo a las 09:00.

## Límites de esta entrega

Las pruebas automáticas usan respuestas simuladas de autenticación,
notificaciones y transporte Drive, y archivos Hive reales con datos ficticios.
No sustituyen la prueba del diálogo del sistema, entrega de una notificación
o inicio de sesión de Google en un teléfono. Esta combinación de paquete y
firma de pruebas puede requerir una configuración OAuth propia para Drive;
no se ha modificado la configuración de la cuenta de Google.

Esta candidata conserva las 365 reflexiones y programa avisos con títulos
concretos para 60 días, renovándolos al volver a la app. No se ha incorporado
la alternativa de recordatorio diario genérico.

No se publica en Google Play ni GitHub. El informe de validación del APK
debe consultarse junto al resultado de estas pruebas antes de preparar una
versión de producción.
