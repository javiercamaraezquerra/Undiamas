import 'package:shared_preferences/shared_preferences.dart';

/// The legacy plugin updates its memory cache before the platform confirms the
/// write. Discard that optimistic value after a failed or ambiguous response.
/// A failed reload is propagated; callers must not use the unverified cache.
Future<bool> persistNotificationPreference(
    SharedPreferences preferences, String key, bool value) async {
  Object? writeError;
  StackTrace? writeStack;
  try {
    if (await preferences.setBool(key, value)) return true;
  } catch (error, stack) {
    writeError = error;
    writeStack = stack;
  }
  await preferences.reload();
  if (writeError != null) {
    Error.throwWithStackTrace(writeError, writeStack!);
  }
  return false;
}
