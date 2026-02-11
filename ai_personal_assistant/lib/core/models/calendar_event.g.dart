// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'calendar_event.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CalendarEventAdapter extends TypeAdapter<CalendarEvent> {
  @override
  final int typeId = 4;

  @override
  CalendarEvent read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CalendarEvent(
      id: fields[0] as String,
      googleEventId: fields[1] as String?,
      title: fields[2] as String,
      description: fields[3] as String?,
      startTime: fields[4] as DateTime,
      endTime: fields[5] as DateTime,
      meetLink: fields[6] as String?,
      attendeeEmail: fields[7] as String?,
      attendeeName: fields[8] as String?,
      reminderSent: fields[9] as bool? ?? false,
      reminderTime: fields[10] as DateTime?,
      status: fields[11] as String? ?? 'scheduled',
      createdAt: fields[12] as DateTime?,
      updatedAt: fields[13] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, CalendarEvent obj) {
    writer
      ..writeByte(14)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.googleEventId)
      ..writeByte(2)
      ..write(obj.title)
      ..writeByte(3)
      ..write(obj.description)
      ..writeByte(4)
      ..write(obj.startTime)
      ..writeByte(5)
      ..write(obj.endTime)
      ..writeByte(6)
      ..write(obj.meetLink)
      ..writeByte(7)
      ..write(obj.attendeeEmail)
      ..writeByte(8)
      ..write(obj.attendeeName)
      ..writeByte(9)
      ..write(obj.reminderSent)
      ..writeByte(10)
      ..write(obj.reminderTime)
      ..writeByte(11)
      ..write(obj.status)
      ..writeByte(12)
      ..write(obj.createdAt)
      ..writeByte(13)
      ..write(obj.updatedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CalendarEventAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
