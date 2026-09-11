import 'package:hive/hive.dart';

// Frozen storage contract from UnDiaMas 1.0.1+15, commit
// 40b344efcddc57888cbdc5d48986b208e1ce4d4a. Only Dart class names are changed
// to let the old writer coexist with the current reader in one test process.
// Original diary_entry.g.dart SHA256:
// AE92782BC7785A9F2EFAFBFEACC8C417BFB25B6099EA7EEC12030CD056BAC435
// Original post.g.dart SHA256:
// E17242237949404CE55FF6C0BFA1BCFEAEAD3CF4499972BC62768F5463732DA5
// Do not update these adapters to follow production changes: that would make
// the upgrade test stop checking compatibility with the old on-disk format.

class Production15DiaryEntry extends HiveObject {
  Production15DiaryEntry({
    required this.createdAt,
    required this.mood,
    required this.text,
  });

  final DateTime createdAt;
  final int mood;
  final String text;
}

class Production15DiaryEntryAdapter
    extends TypeAdapter<Production15DiaryEntry> {
  @override
  final int typeId = 1;

  @override
  Production15DiaryEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Production15DiaryEntry(
      createdAt: fields[0] as DateTime,
      mood: fields[1] as int,
      text: fields[2] as String,
    );
  }

  @override
  void write(BinaryWriter writer, Production15DiaryEntry obj) {
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

class Production15Post extends HiveObject {
  Production15Post({
    required this.id,
    required this.text,
    required this.createdAt,
    this.likes = 0,
  });

  final String id;
  final String text;
  final DateTime createdAt;
  int likes;
}

class Production15PostAdapter extends TypeAdapter<Production15Post> {
  @override
  final int typeId = 2;

  @override
  Production15Post read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Production15Post(
      id: fields[0] as String,
      text: fields[1] as String,
      createdAt: fields[2] as DateTime,
      likes: fields[3] as int,
    );
  }

  @override
  void write(BinaryWriter writer, Production15Post obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.text)
      ..writeByte(2)
      ..write(obj.createdAt)
      ..writeByte(3)
      ..write(obj.likes);
  }
}

// Exact data shape emitted by DriveBackupService.exportHive in version 15.
// It deliberately does not export Hive keys or SharedPreferences.
Map<String, dynamic> exportProduction15Backup(
        Box<dynamic> udm, Box<Production15DiaryEntry> diary) =>
    {
      'udm': udm.toMap(),
      'diary': diary.values
          .map((e) => {
                'text': e.text,
                'mood': e.mood,
                'createdAt': e.createdAt.toIso8601String(),
              })
          .toList(),
    };
