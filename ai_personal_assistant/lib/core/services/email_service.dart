import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

/// Email message data
class EmailData {
  final String from;
  final String subject;
  final String body;
  final DateTime date;
  final String? to;

  EmailData({
    required this.from,
    required this.subject,
    required this.body,
    required this.date,
    this.to,
  });

  Map<String, dynamic> toJson() => {
    'from': from,
    'subject': subject,
    'body': body,
    'date': date.toIso8601String(),
    'to': to,
  };
}

/// Email Service Result
class EmailResult {
  final bool success;
  final String? message;
  final String? error;
  final List<EmailData>? emails;
  final EmailData? email;

  EmailResult({
    required this.success,
    this.message,
    this.error,
    this.emails,
    this.email,
  });

  factory EmailResult.success(String message) =>
      EmailResult(success: true, message: message);

  factory EmailResult.error(String errorMessage) =>
      EmailResult(success: false, error: errorMessage);

  factory EmailResult.withEmails(List<EmailData> emails) =>
      EmailResult(success: true, emails: emails);

  factory EmailResult.withEmail(EmailData email) =>
      EmailResult(success: true, email: email);
}

/// Email Service for sending and reading emails
class EmailService {
  static final EmailService _instance = EmailService._internal();
  factory EmailService() => _instance;
  EmailService._internal();

  String? _smtpHost;
  int _smtpPort = 587;
  String? _smtpUser;
  String? _smtpPassword;
  String? _imapHost;
  int _imapPort = 993;

  bool _isConfigured = false;

  /// Initialize the email service with SMTP/IMAP credentials
  void initialize({
    required String smtpHost,
    required int smtpPort,
    required String smtpUser,
    required String smtpPassword,
    String? imapHost,
    int? imapPort,
  }) {
    _smtpHost = smtpHost;
    _smtpPort = smtpPort;
    _smtpUser = smtpUser;
    _smtpPassword = smtpPassword;
    _imapHost = imapHost ?? 'imap.gmail.com';
    _imapPort = imapPort ?? 993;

    _isConfigured =
        _smtpUser != null &&
        _smtpUser!.isNotEmpty &&
        _smtpPassword != null &&
        _smtpPassword!.isNotEmpty;

    if (_isConfigured) {
      print('✅ Email service initialized');
    } else {
      print('⚠️ Email service not configured (missing credentials)');
    }
  }

  bool get isConfigured => _isConfigured;
  String? get userEmail => _smtpUser;

  /// Send an email
  Future<EmailResult> sendEmail({
    required String to,
    required String subject,
    required String body,
    bool isHtml = false,
  }) async {
    if (!_isConfigured) {
      return EmailResult.error(
        'Serviciul de email nu este configurat. Verifică setările SMTP.',
      );
    }

    if (!validateEmail(to)) {
      return EmailResult.error('Adresa de email "$to" nu este validă.');
    }

    try {
      // Create SMTP server configuration
      SmtpServer smtpServer;

      if (_smtpHost == 'smtp.gmail.com') {
        smtpServer = gmail(_smtpUser!, _smtpPassword!);
      } else {
        smtpServer = SmtpServer(
          _smtpHost!,
          port: _smtpPort,
          username: _smtpUser,
          password: _smtpPassword,
          ssl: _smtpPort == 465,
          allowInsecure: false,
        );
      }

      // Create the message
      final message = Message()
        ..from = Address(_smtpUser!, 'ASIS Assistant')
        ..recipients.add(to)
        ..subject = subject
        ..text = isHtml ? null : body
        ..html = isHtml ? body : null;

      // Send the email
      final sendReport = await send(message, smtpServer);
      print('📧 Email sent: ${sendReport.toString()}');

      return EmailResult.success('Email trimis către $to');
    } on MailerException catch (e) {
      print('❌ Email send error: ${e.message}');
      for (var p in e.problems) {
        print('Problem: ${p.code}: ${p.msg}');
      }
      return EmailResult.error('Eroare la trimiterea emailului: ${e.message}');
    } catch (e) {
      print('❌ Email send error: $e');
      return EmailResult.error('Eroare la trimiterea emailului: $e');
    }
  }

  /// Validate email address format
  bool validateEmail(String email) {
    final pattern = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    return pattern.hasMatch(email);
  }

