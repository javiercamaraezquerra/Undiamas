# Notificaciones de la candidata 21

Revisión: 10 de septiembre de 2026. Este documento registra los cambios locales y las pruebas pendientes antes de una futura versión de producción. No acredita el cumplimiento global de Google Play ni autoriza publicar la app.

## Cambios aplicados

- **Zona horaria real:** `MainActivity.configureFlutterEngine` registra explícitamente `TzPlugin`. El servicio inicializa la base de zonas y consulta la zona del dispositivo antes de programar. Un error de zona se comunica; no se sustituye silenciosamente por UTC.
- **Permiso comprobado:** `AchievementService` utiliza las APIs tipadas `areNotificationsEnabled()` y `requestNotificationsPermission()`. Una respuesta desconocida o un error no equivalen a permiso concedido. Android 13 y posteriores requieren `POST_NOTIFICATIONS` para estos avisos; una instalación nueva empieza con ellos desautorizados. [Permiso de notificaciones — Android](https://developer.android.com/develop/ui/compose/notifications/notification-permission).
- **Decisión en Perfil:** al activar un aviso se solicita permiso si falta. Si se deniega, no se guarda la activación ni se programa; aparece la acción opcional «Abrir ajustes». El canal nativo `undiamas/notifications` abre los ajustes de la app únicamente al tocar esa acción o la fila que lo indica. No se abren automáticamente después de una denegación. Al regresar se actualiza el estado del sistema sin sobrescribir las preferencias deseadas. La solicitud inicial existente también usa la API correcta y espera al desbloqueo de privacidad.
- **Reinicio y actualización:** se declara `RECEIVE_BOOT_COMPLETED` y se conserva el receptor del plugin con `BOOT_COMPLETED` y `MY_PACKAGE_REPLACED` para recuperar su programación persistida. El primero es un permiso normal, sin nuevo diálogo de autorización; el segundo identifica una actualización instalada sobre la misma app. Android elimina las alarmas al apagar el dispositivo, por lo que esta recepción es necesaria. [Permiso de arranque](https://developer.android.com/reference/android/Manifest.permission#RECEIVE_BOOT_COMPLETED), [actualización de la app](https://developer.android.com/reference/android/content/Intent#ACTION_MY_PACKAGE_REPLACED), [alarmas y reinicio](https://developer.android.com/develop/background-work/services/alarms).
- **Canales y modo conservados:** se mantienen `achievements` («Logros de sobriedad») y `daily_reflection` («Reflexión diaria»), así como `inexactAllowWhileIdle`. No se añaden permisos de alarmas exactas ni avisos a pantalla completa. Para este recordatorio diario no se necesita precisión de despertador; Google Play restringe `USE_EXACT_ALARM` a funciones que realmente la requieren. [Alarmas de Android](https://developer.android.com/develop/background-work/services/alarms), [permisos restringidos de Google Play](https://support.google.com/googleplay/android-developer/answer/16558241?hl=en).
- **Apertura desde un aviso:** también se lee el aviso que inició la app desde un proceso cerrado. Su identificador de reflexión se valida y queda pendiente hasta que el bloqueo de privacidad esté abierto y los datos estén disponibles. Una restauración en curso o pendiente de recuperación retrasa esa navegación.
- **Calendario de la reflexión:** se calcula cada fecha civil a las 09:00 de la zona correspondiente, evitando desplazar la hora al pasar por días de 23 o 25 horas. La misma función elige el texto en pantalla y en el aviso. Hay 365 textos: el 29 de febrero repite el del 28; el 1 de marzo y las demás fechas conservan su texto. Los logros mantienen el cómputo previo de periodos transcurridos de 24 horas desde la fecha de inicio y sus identificadores.
- **Actualización al volver a la app:** se comprueban día, zona, permiso, preferencias y fecha de inicio. Una configuración distinta renueva el plan; una petición repetida con la misma configuración no lo duplica. El trabajo espera mientras la privacidad cubre la app o los datos están ocupados/en recuperación. Un fallo no se considera una actualización completada ni inicia un bucle de reintentos.
- **Cambios coherentes:** el servicio serializa programaciones y cancelaciones. Perfil y la actualización de inicio comparten además `HiveRestoreService.runExclusive`: leen las preferencias y programan/cancelan dentro del mismo bloqueo. Así, una lectura antigua no puede volver a activar un aviso ya apagado. Perfil guarda «activado» después de programar correctamente y «desactivado» después de cancelar; impide dobles pulsaciones e invalida decisiones de una generación antigua de datos. La espera de permiso ocurre fuera de ese bloqueo.
- **Errores de guardado y caché:** una escritura de `SharedPreferences` que devuelve `false` o lanza un error no se da por guardada aunque haya cambiado su caché en memoria. Se recargan las preferencias antes de calcular la configuración y antes de programar; Perfil también relee el estado tras un fallo. Así se evita presentar o reutilizar como persistida una activación que no pudo confirmarse.

## Horizonte que se conserva

Cada programación prepara **60 fechas de reflexión**, cada una con el título de su texto correspondiente. Al abrir o retomar la app con una configuración nueva se renueva esa ventana. Si la app permanece sin abrir más allá del horizonte, no hay garantía de avisos de reflexión posteriores. Sigue pendiente decidir si se desea un mecanismo continuo: esta candidata no lo introduce ni cambia los 60 días por otra duración.

No se ha añadido un botón de aviso inmediato ni una función de prueba a los pocos minutos. Las pruebas automáticas de horas, fechas y cambios de horario usan un reloj controlado.

## Qué está verificado y qué falta

Las tandas dirigidas de notificaciones han aprobado **58 pruebas**: 14 del servicio/plataforma simulada, 15 de planificación/calendario y pantalla de reflexión, 10 de actualización al volver, 12 del controlador de preferencias/Perfil y 7 de persistencia con `SharedPreferences` y respuestas de plataforma simuladas. Incluyen permisos denegados y errores, orden de programación/cancelación, limpieza tras fallos parciales, cambios de horario, año bisiesto, conservación de preferencias, retorno desde Ajustes y coherencia de caché ante escrituras fallidas.

La suite completa de la candidata ha terminado con **176/176 pruebas aprobadas**, incluidas esas 58. El registro `build/validation/tests-offline-v21.txt` finaliza con `+176: All tests passed!`. El APK de prueba se ha generado y verificado: `dist/verificacion-android.json` confirma firma, destino API 36, permisos y declaración de reprogramación tras reinicio. La entrega real de avisos sigue pendiente de comprobar en un móvil; véase `VALIDACION-21.md`.

La entrega real en Android no se ha probado en esta sesión. Las pruebas de Flutter verifican cálculos, contratos de canales y comportamiento de widgets; no ejecutan `AlarmManager`, el diálogo de permiso de un teléfono ni los receptores tras un reinicio físico.

Los avisos son **aproximados a partir de las 09:00**, no una promesa de entrega a esa hora exacta. Doze, ahorro de batería y otras restricciones pueden retrasarlos. [Entrega de alarmas inexactas — Android](https://developer.android.com/develop/background-work/services/alarms).

El permiso general puede estar concedido y un canal silenciado por el usuario. La app mantiene los canales existentes y respeta esa configuración; el estado general mostrado en Perfil no acredita que cada canal tenga sonido o visibilidad habilitados. [Control de los canales — Android](https://developer.android.com/develop/ui/compose/notifications/channels).

«Forzar detención» es una acción distinta de dejar la app en segundo plano: Android 15 y posteriores cancelan sus `PendingIntent` al detenerla y requieren que una acción del usuario la saque de ese estado. No se intenta eludirlo. [Estado detenido — Android](https://developer.android.com/about/versions/15/behavior-changes-all#stopped-state).

Si cambia la zona horaria con la app en segundo plano, la adaptación del plan a la nueva hora local se realiza al volver a abrirla; no se ha añadido un receptor específico para ese cambio. La verificación de Google Drive es independiente y no forma parte de estas pruebas de notificaciones.

## Comprobación breve pendiente en un móvil de pruebas

Usar datos ficticios y una instalación de pruebas; no borrar ni reinstalar sobre el inventario real para provocar diálogos.

1. Activar desde Perfil, denegar el permiso y comprobar que el aviso queda apagado. Abrir Ajustes mediante la acción visible, permitirlo y regresar: el estado del sistema se actualiza, y la activación explícita funciona. Repetir apagado/encendido sin duplicados.
2. Dejar un aviso programado para su hora habitual, llevar la app a segundo plano y registrar la recepción real con fecha, hora y captura del título. Admitir el retraso propio del modo inexacto; comprobar por separado con ahorro de batería.
3. Con avisos pendientes, reiniciar el móvil y verificar la siguiente entrega. En una actualización de pruebas firmada con la misma clave, instalada encima sin borrar datos, comprobar también continuidad e inventario intacto.
4. Con el bloqueo de privacidad activado y el proceso de la app cerrado, tocar una reflexión recibida: debe pedir desbloqueo antes de mostrar la pantalla de destino y abrir el texto asociado al aviso.
5. Apagar cada aviso en Perfil; revisar que no reaparece al volver a la app. Revocar el permiso general y silenciar un canal desde Android por separado: respetar ambas decisiones y comprobar la información de Perfil. Si se prueba «Forzar detención», registrar que no se espera actividad normal hasta volver a abrir la app.

Registrar modelo, versión de Android y de la candidata junto a cada resultado. Estos pasos son preparación para revisar una futura publicación; no constituyen una orden de subir o publicar el APK/AAB.
