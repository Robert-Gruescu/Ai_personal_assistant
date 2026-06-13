import 'dart:convert';
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'google_auth_service.dart';
import 'email_service.dart' show EmailData, EmailResult;

/// Serviciu pentru CITIREA și TRIMITEREA emailurilor prin Gmail API,
/// folosind contul Google conectat (autentificare centrală `GoogleAuthService`).
///
/// Înlocuiește nevoia de IMAP (citire) și, când utilizatorul e conectat la Google,
/// și de SMTP (trimitere). Reutilizează modelele `EmailData`/`EmailResult` din
/// `email_service.dart` pentru a fi compatibil cu restul aplicației.
class GmailService {
  static final GmailService _instance = GmailService._internal();
  factory GmailService() => _instance;
  GmailService._internal();

  final GoogleAuthService _auth = GoogleAuthService();

  bool get isSignedIn => _auth.isSignedIn;
  String? get userEmail => _auth.userEmail;

  Future<gmail.GmailApi?> _api() async {
    final client = await _auth.authClient();
    if (client == null) return null;
    return gmail.GmailApi(client);
  }

  // ── CITIRE ──────────────────────────────────────────────────────────────

  /// Cele mai recente `count` emailuri din inbox.
  Future<EmailResult> getRecentEmails({int count = 5}) async {
    return _listAndFetch(query: 'in:inbox', maxResults: count);
  }

  /// Ultimul email primit.
  Future<EmailResult> getLastEmail() async {
    final result = await _listAndFetch(query: 'in:inbox', maxResults: 1);
    if (!result.success) return result;
    final emails = result.emails ?? [];
    if (emails.isEmpty) {
      return EmailResult.error('Nu am găsit niciun email în inbox.');
    }
    return EmailResult.withEmail(emails.first);
  }

  /// Caută emailuri după un termen (subiect, expeditor, conținut).
  Future<EmailResult> searchEmails(String query, {int count = 5}) async {
    if (query.trim().isEmpty) {
      return EmailResult.error('Termenul de căutare lipsește.');
    }
    return _listAndFetch(query: query.trim(), maxResults: count);
  }

  Future<EmailResult> _listAndFetch({
    required String query,
    required int maxResults,
  }) async {
    final api = await _api();
    if (api == null) {
      return EmailResult.error(
        'Contul Google nu este conectat. Conectează-te din Setări.',
      );
    }

    try {
      final list = await api.users.messages.list(
        'me',
        q: query,
        maxResults: maxResults,
      );

      final messages = list.messages ?? [];
      if (messages.isEmpty) {
        return EmailResult.withEmails([]);
      }

      final emails = <EmailData>[];
      for (final msgRef in messages) {
        if (msgRef.id == null) continue;
        final full = await api.users.messages.get(
          'me',
          msgRef.id!,
          format: 'full',
        );
        emails.add(_parseMessage(full));
      }

      return EmailResult.withEmails(emails);
    } catch (e) {
      print('❌ Gmail read error: $e');
      return EmailResult.error('Eroare la citirea emailurilor: $e');
    }
  }

  EmailData _parseMessage(gmail.Message msg) {
    final headers = msg.payload?.headers ?? [];

    String headerValue(String name) {
      for (final h in headers) {
        if ((h.name ?? '').toLowerCase() == name.toLowerCase()) {
          return h.value ?? '';
        }
      }
      return '';
    }

    final from = headerValue('From');
    final subject = headerValue('Subject');
    final to = headerValue('To');
    final dateStr = headerValue('Date');

    DateTime date;
    try {
      date = DateTime.parse(dateStr);
    } catch (_) {
      // Gmail dă și timestamp intern (ms) ca fallback
      final internal = int.tryParse(msg.internalDate ?? '');
      date = internal != null
          ? DateTime.fromMillisecondsSinceEpoch(internal)
          : DateTime.now();
    }

    final body = _extractBody(msg.payload) ?? (msg.snippet ?? '');

    return EmailData(
      from: from,
      subject: subject.isNotEmpty ? subject : '(fără subiect)',
      body: body,
      date: date,
      to: to,
    );
  }

  /// Extrage corpul text dintr-un mesaj Gmail (preferă text/plain, apoi text/html curățat).
  String? _extractBody(gmail.MessagePart? part) {
    if (part == null) return null;

    final mime = part.mimeType ?? '';

    if (mime == 'text/plain') {
      final decoded = _decodeBody(part.body?.data);
      if (decoded != null && decoded.trim().isNotEmpty) return decoded.trim();
    }

    // Caută recursiv în sub-părți (preferă text/plain)
    if (part.parts != null) {
      for (final p in part.parts!) {
        if ((p.mimeType ?? '') == 'text/plain') {
          final decoded = _decodeBody(p.body?.data);
          if (decoded != null && decoded.trim().isNotEmpty) {
            return decoded.trim();
          }
        }
      }
      // fallback: orice sub-parte cu conținut
      for (final p in part.parts!) {
        final nested = _extractBody(p);
        if (nested != null && nested.trim().isNotEmpty) return nested.trim();
      }
    }

    // fallback: html curățat
    if (mime == 'text/html') {
      final decoded = _decodeBody(part.body?.data);
      if (decoded != null) return _stripHtml(decoded);
    }

    return null;
  }

  String? _decodeBody(String? data) {
    if (data == null || data.isEmpty) return null;
    try {
      // Gmail folosește base64 URL-safe, posibil fără padding
      var normalized = data.replaceAll('-', '+').replaceAll('_', '/');
      while (normalized.length % 4 != 0) {
        normalized += '=';
      }
      return utf8.decode(base64.decode(normalized), allowMalformed: true);
    } catch (e) {
      print('⚠️ Gmail body decode error: $e');
      return null;
    }
  }

  String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  // ── TRIMITERE ─────────────────────────────────────────────────────────────

  /// Trimite un email prin Gmail API. `isHtml` controlează tipul de conținut.
  Future<EmailResult> sendEmail({
    required String to,
    required String subject,
    required String body,
    bool isHtml = false,
  }) async {
    final api = await _api();
    if (api == null) {
      return EmailResult.error(
        'Contul Google nu este conectat. Conectează-te din Setări.',
      );
    }

    try {
      final raw = _buildRawMessage(
        from: userEmail ?? 'me',
        to: to,
        subject: subject,
        body: body,
        isHtml: isHtml,
      );

      final message = gmail.Message()..raw = raw;
      await api.users.messages.send(message, 'me');
      print('📧 Gmail: email trimis către $to');
      return EmailResult.success('Email trimis către $to');
    } catch (e) {
      print('❌ Gmail send error: $e');
      return EmailResult.error('Eroare la trimiterea emailului: $e');
    }
  }

  /// Construiește un mesaj RFC 2822 codat base64url (cerut de Gmail API).
  String _buildRawMessage({
    required String from,
    required String to,
    required String subject,
    required String body,
    required bool isHtml,
  }) {
    final contentType = isHtml
        ? 'text/html; charset="UTF-8"'
        : 'text/plain; charset="UTF-8"';

    // Subiect codat MIME (suportă diacritice)
    final encodedSubject =
        '=?UTF-8?B?${base64.encode(utf8.encode(subject))}?=';

    final message = StringBuffer()
      ..writeln('From: ASIS Assistant <$from>')
      ..writeln('To: $to')
      ..writeln('Subject: $encodedSubject')
      ..writeln('MIME-Version: 1.0')
      ..writeln('Content-Type: $contentType')
      ..writeln('Content-Transfer-Encoding: 8bit')
      ..writeln()
      ..write(body);

    return base64Url.encode(utf8.encode(message.toString()));
  }
}
