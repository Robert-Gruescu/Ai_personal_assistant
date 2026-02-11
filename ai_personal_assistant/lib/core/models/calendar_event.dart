import 'package:hive/hive.dart';

part 'calendar_event.g.dart';

@HiveType(typeId: 4)
class CalendarEvent extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String? googleEventId;

  @HiveField(2)
  String title;

  @HiveField(3)
  String? description;

  @HiveField(4)
  DateTime startTime;

  @HiveField(5)
  DateTime endTime;

  @HiveField(6)
  String? meetLink;

  @HiveField(7)
  String? attendeeEmail;

  @HiveField(8)
  String? attendeeName;

  @HiveField(9)
  bool reminderSent;

  @HiveField(10)
  DateTime? reminderTime;

  @HiveField(11)
  String status; // 'scheduled', 'completed', 'cancelled'

  @HiveField(12)
  DateTime createdAt;

  @HiveField(13)
  DateTime updatedAt;

  CalendarEvent({
    required this.id,
    this.googleEventId,
    required this.title,
    this.description,
    required this.startTime,
    required this.endTime,
    this.meetLink,
    this.attendeeEmail,
    this.attendeeName,
    this.reminderSent = false,
    this.reminderTime,
    this.status = 'scheduled',
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  bool get isScheduled => status == 'scheduled';
  bool get isCompleted => status == 'completed';
  bool get isCancelled => status == 'cancelled';

  bool get hasMeetLink => meetLink != null && meetLink!.isNotEmpty;

  Duration get duration => endTime.difference(startTime);

  CalendarEvent copyWith({
    String? id,
    String? googleEventId,
    String? title,
    String? description,
    DateTime? startTime,
    DateTime? endTime,
    String? meetLink,
    String? attendeeEmail,
    String? attendeeName,
    bool? reminderSent,
    DateTime? reminderTime,
    String? status,
  }) {
    return CalendarEvent(
      id: id ?? this.id,
      googleEventId: googleEventId ?? this.googleEventId,
      title: title ?? this.title,
      description: description ?? this.description,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      meetLink: meetLink ?? this.meetLink,
      attendeeEmail: attendeeEmail ?? this.attendeeEmail,
      attendeeName: attendeeName ?? this.attendeeName,
      reminderSent: reminderSent ?? this.reminderSent,
      reminderTime: reminderTime ?? this.reminderTime,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
