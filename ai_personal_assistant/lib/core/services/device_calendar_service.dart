import 'dart:io';
import 'package:flutter/services.dart';

/// Device Calendar Service - Adds events directly to the phone's native calendar
/// Uses native Android ContentResolver via MethodChannel for silent insertion
class DeviceCalendarService {
  static final DeviceCalendarService _instance =
      DeviceCalendarService._internal();
  factory DeviceCalendarService() => _instance;
  DeviceCalendarService._internal();

  static const MethodChannel _channel = MethodChannel(
    'com.asis.calendar/native',
  );
  bool _isInitialized = false;
  bool _hasPermission = false;

  bool get isInitialized => _isInitialized;
  bool get hasPermission => _hasPermission;

  /// Initialize and check/request permissions
  Future<bool> initialize() async {
    if (!Platform.isAndroid) {
      print('⚠️ Calendar service only works on Android');
      return false;
    }

    try {
      // Check if we have permission
      _hasPermission =
          await _channel.invokeMethod<bool>('hasCalendarPermission') ?? false;

      if (!_hasPermission) {
        // Request permission
        await _channel.invokeMethod('requestCalendarPermission');
        // Check again after request
        await Future.delayed(const Duration(milliseconds: 500));
        _hasPermission =
            await _channel.invokeMethod<bool>('hasCalendarPermission') ?? false;
      }

      _isInitialized = true;
      print('📅 Calendar service initialized. Permission: $_hasPermission');
      return _hasPermission;
    } catch (e) {
      print('❌ Calendar service init error: $e');
      _isInitialized = true;
      return false;
    }
  }

  /// Add a meeting event directly to the device calendar (no user interaction needed)
  Future<String?> addMeetingToCalendar({
    required String title,
    required DateTime startTime,
    required DateTime endTime,
    String? description,
    String? meetLink,
    String? attendeeEmail,
    String? attendeeName,
    int reminderMinutesBefore = 30,
  }) async {
    if (!Platform.isAndroid) {
      print('⚠️ Calendar only works on Android');
      return null;
    }

    if (!_isInitialized) {
      await initialize();
    }

    // Re-check permission
    try {
      _hasPermission =
          await _channel.invokeMethod<bool>('hasCalendarPermission') ?? false;
      if (!_hasPermission) {
        print('⚠️ No calendar permission - requesting...');
        await _channel.invokeMethod('requestCalendarPermission');
        await Future.delayed(const Duration(seconds: 1));
        _hasPermission =
            await _channel.invokeMethod<bool>('hasCalendarPermission') ?? false;
        if (!_hasPermission) {
          print('❌ Calendar permission denied');
          return null;
        }
      }
    } catch (e) {
      print('⚠️ Permission check error: $e');
    }

    try {
      // Build full description with Meet link
      final fullDescription = StringBuffer();
      if (description != null && description.isNotEmpty) {
        fullDescription.writeln(description);
        fullDescription.writeln();
      }
      if (meetLink != null && meetLink.isNotEmpty) {
        fullDescription.writeln('🔗 Link Google Meet:');
        fullDescription.writeln(meetLink);
        fullDescription.writeln();
      }
      if (attendeeName != null || attendeeEmail != null) {
        fullDescription.writeln(
          '👤 Participant: ${attendeeName ?? attendeeEmail}',
        );
      }

      final result = await _channel.invokeMethod<String>('addEventToCalendar', {
        'title': '📅 $title',
        'description': fullDescription.toString(),
        'startTime': startTime.millisecondsSinceEpoch,
        'endTime': endTime.millisecondsSinceEpoch,
        'location': meetLink ?? '',
        'reminderMinutes': reminderMinutesBefore,
      });

      if (result != null) {
        print('✅ Eveniment adăugat automat în calendar: $result');
        return result;
      } else {
        print('❌ Nu s-a putut adăuga evenimentul');
        return null;
      }
    } catch (e) {
      print('❌ Error adding to calendar: $e');
      return null;
    }
  }
}
