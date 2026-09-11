# Prueba local: privacidad y bloqueo

Base: `1.0.1+15`, commit `40b344efcddc57888cbdc5d48986b208e1ce4d4a`.
Esta copia independiente se identifica como `1.0.2+21`. No recupera los cambios
descartados de las copias 16–19. La carpeta original `UnDiaMas` se conserva.

## Bloqueo de la aplicación

En Perfil, inmediatamente debajo de «Copias automáticas en Drive», se añade
«Privacidad y bloqueo de la app», con el mismo formato de fila e interruptor.

Al activarlo se presenta una explicación y después la comprobación nativa del
teléfono. No se crea un PIN propio. Android decide qué métodos tiene disponibles:
huella, rostro compatible y credencial del dispositivo (PIN, patrón o contraseña).
La app recibe el resultado de la verificación, no esas credenciales.

- La preferencia empieza desactivada.
- Activar y desactivar exigen una verificación satisfactoria.
- Cancelar o fallar no abre una sesión protegida ni muestra un cambio como exitoso.
- Se exige desbloqueo al arrancar y al volver del segundo plano.
- Los cambios de estado de la propia pantalla del PIN no provocan otro reto.
- La cubierta está por encima de todo el navegador, incluidas rutas y diálogos.
- Ocultar la sesión mantiene sus widgets: no desmonta un formulario abierto.
- Se permiten capturas y grabaciones. No se aplica protección especial a
  Recientes: Android puede mostrar la última pantalla que estaba desbloqueada.
  Al volver, la app exige autenticación antes de aceptar interacción. Una sesión
  que ya estaba bloqueada no descubre una pantalla anterior al salir.
- Desactivado, se utiliza la entrada y salida normales de la aplicación.

La única preferencia nueva es `privacyAppLockEnabled`. Se conservan los nombres
de las cajas Hive existentes, sus adaptadores y la clave de cifrado. La revisión
21 añade una caja cifrada de recuperación durante la restauración; los cambios
autorizados de Inventario y Drive se explican en `AJUSTE-21.md`. Las reflexiones,
las herramientas, el diseño del sol y las montañas y las ubicaciones de anuncios
se conservan.

La programación nativa de avisos que ya existe sigue vigente. Los diálogos de
inicio (permisos y ayuda MIUI) y su secuencia de programación esperan al primer
desbloqueo. Si llega una respuesta de notificación mientras está cubierto el
navegador, se conserva el destino para abrirlo después de verificar la identidad.

## APK independiente para probar

- Paquete: `com.celsoriaapps.undiamas.privacidad`.
- Nombre en el móvil: **Un día más · Privacidad**.
- Firma de pruebas, distinta de la distribución de Google Play.
- Datos propios: no sustituye la app publicada ni contiene automáticamente su
  Inventario. No hay que desinstalar la aplicación de Google Play.
- Anuncios de prueba cuando se compila con `UDM_PREVIEW=true`, en los mismos sitios.
- Drive puede rechazar el acceso de este paquete/firma de pruebas al no tener
  registrada esa combinación en OAuth. No se han cambiado los clientes de Google.
- No se ha subido ningún APK ni versión a Google Play o GitHub.

El APK es para evaluar este cambio antes de decidir mantenerlo, pulirlo o quitarlo.

## Compilar y verificar

Flutter 3.32.8, JDK 17, Android SDK 36. El proyecto original tenía una configuración
de firma que intentaba leer un almacén ausente y un lockfile desactualizado
respecto a sus dependencias declaradas. Esta copia resuelve las dependencias y
separa explícitamente la variante de prueba de la de producción. No existe una
alternativa automática que firme producción con la clave de pruebas.

```powershell
flutter pub get
flutter test --no-pub
flutter analyze --no-pub
$env:UDM_PREVIEW_KEYSTORE = 'C:\Users\Javi\.android\debug.keystore'
flutter build apk --flavor preview --release --no-pub --dart-define=UDM_PREVIEW=true
```

La firma de la prueba 21 exige `UDM_PREVIEW_KEYSTORE` apuntando a la clave de la
prueba anterior: no se genera una nueva. En esta sesión se utiliza el script
`../undiamas-runtime/offline-app.ps1`, con Flutter, Pub, Gradle y configuración de
escritorio aislados dentro del workspace autorizado. Ese script usa
`pub get --offline --enforce-lockfile` y Gradle `--offline`. No se modifica el modo
de desarrollador de Windows.
El detalle Android y el contrato del canal se describen en
`android/PRIVACY_PREVIEW.md`.

## Límites de las comprobaciones

Las pruebas Flutter simulan las respuestas del sistema de autenticación. Prueban
la lógica y los widgets de la app, pero no son una lectura física de una huella.
Este PC no tiene aceleración disponible para el AVD Android 36, y el intento de
arranque por software no produjo un dispositivo operativo. No había móviles
conectados. No se presentan estas pruebas como una ejecución real en Android.

Si no se puede leer la preferencia, la app queda cubierta y permite reintentar.
Si falla escribirla, se intenta restaurar el valor anterior y no se muestra éxito.
Un fallo simultáneo de escritura y restauración no permite certificar qué valor
quedó en disco, aunque una sesión previamente protegida permanece cubierta.

Recorrido pendiente en un móvil: activar, hacer una captura, abrir Recientes,
volver y entrar con éxito, cancelar,
comprobar el PIN alternativo, volver a una entrada sin guardar y desactivar.
Repetir tras cerrar completamente la app. La credencial válida
debe permitir entrar; un rechazo o una cancelación debe dejarla bloqueada.
