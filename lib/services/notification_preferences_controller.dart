import 'package:flutter/foundation.dart';

import 'achievement_service.dart';

enum NotificationPreferenceResult { applied, denied, failed, cancelled, busy }

/// Coordinates one explicit preference change. System permission is displayed
/// separately from the stored choice; refreshing it never changes preferences.
class NotificationsController extends ChangeNotifier {
  NotificationsController({
    Future<bool> Function()? readPermission,
    Future<bool> Function()? requestPermission,
    Future<void> Function()? openSettings,
  })  : _readPermission =
            readPermission ?? AchievementService.notificationsEnabled,
        _requestPermission = requestPermission ??
            AchievementService.requestNotificationPermission,
        _openSettings =
            openSettings ?? AchievementService.openNotificationSettings;

  final Future<bool> Function() _readPermission;
  final Future<bool> Function() _requestPermission;
  final Future<void> Function() _openSettings;
  bool _busy = false;
  bool _disposed = false;
  bool? _systemEnabled;
  int _statusRevision = 0;

  bool get busy => _busy;
  bool? get systemEnabled => _systemEnabled;

  Future<void> refresh() async {
    if (_disposed) return;
    final revision = ++_statusRevision;
    bool? enabled;
    try {
      enabled = await _readPermission();
    } catch (_) {
      enabled = null;
    }
    if (_disposed || revision != _statusRevision) return;
    _systemEnabled = enabled;
    notifyListeners();
  }

  Future<void> openSettings() => _openSettings();

  void _permissionRead(bool enabled) {
    if (_disposed) return;
    ++_statusRevision;
    _systemEnabled = enabled;
    notifyListeners();
  }

  Future<NotificationPreferenceResult> change({
    required bool enable,
    required bool Function() isCurrent,
    required Future<void> Function() schedule,
    required Future<void> Function() cancel,
    required Future<bool> Function(bool value) persist,
    required Future<void> Function(Future<void> Function() action) runExclusive,
  }) async {
    if (_disposed || !isCurrent()) {
      return NotificationPreferenceResult.cancelled;
    }
    if (_busy) return NotificationPreferenceResult.busy;
    _busy = true;
    ++_statusRevision;
    notifyListeners();
    try {
      if (enable) {
        var allowed = await _readPermission();
        if (_disposed || !isCurrent()) {
          return NotificationPreferenceResult.cancelled;
        }
        _permissionRead(allowed);
        if (!allowed) {
          await _requestPermission();
          if (_disposed || !isCurrent()) {
            return NotificationPreferenceResult.cancelled;
          }
          allowed = await _readPermission();
          if (_disposed || !isCurrent()) {
            return NotificationPreferenceResult.cancelled;
          }
          _permissionRead(allowed);
        }
        if (!allowed) return NotificationPreferenceResult.denied;
      }
      if (_disposed || !isCurrent()) {
        return NotificationPreferenceResult.cancelled;
      }
      var applied = false;
      await runExclusive(() async {
        if (_disposed || !isCurrent()) return;
        if (enable) {
          try {
            await schedule();
            if (!await persist(true)) throw StateError('Preference not saved');
          } catch (_) {
            // Scheduling can fail after adding some alarms. Do not leave those
            // enabled when the preference change could not be completed.
            try {
              await cancel();
            } catch (_) {
              // The UI still reports failure; never claim that it was enabled.
            }
            rethrow;
          }
        } else {
          await cancel();
          if (!await persist(false)) throw StateError('Preference not saved');
        }
        // Once scheduled/cancelled inside the data lock, finish persisting the
        // accepted action even if its screen was removed during the async IO.
        applied = true;
      });
      return applied
          ? NotificationPreferenceResult.applied
          : NotificationPreferenceResult.cancelled;
    } catch (_) {
      return NotificationPreferenceResult.failed;
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_statusRevision;
    super.dispose();
  }
}
