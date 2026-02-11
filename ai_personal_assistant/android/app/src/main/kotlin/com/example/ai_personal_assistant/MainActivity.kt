package com.example.ai_personal_assistant

import android.content.ContentValues
import android.content.pm.PackageManager
import android.provider.CalendarContract
import android.Manifest
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.asis.calendar/native"
    private val PERMISSION_REQUEST_CODE = 100

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "addEventToCalendar" -> {
                    val title = call.argument<String>("title") ?: ""
                    val description = call.argument<String>("description") ?: ""
                    val startTime = call.argument<Long>("startTime") ?: 0L
                    val endTime = call.argument<Long>("endTime") ?: 0L
                    val location = call.argument<String>("location") ?: ""
                    val reminderMinutes = call.argument<Int>("reminderMinutes") ?: 30
                    
                    val eventId = addEventToCalendar(title, description, startTime, endTime, location, reminderMinutes)
                    if (eventId != null) {
                        result.success(eventId.toString())
                    } else {
                        result.error("CALENDAR_ERROR", "Nu s-a putut adăuga evenimentul în calendar", null)
                    }
                }
                "hasCalendarPermission" -> {
                    val hasPermission = ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.WRITE_CALENDAR
                    ) == PackageManager.PERMISSION_GRANTED
                    result.success(hasPermission)
                }
                "requestCalendarPermission" -> {
                    ActivityCompat.requestPermissions(
                        this,
                        arrayOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR),
                        PERMISSION_REQUEST_CODE
                    )
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
    
    private fun addEventToCalendar(
        title: String,
        description: String,
        startTime: Long,
        endTime: Long,
        location: String,
        reminderMinutes: Int
    ): Long? {
        // Check permission first
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.WRITE_CALENDAR) 
            != PackageManager.PERMISSION_GRANTED) {
            println("⚠️ No calendar permission")
            return null
        }
        
        try {
            // Get the primary calendar ID
            val calendarId = getPrimaryCalendarId()
            if (calendarId == null) {
                println("⚠️ No calendar found")
                return null
            }
            
            // Create event values
            val values = ContentValues().apply {
                put(CalendarContract.Events.DTSTART, startTime)
                put(CalendarContract.Events.DTEND, endTime)
                put(CalendarContract.Events.TITLE, title)
                put(CalendarContract.Events.DESCRIPTION, description)
                put(CalendarContract.Events.EVENT_LOCATION, location)
                put(CalendarContract.Events.CALENDAR_ID, calendarId)
                put(CalendarContract.Events.EVENT_TIMEZONE, TimeZone.getDefault().id)
                put(CalendarContract.Events.HAS_ALARM, 1)
            }
            
            // Insert the event
            val uri = contentResolver.insert(CalendarContract.Events.CONTENT_URI, values)
            val eventId = uri?.lastPathSegment?.toLongOrNull()
            
            // Add reminder
            if (eventId != null && reminderMinutes > 0) {
                val reminderValues = ContentValues().apply {
                    put(CalendarContract.Reminders.EVENT_ID, eventId)
                    put(CalendarContract.Reminders.MINUTES, reminderMinutes)
                    put(CalendarContract.Reminders.METHOD, CalendarContract.Reminders.METHOD_ALERT)
                }
                contentResolver.insert(CalendarContract.Reminders.CONTENT_URI, reminderValues)
                println("✅ Reminder added: $reminderMinutes minutes before")
            }
            
            println("✅ Event added to calendar with ID: $eventId")
            return eventId
        } catch (e: Exception) {
            println("❌ Error adding event: ${e.message}")
            e.printStackTrace()
            return null
        }
    }
    
    private fun getPrimaryCalendarId(): Long? {
        val projection = arrayOf(
            CalendarContract.Calendars._ID,
            CalendarContract.Calendars.CALENDAR_DISPLAY_NAME,
            CalendarContract.Calendars.IS_PRIMARY
        )
        
        val cursor = contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            projection,
            null,
            null,
            null
        )
        
        cursor?.use {
            while (it.moveToNext()) {
                val idIndex = it.getColumnIndex(CalendarContract.Calendars._ID)
                val isPrimaryIndex = it.getColumnIndex(CalendarContract.Calendars.IS_PRIMARY)
                
                if (idIndex >= 0) {
                    val id = it.getLong(idIndex)
                    val isPrimary = if (isPrimaryIndex >= 0) it.getInt(isPrimaryIndex) == 1 else false
                    
                    // Return primary calendar or first one found
                    if (isPrimary || cursor.isFirst) {
                        return id
                    }
                }
            }
            // Return first calendar if no primary found
            if (it.moveToFirst()) {
                val idIndex = it.getColumnIndex(CalendarContract.Calendars._ID)
                if (idIndex >= 0) {
                    return it.getLong(idIndex)
                }
            }
        }
        return null
    }
}
