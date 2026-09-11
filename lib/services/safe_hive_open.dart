import 'dart:async';

import 'package:hive/hive.dart';

final _openingBoxes = <String, Future<Box<dynamic>>>{};

/// Opens without Hive's destructive checksum recovery. Hive 2.2.3 reports a
/// failed open twice: once to its caller and once through an internal waiter
/// completer which may have no listener (hive_impl.dart, _openBox). Contain that
/// identical duplicate within the opening operation, while returning its error
/// normally. Other asynchronous errors still reach the caller's error zone.
///
/// Coalesce same-name opens outside the guarded zone: Dart error futures cannot
/// cross different error zones, so directly awaiting Hive's internal open from
/// two guarded zones could otherwise leave one of the callers waiting forever.
Future<Box<T>> openHiveBoxSafely<T>(String name,
    {HiveCipher? encryptionCipher}) {
  final canonicalName = name.toLowerCase();
  final existing = _openingBoxes[canonicalName];
  if (existing != null) return existing.then((box) => box as Box<T>);

  final result = Completer<Box<T>>();
  final callerZone = Zone.current;
  Object? reportedError;
  _openingBoxes[canonicalName] = result.future;

  void reportError(Object error, StackTrace stack) {
    if (!result.isCompleted) {
      reportedError = error;
      result.completeError(error, stack);
    } else if (!identical(error, reportedError)) {
      // Never silence unrelated errors, or errors after a successful open.
      callerZone.handleUncaughtError(error, stack);
    }
  }

  runZonedGuarded(() async {
    try {
      final box = await Hive.openBox<T>(name,
          encryptionCipher: encryptionCipher, crashRecovery: false);
      if (!result.isCompleted) result.complete(box);
    } catch (error, stack) {
      reportError(error, stack);
    } finally {
      _openingBoxes.remove(canonicalName);
    }
  }, reportError);
  return result.future;
}
