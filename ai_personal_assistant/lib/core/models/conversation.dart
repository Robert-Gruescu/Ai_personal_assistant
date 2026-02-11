import 'package:hive/hive.dart';

part 'conversation.g.dart';

@HiveType(typeId: 0)
class Conversation extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String title;

  @HiveField(2)
  DateTime createdAt;

  @HiveField(3)
  DateTime updatedAt;

  @HiveField(4)
  List<Message> messages;

  Conversation({
    required this.id,
    required this.title,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<Message>? messages,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now(),
       messages = messages ?? [];

  void addMessage(Message message) {
    messages.add(message);
    updatedAt = DateTime.now();
  }
}

@HiveType(typeId: 1)
class Message extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String role; // 'user' or 'assistant'

  @HiveField(2)
  String content;

  @HiveField(3)
  String? audioPath;

  @HiveField(4)
  DateTime createdAt;

  Message({
    required this.id,
    required this.role,
    required this.content,
    this.audioPath,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';
}
