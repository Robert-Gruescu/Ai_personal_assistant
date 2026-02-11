// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_action.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AgentActionAdapter extends TypeAdapter<AgentAction> {
  @override
  final int typeId = 5;

  @override
  AgentAction read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AgentAction(
      id: fields[0] as String,
      actionType: fields[1] as String,
      target: fields[2] as String?,
      content: fields[3] as String?,
      status: fields[4] as String? ?? 'pending',
      createdAt: fields[5] as DateTime?,
      executedAt: fields[6] as DateTime?,
      errorMessage: fields[7] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, AgentAction obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.actionType)
      ..writeByte(2)
      ..write(obj.target)
      ..writeByte(3)
      ..write(obj.content)
      ..writeByte(4)
      ..write(obj.status)
      ..writeByte(5)
      ..write(obj.createdAt)
      ..writeByte(6)
      ..write(obj.executedAt)
      ..writeByte(7)
      ..write(obj.errorMessage);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentActionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
