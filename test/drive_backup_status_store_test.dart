import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:un_dia_mas/services/drive_backup_status_store.dart';

Map<String, dynamic> _copy({String text = 'Hoy he dado un paso.'}) => {
      'version': 2,
      'udm': {'startDate': '2026-01-03T10:30:00.000', 'substance': 'Tabaco'},
      'diary': [
        {
          'text': text,
          'mood': 3,
          'createdAt': '2026-10-01T12:00:00.000',
          'photoId': List.filled(64, 'a').join(),
        },
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DriveBackupStatusStore store;
  var now = DateTime.utc(2026, 10, 1, 10, 15);

  setUp(() {
    SharedPreferences.setMockInitialValues({'autoBackup': true});
    now = DateTime.utc(2026, 10, 1, 10, 15);
    store = DriveBackupStatusStore(now: () => now);
  });
  tearDown(() => store.dispose());

  test('missing history does not invent a time or imply an empty Drive',
      () async {
    final status = await store.read();
    expect(status.confirmedAt, isNull);
    expect(status.contentHash, isNull);
    expect(status.lastAttemptFailed, isFalse);
  });

  test('date is durable, and a failed later attempt preserves the receipt',
      () async {
    await store.selectAccount('account-a');
    final hash = backupContentFingerprint(_copy());
    await store.recordSuccess('account-a', hash);
    final completed = now;
    now = now.add(const Duration(hours: 1));
    await store.recordFailure(accountId: 'account-a');
    final restarted = DriveBackupStatusStore();
    final status = await restarted.read();
    restarted.dispose();
    expect(status.confirmedAt, completed);
    expect(status.contentHash, hash);
    expect(status.lastAttemptFailed, isTrue);
    expect(status.differsFrom(backupContentFingerprint(_copy(text: 'Nuevo'))),
        isTrue);
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(DriveBackupStatusStore.preferenceKey)!;
    expect(raw, isNot(contains('account-a')));
    expect(raw, isNot(contains('Hoy he dado')));
    expect(prefs.getBool('autoBackup'), isTrue);
  });

  test('account change clears old evidence and ignores a late old receipt',
      () async {
    await store.selectAccount('account-a');
    await store.recordSuccess('account-a', backupContentFingerprint(_copy()));
    await store.selectAccount('account-b');
    await store.recordSuccess('account-a', backupContentFingerprint(_copy()));
    await store.recordFailure(accountId: 'account-a');
    expect((await store.read()).confirmedAt, isNull);
    expect((await store.read()).lastAttemptFailed, isFalse);
    await store.recordSuccess('account-b', backupContentFingerprint(_copy()));
    expect((await store.read()).confirmedAt, now);
  });

  test('failure with no successful upload has no date; later success clears it',
      () async {
    await store.recordFailure();
    expect((await store.read()).confirmedAt, isNull);
    await store.selectAccount('account-a');
    await store.recordFailure(accountId: 'account-a');
    await store.recordSuccess('account-a', backupContentFingerprint(_copy()));
    expect((await store.read()).lastAttemptFailed, isFalse);
  });

  test('optional metadata storage errors never fail the completed upload',
      () async {
    final unavailable = DriveBackupStatusStore(
        preferences: () async => throw StateError('Fixture storage failure'));
    await expectLater(unavailable.selectAccount('account-a'), completes);
    await expectLater(
        unavailable.recordSuccess('account-a', 'hash'), completes);
    await expectLater(unavailable.recordFailure(), completes);
    await expectLater(unavailable.clear(), completes);
    unavailable.dispose();
  });

  test('deleting/disconnecting clears receipt without altering other settings',
      () async {
    await store.selectAccount('account-a');
    await store.recordSuccess('account-a', backupContentFingerprint(_copy()));
    await store.clear();
    expect((await store.read()).confirmedAt, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(DriveBackupStatusStore.preferenceKey), isFalse);
    expect(prefs.getBool('autoBackup'), isTrue);
  });

  test('same content survives reordered map keys and keeps duplicate entries',
      () {
    final original = _copy();
    final alternate = {
      'diary': original['diary'],
      'udm': {
        'substance': 'Tabaco',
        'startDate': '2026-01-03T10:30:00.000',
      },
      'version': 2,
    };
    final hash = backupContentFingerprint(original);
    expect(backupContentFingerprint(alternate), hash);
    final duplicated = jsonDecode(jsonEncode(original)) as Map<String, dynamic>;
    (duplicated['diary'] as List).add((duplicated['diary'] as List).first);
    expect(backupContentFingerprint(duplicated), isNot(hash));
  });

  for (final field in ['text', 'mood', 'createdAt', 'photoId', 'startDate']) {
    test('$field changes are detected without modifying the source', () {
      final original = _copy();
      final preserved = jsonEncode(original);
      final modified = jsonDecode(preserved) as Map<String, dynamic>;
      if (field == 'startDate') {
        (modified['udm'] as Map)[field] = '2026-10-01T13:00:00.000';
      } else {
        (modified['diary'] as List).first[field] = switch (field) {
          'mood' => 1,
          'photoId' => null,
          'createdAt' => '2026-10-02T12:00:00.000',
          _ => 'Otra entrada',
        };
      }
      expect(backupContentFingerprint(modified),
          isNot(backupContentFingerprint(original)));
      expect(jsonEncode(original), preserved);
    });
  }
}
