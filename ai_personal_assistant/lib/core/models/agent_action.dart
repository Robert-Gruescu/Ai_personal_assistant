import 'package:hive/hive.dart';

part 'agent_action.g.dart';

@HiveType(typeId: 5)
class AgentAction extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String actionType; // 'email', 'sms', 'reminder', 'calendar', etc.

  @HiveField(2)
  String? target; // email address, phone number, etc.

  @HiveField(3)
  String? content;

  @HiveField(4)
  String status; // 'pending', 'completed', 'failed'

  @HiveField(5)
  DateTime createdAt;

  @HiveField(6)
  DateTime? executedAt;

  @HiveField(7)
  String? errorMessage;

  AgentAction({
    required this.id,
    required this.actionType,
    this.target,
    this.content,
    this.status = 'pending',
    DateTime? createdAt,
    this.executedAt,
    this.errorMessage,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isPending => status == 'pending';
  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';

  void markCompleted() {
    status = 'completed';
    executedAt = DateTime.now();
  }

  void markFailed(String error) {
    status = 'failed';
    executedAt = DateTime.now();
    errorMessage = error;
  }
}
