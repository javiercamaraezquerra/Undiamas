import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local evidence of an acknowledged upload, never part of a Drive archive.
/// Only hashes and a timestamp are retained; no entry, photo or account name.
class DriveBackupStatus {
  const DriveBackupStatus({
    this.accountHash,
    this.confirmedAt,
    this.contentHash,
    this.lastAttemptFailed = false,
  });

  final String? accountHash;
  final DateTime? confirmedAt;
  final String? contentHash;
  final bool lastAttemptFailed;

  bool differsFrom(String currentHash) =>
      contentHash != null && contentHash != currentHash;
}

/// Hash canonical JSON so restoring equivalent content with different Hive
/// keys or map insertion order does not create a false pending-change warning.
/// Photo IDs are SHA-256 hashes of the immutable JPEG bytes already validated
/// by InventoryPhotoStore and InventoryBackupArchive.
String backupContentFingerprint(Map<String, dynamic> data) {
  Object? ordered(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: ordered(value[key])};
    }
    if (value is List) return value.map(ordered).toList();
    return value;
  }

  return sha256.convert(utf8.encode(jsonEncode(ordered(data)))).toString();
}

class DriveBackupStatusStore extends ChangeNotifier {
  DriveBackupStatusStore({
    Future<SharedPreferences> Function()? preferences,
    DateTime Function()? now,
  })  : _preferences = preferences ?? SharedPreferences.getInstance,
        _now = now ?? DateTime.now;

  static final instance = DriveBackupStatusStore();
  static const preferenceKey = 'drive_backup_status_v1';
  final Future<SharedPreferences> Function() _preferences;
  final DateTime Function() _now;
  Future<void> _tail = Future<void>.value();
  String? _selectedAccountHash;
  bool _uploading = false;
  bool get uploading => _uploading;

  void setUploading(bool value) {
    if (_uploading == value) return;
    _uploading = value;
    notifyListeners();
  }

  static String _accountHash(String id) =>
      sha256.convert(utf8.encode('udm-drive-account:$id')).toString();

  static DriveBackupStatus _decode(SharedPreferences prefs) {
    final raw = prefs.getString(preferenceKey);
    if (raw == null) return const DriveBackupStatus();
    final value = jsonDecode(raw) as Map<String, dynamic>;
    final date = value['confirmedAt'] as String?;
    final hash = value['contentHash'] as String?;
    return DriveBackupStatus(
      accountHash: value['accountHash'] as String?,
      confirmedAt: date == null ? null : DateTime.parse(date),
      contentHash: hash,
      lastAttemptFailed: value['lastAttemptFailed'] == true,
    );
  }

  Future<DriveBackupStatus> read() async {
    await _tail;
    final stored = _decode(await _preferences());
    // If persisting a just-selected account failed, never show the old account's
    // timestamp as evidence for the new one during this session.
    if (_selectedAccountHash != null &&
        stored.accountHash != _selectedAccountHash) {
      return DriveBackupStatus(accountHash: _selectedAccountHash);
    }
    return stored;
  }

  Future<void> _change(DriveBackupStatus? Function(DriveBackupStatus) update) {
    final operation = _tail.then((_) async {
      final prefs = await _preferences();
      DriveBackupStatus previous;
      try {
        previous = _decode(prefs);
      } catch (_) {
        // A malformed optional status must not affect the inventory or Drive.
        previous = const DriveBackupStatus();
      }
      final next = update(previous);
      final stored = next == null
          ? await prefs.remove(preferenceKey)
          : await prefs.setString(
              preferenceKey,
              jsonEncode({
                'accountHash': next.accountHash,
                'confirmedAt': next.confirmedAt?.toUtc().toIso8601String(),
                'contentHash': next.contentHash,
                'lastAttemptFailed': next.lastAttemptFailed,
              }));
      if (!stored) throw StateError('Backup status could not be stored.');
    });
    // Metadata is best effort. A confirmed cloud upload must remain successful
    // if this local preference fails. Keep the chain usable after a failure.
    _tail = operation.then((_) {}, onError: (Object _, StackTrace __) {});
    return _tail.whenComplete(notifyListeners);
  }

  Future<void> selectAccount(String accountId) {
    final hash = _accountHash(accountId);
    _selectedAccountHash = hash;
    return _change((previous) {
      return previous.accountHash == hash
          ? previous
          : DriveBackupStatus(accountHash: hash);
    });
  }

  Future<void> recordSuccess(String accountId, String contentHash) {
    final completedAt = _now().toUtc();
    return _change((previous) {
      final hash = _accountHash(accountId);
      if (_selectedAccountHash != hash) return previous;
      return DriveBackupStatus(
        accountHash: hash,
        confirmedAt: completedAt,
        contentHash: contentHash,
      );
    });
  }

  Future<void> recordFailure({String? accountId}) => _change((previous) {
        if (accountId != null &&
            _selectedAccountHash != _accountHash(accountId)) {
          return previous;
        }
        if (_selectedAccountHash != null &&
            previous.accountHash != _selectedAccountHash) {
          return DriveBackupStatus(
              accountHash: _selectedAccountHash, lastAttemptFailed: true);
        }
        return DriveBackupStatus(
          accountHash: previous.accountHash,
          confirmedAt: previous.confirmedAt,
          contentHash: previous.contentHash,
          lastAttemptFailed: true,
        );
      });

  Future<void> clear() {
    _selectedAccountHash = null;
    return _change((_) => null);
  }
}
