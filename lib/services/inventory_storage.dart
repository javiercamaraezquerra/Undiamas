import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../models/diary_entry.dart';
import 'safe_hive_open.dart';

/// Opens storage without truncating unreadable files and finishes a legacy
/// migration only after its complete destination is verified and flushed.
class InventoryStorage {
  static Future<({Box<dynamic> settings, Box<DiaryEntry> diary})> open(
    HiveAesCipher cipher, {
    @visibleForTesting Future<void> Function(String step)? beforeStep,
  }) async {
    final settings = await openHiveBoxSafely<dynamic>('udm_secure',
        encryptionCipher: cipher);
    final diary = await openHiveBoxSafely<DiaryEntry>('diary_secure',
        encryptionCipher: cipher);
    final legacySettings = await Hive.boxExists('udm')
        ? await openHiveBoxSafely<dynamic>('udm')
        : null;
    final legacyDiary = await Hive.boxExists('diary')
        ? await openHiveBoxSafely<DiaryEntry>('diary')
        : null;
    final oldSettings = legacySettings?.toMap();
    final oldEntries = legacyDiary?.toMap();

    // Validate both migrations before changing either destination or deleting
    // either source. Partial compatible copies can safely resume by Hive key.
    if (oldSettings != null) {
      _checkCompatible(oldSettings, settings.toMap(), _equal);
    }
    if (oldEntries != null) {
      _checkCompatible(oldEntries, diary.toMap(), _sameEntry);
    }

    if (legacySettings != null && oldSettings != null) {
      await beforeStep?.call('settings.copy');
      await settings.putAll({
        for (final entry in oldSettings.entries)
          if (!settings.containsKey(entry.key)) entry.key: entry.value,
      });
      await beforeStep?.call('settings.flush');
      await settings.flush();
      _verify(oldSettings, settings.toMap(), _equal);
      await beforeStep?.call('settings.deleteSource');
      await legacySettings.deleteFromDisk();
    }
    if (legacyDiary != null && oldEntries != null) {
      await beforeStep?.call('diary.copy');
      await diary.putAll({
        for (final entry in oldEntries.entries)
          if (!diary.containsKey(entry.key))
            entry.key: DiaryEntry(
              text: entry.value.text,
              mood: entry.value.mood,
              createdAt: entry.value.createdAt,
              photoId: entry.value.photoId,
            ),
      });
      await beforeStep?.call('diary.flush');
      await diary.flush();
      _verify(oldEntries, diary.toMap(), _sameEntry);
      await beforeStep?.call('diary.deleteSource');
      await legacyDiary.deleteFromDisk();
    }
    return (settings: settings, diary: diary);
  }

  static void _checkCompatible<K, V>(
      Map<K, V> source, Map<K, V> destination, bool Function(V, V) equal) {
    // An empty legacy box has no data to contribute. Preserve the complete
    // encrypted destination, including any data written in a newer version.
    if (source.isEmpty) return;
    for (final entry in destination.entries) {
      if (!source.containsKey(entry.key) ||
          !equal(source[entry.key] as V, entry.value)) {
        throw StateError('Hay diferencias entre los archivos antiguos y los '
            'cifrados. Se han conservado ambos sin sustituir sus datos.');
      }
    }
  }

  static void _verify<K, V>(
      Map<K, V> source, Map<K, V> destination, bool Function(V, V) equal) {
    if (source.isEmpty) return;
    if (source.length != destination.length ||
        !source.entries.every((entry) =>
            destination.containsKey(entry.key) &&
            equal(entry.value, destination[entry.key] as V))) {
      throw StateError('No se pudo comprobar la migración completa. '
          'El archivo antiguo se ha conservado.');
    }
  }

  static bool _sameEntry(DiaryEntry a, DiaryEntry b) =>
      a.text == b.text &&
      a.mood == b.mood &&
      a.photoId == b.photoId &&
      _equal(a.createdAt, b.createdAt);

  static bool _equal(dynamic a, dynamic b) {
    if (a is DateTime && b is DateTime) {
      // This is the timestamp precision and UTC flag persisted by Hive.
      return a.millisecondsSinceEpoch == b.millisecondsSinceEpoch &&
          a.isUtc == b.isUtc;
    }
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.keys.every((key) => b.containsKey(key) && _equal(a[key], b[key]));
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_equal(a[i], b[i])) return false;
      }
      return true;
    }
    if (a is num || b is num) {
      if (a is int && b is int) return a == b;
      if (a is double && b is double) {
        return a == b || (a.isNaN && b.isNaN);
      }
      return false;
    }
    return a == b;
  }
}
