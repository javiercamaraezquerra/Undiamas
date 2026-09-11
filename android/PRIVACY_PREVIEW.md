# Prueba Android de privacidad

La variante `preview` genera una aplicación independiente:

- Identificador: `com.celsoriaapps.undiamas.privacidad`.
- Etiqueta: `Un día más · Privacidad` en todos los idiomas.
- Firma de depuración exclusivamente para esta prueba local, incluso al optimizar con `--release`.
- No sustituye la instalación `com.celsoriaapps.undiamas` ni comparte sus datos.
- No debe publicarse en Google Play.

Compilación, desde la raíz del proyecto y con Flutter 3.32.8:

```powershell
$env:UDM_PREVIEW_KEYSTORE = 'C:\Users\Javi\.android\debug.keystore'
flutter build apk --flavor preview --release --no-pub --dart-define=UDM_PREVIEW=true
```

Se exige la clave de pruebas existente para mantener la firma de v20 y permitir
actualizarla conservando sus datos. La sesión actual compila mediante el script
offline y los directorios aislados descritos en `docs/PRIVACIDAD.md`.

La variante `production` conserva el identificador y los recursos de nombre originales. Solo permite el tipo `release`; se detiene antes de ejecutar tareas si falta una configuración de firma completa o el almacén indicado. Nunca usa la firma de depuración como alternativa. No se han añadido claves a esta copia.

Configuración: compile/target SDK 36, mínimo SDK 24, JDK 17, AGP 8.10.1, Gradle 8.11.1 y NDK 28.1.13356709. La selección de dependencias Dart corresponde a `pubspec.lock`; este cambio Android no actualiza el resto de bibliotecas.

## Contrato del canal nativo

Canal `undiamas/privacy`; argumentos booleanos directos, sin mapa:

| Método | Efecto | Retorno |
| --- | --- | --- |
| `setLocked(bool)` | Refleja la cobertura del bloqueo Flutter; mientras esté activo, Atrás envía la actividad al fondo sin navegar dentro de Flutter. No autentica ni persiste datos. | `null` al terminar |

Un argumento de otro tipo devuelve `PlatformException` con código `invalid_argument`.

Flutter conserva la única preferencia `privacyAppLockEnabled` mediante la API legacy `SharedPreferences`. Android lee `FlutterSharedPreferences` / `flutter.privacyAppLockEnabled` antes de crear el primer frame; si la lectura falla, arranca protegido y bloqueado. Esta correspondencia se comprobó en el código instalado de `shared_preferences_android 2.4.7`, `LegacySharedPreferencesPlugin.java`.

La revisión 21 elimina `FLAG_SECURE` y el método `setProtected`: las capturas,
grabaciones y miniaturas de Recientes se gestionan normalmente. Al salir de una
sesión autenticada se conserva su última pantalla para la miniatura, sin aceptar
interacciones. Al volver, la cubierta Flutter protege el navegador completo hasta
desbloquear. Una sesión ya bloqueada sigue mostrando su pantalla de bloqueo.
Android no presenta otra pantalla de bloqueo.

En Android 13 o posterior se registra un callback de Atrás únicamente mientras está bloqueado. En versiones anteriores se intercepta `onBackPressed`. El callback moderno se retira al desbloquear y al destruir la actividad.

## Fuentes oficiales

- [Integración Android de local_auth 2.3.0](https://pub.dev/packages/local_auth/versions/2.3.0): `FlutterFragmentActivity`, permiso `USE_BIOMETRIC` y temas AppCompat.
- [Compatibilidad de AGP 8.10](https://developer.android.com/build/releases/agp-8-10-0-release-notes): SDK 36, Gradle 8.11.1 y JDK 17.
- [Variantes de compilación Android](https://developer.android.com/build/build-variants): identificadores, recursos y firma por variante.
- [Protección de actividades sensibles](https://developer.android.com/security/fraud-prevention/activities): comportamiento y limitaciones de `FLAG_SECURE`.
- [Callbacks de Atrás](https://developer.android.com/guide/navigation/custom-back/predictive-back-gesture): habilitación según el estado de la interfaz.

La revisión de XML o una compilación no prueba por sí sola la biometría, el contenido de Recientes ni todos los dispositivos. La prueba física debe comprobar arranque bloqueado, rechazo/cancelación, desbloqueo, cambio de aplicación, Atrás desde rutas secundarias y conservación del inventario.
