import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:local_auth/error_codes.dart' as auth_errors;
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class AppLockPreferences {
  Future<bool?> readEnabled();
  Future<bool> writeEnabled(bool enabled);
}

abstract class AppLockAuthenticator {
  Future<bool> isDeviceSupported();
  Future<bool> authenticate({required String reason});
}

/// Device privacy only. This controller never opens Hive or modifies backups.
/// Lifecycle events cover content but never launch authentication themselves.
class AppLockController extends ChangeNotifier {
  static const preferenceKey = 'privacyAppLockEnabled';
  static final instance = AppLockController();

  final AppLockPreferences _preferences;
  final AppLockAuthenticator _authenticator;
  AppLifecycleState _lifecycle;
  Future<void>? _initializing;
  bool _initialized = false;
  bool _enabled = false;
  bool _locked = true;
  bool _obscured;
  bool _authenticating = false;
  bool _changingSetting = false;
  bool _nativeAuthenticationActive = false;
  bool _disposed = false;
  int _backgroundEpoch = 0;
  String? _message;

  AppLockController({
    AppLockPreferences? preferences,
    AppLockAuthenticator? authenticator,
    AppLifecycleState initialLifecycle = AppLifecycleState.resumed,
  })  : _preferences = preferences ?? _SharedAppLockPreferences(),
        _authenticator = authenticator ?? _DeviceAppLockAuthenticator(),
        _lifecycle = initialLifecycle,
        _obscured = initialLifecycle != AppLifecycleState.resumed;

  bool get initialized => _initialized;
  bool get enabled => _enabled;
  bool get locked => _locked;
  bool get obscured => _obscured;
  bool get authenticating => _authenticating;
  bool get changingSetting => _changingSetting;
  String? get message => _message;
  bool get covered => !initialized || (enabled && (locked || obscured));

  Future<void> initialize() {
    if (_disposed || _initialized) return Future<void>.value();
    return _initializing ??= _readPreference().whenComplete(() {
      _initializing = null;
    });
  }

  Future<void> _readPreference() async {
    try {
      final value = await _preferences.readEnabled();
      if (_disposed) return;
      _enabled = value ?? false;
      _locked = _enabled;
      _initialized = true;
      _message = null;
    } catch (_) {
      if (_disposed) return;
      // An unreadable setting is not evidence that protection was disabled.
      _initialized = false;
      _locked = true;
      _message = 'No se pudo leer la protección de privacidad. '
          'Vuelve a intentarlo; tus datos no se han borrado.';
    }
    _notify();
  }

  Future<bool> setEnabled(bool value) async {
    if (_disposed || !_initialized || _authenticating || _changingSetting) {
      return false;
    }
    if (value == _enabled) return true;
    if (_lifecycle != AppLifecycleState.resumed) return false;
    final previous = _enabled;
    _changingSetting = true;
    _authenticating = true;
    _message = null;
    _notify();
    try {
      final authenticated = await _requestAuthentication(value
          ? 'Confirma el bloqueo de privacidad de Un día más'
          : 'Confirma que quieres desactivar el bloqueo de Un día más');
      if (_disposed) return false;
      if (!authenticated) {
        _authenticationFailed();
        return false;
      }
      _authenticating = false;
      final authenticatedEpoch = _backgroundEpoch;
      try {
        if (!await _preferences.writeEnabled(value)) {
          throw StateError('The privacy preference was not committed.');
        }
      } catch (_) {
        // SharedPreferences may update its memory cache before a failed native
        // commit. Try to restore the previous value; never display success.
        try {
          await _preferences.writeEnabled(previous);
        } catch (_) {
          // The current session remains protected if it was protected before.
        }
        if (_disposed) return false;
        _enabled = previous;
        _locked = previous;
        _message = 'No se pudo guardar el cambio de privacidad. '
            '${previous ? 'El bloqueo sigue activado.' : 'El bloqueo no se ha activado.'} '
            'Vuelve a intentarlo.';
        return false;
      }
      if (_disposed) return false;
      _enabled = value;
      // Leaving AFTER the native challenge finished requires a fresh challenge.
      // Leaving DURING a sticky PIN dialog belongs to that same challenge.
      _locked = value && authenticatedEpoch != _backgroundEpoch;
      _obscured = _lifecycle != AppLifecycleState.resumed;
      _message = null;
      return true;
    } catch (error) {
      if (!_disposed) _authenticationFailed(error);
      return false;
    } finally {
      _nativeAuthenticationActive = false;
      _authenticating = false;
      _changingSetting = false;
      _notify();
    }
  }

