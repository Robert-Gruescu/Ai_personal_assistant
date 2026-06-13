import 'package:googleapis/calendar/v3.dart' as gcal;
import 'google_auth_service.dart';

/// Rezultatul creării unui eveniment cu link Google Meet real.
class GoogleMeetEvent {
  final String eventId;
  final String? meetLink; // link Meet REAL (hangoutLink) returnat de Google
  final String? htmlLink; // link către eveniment în Google Calendar

  GoogleMeetEvent({required this.eventId, this.meetLink, this.htmlLink});

  bool get hasMeetLink => meetLink != null && meetLink!.isNotEmpty;
}

/// Serviciu pentru creare de evenimente reale în Google Calendar, cu link
/// Google Meet generat de Google (nu fabricat local).
///
/// Autentificarea NU mai e gestionată aici — se folosește serviciul central
/// `GoogleAuthService` (o singură conectare pentru Calendar + Gmail). Acest
/// serviciu doar cere clientul autentificat și apelează Calendar API.
class GoogleCalendarService {
  static final GoogleCalendarService _instance =
      GoogleCalendarService._internal();
  factory GoogleCalendarService() => _instance;
  GoogleCalendarService._internal();

  final GoogleAuthService _auth = GoogleAuthService();

  bool get isSignedIn => _auth.isSignedIn;
  String? get userEmail => _auth.userEmail;

  /// Construiește un client Calendar API autentificat. Null dacă neconectat.
  Future<gcal.CalendarApi?> _calendarApi() async {
    final client = await _auth.authClient();
    if (client == null) return null;
    return gcal.CalendarApi(client);
  }

  /// Creează un eveniment REAL în Google Calendar, cu link Google Meet generat
  /// de Google. Trimite automat invitația oficială Google către participant
  /// (sendUpdates: 'all'). Returnează null dacă nu este conectat sau apare o eroare.
  Future<GoogleMeetEvent?> createEventWithMeet({
    required String title,
    String? description,
    required DateTime startTime,
    required DateTime endTime,
    String? attendeeEmail,
    int reminderMinutesBefore = 30,
  }) async {
    final api = await _calendarApi();
    if (api == null) return null;

    try {
      final event = gcal.Event(
        summary: title,
        description: description,
        start: gcal.EventDateTime(
          dateTime: startTime.toUtc(),
          timeZone: 'Europe/Bucharest',
        ),
        end: gcal.EventDateTime(
          dateTime: endTime.toUtc(),
          timeZone: 'Europe/Bucharest',
        ),
        attendees: (attendeeEmail != null && attendeeEmail.isNotEmpty)
            ? [gcal.EventAttendee(email: attendeeEmail)]
            : null,
        reminders: gcal.EventReminders(
          useDefault: false,
          overrides: [
            gcal.EventReminder(
              method: 'popup',
              minutes: reminderMinutesBefore,
            ),
            gcal.EventReminder(method: 'email', minutes: 60),
          ],
        ),
        // Cererea care îi spune Google să genereze un link Google Meet real.
        conferenceData: gcal.ConferenceData(
          createRequest: gcal.CreateConferenceRequest(
            requestId: DateTime.now().millisecondsSinceEpoch.toString(),
            conferenceSolutionKey: gcal.ConferenceSolutionKey(
              type: 'hangoutsMeet',
            ),
          ),
        ),
      );

      final created = await api.events.insert(
        event,
        'primary',
        // OBLIGATORIU pentru ca Google să creeze efectiv camera Meet.
        conferenceDataVersion: 1,
        // Trimite invitația oficială Google către participant.
        sendUpdates: 'all',
      );

      final meetLink =
          created.hangoutLink ?? _extractMeetFromEntryPoints(created);

      print('✅ Eveniment Google Calendar creat. Meet: $meetLink');
      return GoogleMeetEvent(
        eventId: created.id ?? '',
        meetLink: meetLink,
        htmlLink: created.htmlLink,
      );
    } catch (e) {
      print('❌ Eroare la crearea evenimentului Google Calendar: $e');
      return null;
    }
  }

  /// Caută link-ul Meet în entryPoints dacă hangoutLink nu e populat încă.
  String? _extractMeetFromEntryPoints(gcal.Event event) {
    final entryPoints = event.conferenceData?.entryPoints;
    if (entryPoints == null) return null;
    for (final ep in entryPoints) {
      if (ep.entryPointType == 'video' &&
          ep.uri != null &&
          ep.uri!.isNotEmpty) {
        return ep.uri;
      }
    }
    return null;
  }
}
