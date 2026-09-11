import 'dart:async';

/// Refreshes a finite notification plan when foreground configuration changes.
/// The owner requests work on resume and notifies state changes after privacy
/// or data operations unblock it. No timers, background workers or UI hooks.
class ForegroundNotificationRefresh {
  ForegroundNotificationRefresh({
    required Future<String> Function() configurationKey,
    required Future<void> Function() refresh,
    required bool Function() canRun,
    void Function(Object, StackTrace)? onError,
  })  : _configurationKey = configurationKey,
        _refresh = refresh,
        _canRun = canRun,
        _onError = onError;

  final Future<String> Function() _configurationKey;
  final Future<void> Function() _refresh;
  final bool Function() _canRun;
  final void Function(Object, StackTrace)? _onError;
  bool _pending = false;
  bool _running = false;
  bool _disposed = false;
  String? _lastSuccessfulKey;

  void requestRefresh() {
    if (_disposed) return;
    _pending = true;
    _tryRun();
  }

  void onStateChanged() {
    if (!_disposed && _pending) _tryRun();
  }

  void _tryRun() {
    if (_disposed || _running || !_pending || !_canRun()) return;
    _pending = false;
    _running = true;
    unawaited(_run());
  }

  Future<void> _run() async {
    var deferred = false;
    try {
      final key = await _configurationKey();
      if (_disposed) return;
      // A dialog or a restore can start while reading preferences/timezone.
      if (!_canRun()) {
        _pending = true;
        deferred = true;
        return;
      }
      if (key == _lastSuccessfulKey) return;
      await _refresh();
      if (!_disposed) _lastSuccessfulKey = key;
    } catch (error, stack) {
      // A failed replacement may already have cancelled the preceding plan.
      // Returning to an older configuration must not reuse its old cache key.
      _lastSuccessfulKey = null;
      // A listener from the failed operation must not create an auth/retry
      // loop. A later explicit request can retry because its key was not saved.
      if (!_disposed) _onError?.call(error, stack);
    } finally {
      _running = false;
      // Requests arriving during a running refresh collapse into one key
      // check. Deferred work waits for a genuine unblocking state notification.
      if (!_disposed && _pending && !deferred) _tryRun();
    }
  }

  /// Stops new work; an already-started platform call cannot be undone here.
  void dispose() {
    _disposed = true;
    _pending = false;
  }
}
