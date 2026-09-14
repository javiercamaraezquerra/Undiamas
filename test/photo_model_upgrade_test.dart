import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:un_dia_mas/models/diary_entry.dart';

class _PublishedEntryAdapter extends TypeAdapter<DiaryEntry> {
  @override
  int get typeId => 1;
  @override
  DiaryEntry read(BinaryReader reader) => throw UnimplementedError();
  @override
  void write(BinaryWriter writer, DiaryEntry obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.createdAt)
      ..writeByte(1)
      ..write(obj.mood)
      ..writeByte(2)
      ..write(obj.text);
  }
}

void main() {
  test(
      'published encrypted entries survive adding nullable photo field and reopening',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('udm_photo_upgrade_');
    final key = List<int>.generate(32, (i) => i + 1);
    Hive.init(directory.path);
    Hive.registerAdapter(_PublishedEntryAdapter());
    try {
      final original = DiaryEntry(
          createdAt: DateTime.utc(2026, 9, 11, 12),
          mood: 2,
          text: 'Mi entrada anterior, con acentos y 🙂');
      var box = await Hive.openBox<DiaryEntry>('diary_secure',
          encryptionCipher: HiveAesCipher(key), crashRecovery: false);
      await box.put(47, original);
      await box.flush();
      await box.close();
      // Keep Hive's built-in DateTime adapters while switching the app schema.
      Hive.registerAdapter(DiaryEntryAdapter(), override: true);
      box = await Hive.openBox<DiaryEntry>('diary_secure',
          encryptionCipher: HiveAesCipher(key), crashRecovery: false);
      expect(box.get(47)!.photoId, isNull);
      expect(box.get(47)!.text, original.text);
      expect(box.get(47)!.mood, original.mood);
      expect(box.get(47)!.createdAt, original.createdAt);
      final photoId = List.filled(64, 'a').join();
      await box.put(
          'photo-draft-0123456789abcdef',
          DiaryEntry(
              createdAt: DateTime(2026, 9, 14),
              mood: 3,
              text: '',
              photoId: photoId));
      await box.flush();
      await box.close();
      box = await Hive.openBox<DiaryEntry>('diary_secure',
          encryptionCipher: HiveAesCipher(key), crashRecovery: false);
      expect(box.length, 2);
      expect(box.get(47)!.text, original.text);
      expect(box.get(47)!.photoId, isNull);
      expect(box.get('photo-draft-0123456789abcdef')!.photoId, photoId);
      expect(box.get('photo-draft-0123456789abcdef')!.text, isEmpty);
    } finally {
      await Hive.close();
      final root = await Directory.systemTemp.resolveSymbolicLinks();
      final actual = await directory.resolveSymbolicLinks();
      if (!actual
              .toLowerCase()
              .startsWith('$root${Platform.pathSeparator}'.toLowerCase()) ||
          !directory.uri.pathSegments
              .where((part) => part.isNotEmpty)
              .last
              .startsWith('udm_photo_upgrade_')) {
        throw StateError('Unexpected temporary fixture directory');
      }
      await directory.delete(recursive: true);
    }
  });
}
