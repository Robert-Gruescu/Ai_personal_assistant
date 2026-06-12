import 'package:google_sign_in/google_sign_in.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;

/// Rezultatul creării unui eveniment cu link Google Meet real.
class GoogleMeetEvent {
  final String eventId;
  final String? meetLink; // link Meet REAL (hangoutLink) returnat de Google
  final String? htmlLink; // link către eveniment în Google Calendar

  GoogleMeetEvent({required this.eventId, this.meetLink, this.htmlLink});

  bool get hasMeetLink => meetLink != null && meetLink!.isNotEmpty;
}

/// Serviciu pentru autentificare Google și creare de evenimente reale
/// în Google Calendar, cu link Google Meet generat de Google (nu fabricat local).
///
/// Folosește:
///   - google_sign_in            → autentificarea utilizatorului (OAuth)
///   - extension_google_sign_in_as_googleapis_auth → client HTTP autentificat
///   - googleapis (Calendar v3)  → inserarea evenimentului cu conferenceData
///
/// IMPORTANT: pentru a funcționa pe Android trebuie configurat în Google Cloud
/// Console un OAuth Client ID de tip „Android” cu package name
/// `com.example.ai_personal_assistant` și amprenta SHA-1 a cheii de semnare,
/// iar Google Calendar API trebuie activat. Vezi DOCUMENTATIE_APLICATIE.md.
class GoogleCalendarService {
  static final GoogleCalendarService _instance =
      GoogleCalendarService._internal();
  factory GoogleCalendarService() => _instance;
  GoogleCalendarService._internal();

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: <String>[gcal.CalendarApi.calendarEventsScope],
  );

  GoogleSignInAccount? _currentUser;

  bool get isSignedIn => _currentUser != null;
  String? get userEmail => _currentUser?.email;

  /// Încearcă o autentificare silențioasă (fără a deschide fereastra de login)
  /// pe baza unei sesiuni Google existente. Returnează true dacă reușește.
  Future<bool> signInSilently() async {
    try {
      _currentUser = await _googleSignIn.signInSilently();
      if (_currentUser != null) {
        print('✅ Google sign-in silent OK: ${_currentUser!.email}');
      }
      return _currentUser != null;
    } catch (e) {
      print('⚠️ Google signInSilently error: $e');
      return false;
    }
  }

  /// Deschide fereastra de login Google pentru a alege contul.
  Future<bool> signIn() async {
    try {
      _currentUser = await _googleSignIn.signIn();
      if (_currentUser != null) {
        print('✅ Google sign-in OK: ${_currentUser!.email}');
      } else {
        print('⚠️ Google sign-in anulat de utilizator');
      }
      return _currentUser != null;
    } catch (e) {
      print('❌ Google sign-in error: $e');
      return false;
    }
  }

  /// Deconectează contul Google.
  Future<void> signOut() async {
    try {
      await _googleSignIn.disconnect();
    } catch (_) {
      await _googleSignIn.signOut();
    }
    _currentUser = null;
    print('👋 Google sign-out');
  }

  /// Construiește un client Calendar API autentificat. Întoarce null dacă
  /// utilizatorul nu este conectat și nici autentificarea silențioasă nu reușește.
  Future<gcal.CalendarApi?> _calendarApi() async {
    if (_currentUser == null) {
      await signInSilently();
    }
    if (_currentUser == null) return null;

    final client = await _googleSignIn.authenticatedClient();
    if (client == null) {
      print('⚠️ Nu am putut obține clientul autentificat Google');
      return null;
    }
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
