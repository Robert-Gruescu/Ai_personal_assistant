import 'package:google_sign_in/google_sign_in.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:googleapis_auth/googleapis_auth.dart' as gauth;

/// Serviciu CENTRAL de autentificare Google (OAuth).
///
/// O SINGURĂ conectare Google deservește toate funcțiile care au nevoie de contul
/// utilizatorului: Google Calendar (întâlniri + Meet), Gmail (citire + trimitere)
/// și, în viitor, orice alt serviciu Google. Celelalte servicii
/// (`GoogleCalendarService`, `GmailService`) NU se mai autentifică separat —
/// cer de aici clientul HTTP autentificat (`authClient()`).
///
/// IMPORTANT (configurare Google Cloud Console — o singură dată):
///   - OAuth Client ID tip Android: package `com.example.ai_personal_assistant`
///     + SHA-1 al cheii de semnare.
///   - API-uri activate: Google Calendar API ȘI Gmail API.
///   - Scope-uri adăugate la „Data Access”: calendar.events, gmail.readonly, gmail.send.
///   - Scope-ul gmail.readonly este „restricted” → în modul Testing apare un
///     avertisment „aplicație neverificată” (normal, se apasă Continue).
class GoogleAuthService {
  static final GoogleAuthService _instance = GoogleAuthService._internal();
  factory GoogleAuthService() => _instance;
  GoogleAuthService._internal();

  /// Toate permisiunile cerute la o singură conectare.
  static const List<String> scopes = <String>[
    gcal.CalendarApi.calendarEventsScope, // creare/editare evenimente + Meet
    gmail.GmailApi.gmailReadonlyScope, // citire emailuri
    gmail.GmailApi.gmailSendScope, // trimitere emailuri
  ];

  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: scopes);

  GoogleSignInAccount? _currentUser;

  bool get isSignedIn => _currentUser != null;
  String? get userEmail => _currentUser?.email;
  String? get displayName => _currentUser?.displayName;

  /// Reconectare silențioasă (fără fereastră de login) pe baza unei sesiuni existente.
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

  /// Deschide fereastra de login Google.
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

  Future<void> signOut() async {
    try {
      await _googleSignIn.disconnect();
    } catch (_) {
      await _googleSignIn.signOut();
    }
    _currentUser = null;
    print('👋 Google sign-out');
  }

  /// Client HTTP autentificat pentru apeluri către API-urile Google.
  /// Încearcă reconectarea silențioasă dacă nu există sesiune. Null dacă eșuează.
  Future<gauth.AuthClient?> authClient() async {
    if (_currentUser == null) {
      await signInSilently();
    }
    if (_currentUser == null) return null;

    final client = await _googleSignIn.authenticatedClient();
    if (client == null) {
      print('⚠️ Nu am putut obține clientul autentificat Google');
    }
    return client;
  }
}