  /// Get recent emails (placeholder - IMAP requires additional package)
  /// For full IMAP support, you would need to use a package like 'enough_mail'
  Future<EmailResult> getRecentEmails({int count = 10}) async {
    if (!_isConfigured) {
      return EmailResult.error(
        'Serviciul de email nu este configurat. Verifică setările.',
      );
    }

    // Note: Full IMAP support requires additional implementation
    // For now, return a placeholder message
    return EmailResult.error('Citirea emailurilor nu este încă implementată.');
  }

  /// Search emails (placeholder)
  Future<EmailResult> searchEmails(String query) async {
    if (!_isConfigured) {
      return EmailResult.error('Serviciul de email nu este configurat.');
    }

    return EmailResult.error('Căutarea emailurilor nu este încă implementată.');
  }

  /// Get the last email (placeholder)
  Future<EmailResult> getLastEmail() async {
    if (!_isConfigured) {
      return EmailResult.error('Serviciul de email nu este configurat.');
    }

    return EmailResult.error('Citirea emailurilor nu este încă implementată.');
  }

  /// Send meeting invitation email
  Future<EmailResult> sendMeetingInvitation({
    required String to,
    required String attendeeName,
    required String meetingTitle,
    required DateTime startTime,
    required String meetLink,
    String? description,
  }) async {
    final formattedDate =
        '${startTime.day}/${startTime.month}/${startTime.year}';
    final formattedTime =
        '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}';

    final htmlBody =
        '''
<!DOCTYPE html>
<html>
<head>
  <style>
    body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; }
    .header { background: #4285f4; color: white; padding: 20px; text-align: center; border-radius: 8px 8px 0 0; }
    .content { background: #f9f9f9; padding: 20px; border: 1px solid #ddd; }
    .meeting-details { background: white; padding: 15px; border-radius: 8px; margin: 15px 0; }
    .meet-button { display: inline-block; background: #1a73e8; color: white; padding: 12px 24px; text-decoration: none; border-radius: 4px; margin-top: 15px; }
    .footer { text-align: center; color: #666; font-size: 12px; margin-top: 20px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>📅 Invitație la Întâlnire</h1>
    </div>
    <div class="content">
      <p>Bună $attendeeName,</p>
      <p>Ai fost invitat la o întâlnire:</p>
      
      <div class="meeting-details">
        <h2>$meetingTitle</h2>
        <p><strong>📆 Data:</strong> $formattedDate</p>
        <p><strong>🕐 Ora:</strong> $formattedTime</p>
        ${description != null ? '<p><strong>📝 Descriere:</strong> $description</p>' : ''}
      </div>
      
      <p>Apasă butonul de mai jos pentru a te alătura întâlnirii:</p>
      <a href="$meetLink" class="meet-button">🎥 Intră în Google Meet</a>
      
      <p style="margin-top: 20px;">Link direct: <a href="$meetLink">$meetLink</a></p>
    </div>
    <div class="footer">
      <p>Această invitație a fost trimisă automat de ASIS Assistant</p>
    </div>
  </div>
</body>
</html>
''';

    return await sendEmail(
      to: to,
      subject: '📅 Invitație: $meetingTitle - $formattedDate la $formattedTime',
      body: htmlBody,
      isHtml: true,
    );
  }

  /// Send meeting reminder email
  Future<EmailResult> sendMeetingReminder({
    required String to,
    required String attendeeName,
    required String meetingTitle,
    required DateTime startTime,
    required String meetLink,
  }) async {
    final formattedTime =
        '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}';

    final htmlBody =
        '''
<!DOCTYPE html>
<html>
<head>
  <style>
    body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; }
    .header { background: #ea4335; color: white; padding: 20px; text-align: center; border-radius: 8px 8px 0 0; }
    .content { background: #f9f9f9; padding: 20px; border: 1px solid #ddd; }
    .meet-button { display: inline-block; background: #1a73e8; color: white; padding: 12px 24px; text-decoration: none; border-radius: 4px; margin-top: 15px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>⏰ Reminder: Întâlnire în 1 oră!</h1>
    </div>
    <div class="content">
      <p>Bună $attendeeName,</p>
      <p>Aceasta este o reamintire că ai o întâlnire programată:</p>
      
      <h2>$meetingTitle</h2>
      <p><strong>🕐 Ora:</strong> $formattedTime</p>
      
      <a href="$meetLink" class="meet-button">🎥 Intră în Google Meet</a>
    </div>
  </div>
</body>
</html>
''';

    return await sendEmail(
      to: to,
      subject: '⏰ Reminder: $meetingTitle începe la $formattedTime',
      body: htmlBody,
      isHtml: true,
    );
  }
}