  Future<void> unlock() async {
    if (_disposed ||
        !_initialized ||
        !_enabled ||
        !_locked ||
        _authenticating ||
        _changingSetting ||
        _lifecycle != AppLifecycleState.resumed) {
      return;
    }
    _authenticating = true;
    _message = null;
    _notify();
    try {
      final authenticated = await _requestAuthentication(
          'Desbloquea tu espacio personal de Un día más');
      if (_disposed) return;
      if (authenticated) {
        _locked = false;
        _obscured = _lifecycle != AppLifecycleState.resumed;
        _message = null;
      } else {
        _authenticationFailed();
      }
    } catch (error) {
      if (!_disposed) _authenticationFailed(error);
    } finally {
      _nativeAuthenticationActive = false;
      _authenticating = false;
      _notify();
    }
  }

  Future<bool> _requestAuthentication(String reason) async {
    if (!await _authenticator.isDeviceSupported()) {
      throw PlatformException(code: auth_errors.passcodeNotSet);
    }
    if (_disposed || _lifecycle != AppLifecycleState.resumed) return false;
    _nativeAuthenticationActive = true;
    try {
      return await _authenticator.authenticate(reason: reason);
    } finally {
      _nativeAuthenticationActive = false;
    }
  }

  void handleLifecycle(AppLifecycleState state) {
    if (_disposed || state == _lifecycle) return;
    final wasInBackground = _lifecycle == AppLifecycleState.paused ||
        _lifecycle == AppLifecycleState.hidden;
    final entersBackground = !wasInBackground &&
        (state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden);
    _lifecycle = state;
    _obscured = state != AppLifecycleState.resumed;
    // Flutter emits paused -> hidden -> inactive -> resumed on the return
    // journey too. That hidden event must not revoke a completed native PIN.
    if ((entersBackground || state == AppLifecycleState.detached) &&
        !_nativeAuthenticationActive) {
      _backgroundEpoch++;
      if (_enabled) _locked = true;
    }
    _notify();
  }

  void _authenticationFailed([Object? error]) {
    if (_enabled) _locked = true;
    if (error is PlatformException) {
      switch (error.code) {
        case auth_errors.passcodeNotSet:
        case auth_errors.notEnrolled:
          _message = 'Configura primero un PIN, patrón o contraseña de bloqueo '
              'en los ajustes del teléfono y vuelve a intentarlo.';
          return;
        case auth_errors.lockedOut:
        case auth_errors.permanentlyLockedOut:
          _message = 'El teléfono ha limitado los intentos. Desbloquéalo con '
              'su PIN, patrón o contraseña y vuelve a intentarlo.';
          return;
        case auth_errors.notAvailable:
        case auth_errors.otherOperatingSystem:
          _message = 'El teléfono no puede comprobar tu identidad ahora. '
              'Revisa su bloqueo de pantalla y vuelve a intentarlo.';
          return;
      }
    }
    _message = error == null
        ? 'No se ha confirmado tu identidad. Puedes volver a intentarlo.'
        : 'No se pudo comprobar tu identidad. Vuelve a intentarlo con el '
            'método de bloqueo de tu teléfono.';
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class _SharedAppLockPreferences implements AppLockPreferences {
  @override
  Future<bool?> readEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    final value = preferences.get(AppLockController.preferenceKey);
    if (value != null && value is! bool) {
      throw const FormatException('Invalid privacy preference.');
    }
    return value as bool?;
  }

  @override
  Future<bool> writeEnabled(bool enabled) async =>
      (await SharedPreferences.getInstance())
          .setBool(AppLockController.preferenceKey, enabled);
}

class _DeviceAppLockAuthenticator implements AppLockAuthenticator {
  final _auth = LocalAuthentication();

  @override
  Future<bool> isDeviceSupported() => _auth.isDeviceSupported();

  @override
  Future<bool> authenticate({required String reason}) => _auth.authenticate(
        localizedReason: reason,
        authMessages: const [
          AndroidAuthMessages(
            signInTitle: 'Protege tu espacio personal',
            cancelButton: 'Cancelar',
            biometricHint: 'Confirma tu identidad',
            biometricNotRecognized: 'No reconocido. Vuelve a intentarlo.',
            biometricSuccess: 'Identidad confirmada',
            biometricRequiredTitle: 'Configura el bloqueo del teléfono',
            deviceCredentialsRequiredTitle: 'Configura el bloqueo del teléfono',
            deviceCredentialsSetupDescription:
                'Añade un PIN, patrón o contraseña en los ajustes del teléfono.',
            goToSettingsButton: 'Abrir ajustes',
            goToSettingsDescription:
                'Configura un método de desbloqueo en los ajustes del teléfono.',
          ),
        ],
        options: const AuthenticationOptions(
          biometricOnly: false,
          useErrorDialogs: false,
          stickyAuth: true,
        ),
      );
}
