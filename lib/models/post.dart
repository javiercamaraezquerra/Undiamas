import 'package:hive/hive.dart';

part 'post.g.dart';

@HiveType(typeId: 2)
class Post extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String text;

  @HiveField(2)
  final DateTime createdAt;

  @HiveField(3)
  int likes;

  Post({
    required this.id,
    required this.text,
    required this.createdAt,
    this.likes = 0,
  });
}
