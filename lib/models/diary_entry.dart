import 'package:hive/hive.dart';

part 'diary_entry.g.dart';

@HiveType(typeId: 1)
class DiaryEntry extends HiveObject {
  @HiveField(0)
  final DateTime createdAt;

  @HiveField(1)
  final int mood; // 0‑4 índice de emoji

  @HiveField(2)
  final String text;

  /// SHA-256 of the normalized photo in private encrypted storage.
  /// Field numbers 0–2 remain unchanged so existing inventories still open.
  @HiveField(3)
  final String? photoId;

  DiaryEntry({
    required this.createdAt,
    required this.mood,
    required this.text,
    this.photoId,
  });
}
