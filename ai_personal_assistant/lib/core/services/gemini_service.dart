import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:intl/intl.dart';

/// Response from the Gemini AI
class AIResponse {
  final String response;
  final String? intent;
  final Map<String, dynamic>? actionData;
  final bool needsConfirmation;
  final String? followUpQuestion;
  final String? searchQuery;
  final String? error;

  AIResponse({
    required this.response,
    this.intent,
    this.actionData,
    this.needsConfirmation = false,
    this.followUpQuestion,
    this.searchQuery,
    this.error,
  });

  factory AIResponse.fromJson(Map<String, dynamic> json) {
    return AIResponse(
      response: json['response'] ?? '',
      intent: json['intent'],
      actionData: json['action_data'],
      needsConfirmation: json['needs_confirmation'] ?? false,
      followUpQuestion: json['follow_up_question'],
      searchQuery: json['search_query'],
    );
  }

  factory AIResponse.error(String errorMessage) {
    return AIResponse(
      response: 'Îmi pare rău, am întâmpinat o problemă: $errorMessage',
      intent: 'error',
      error: errorMessage,
    );
  }

  bool get hasAction =>
      intent != null && intent != 'general' && intent != 'error';
  bool get needsSearch => searchQuery != null && searchQuery!.isNotEmpty;
}

/// Google Gemini AI Service
class GeminiService {
  static final GeminiService _instance = GeminiService._internal();
  factory GeminiService() => _instance;
  GeminiService._internal();

  GenerativeModel? _model;
  bool _isInitialized = false;

  static const List<String> _availableModels = [
    'gemini-2.5-flash',
    'gemini-2.0-flash',
    'gemini-1.5-flash',
    'gemini-1.5-pro',
  ];

  /// Initialize the Gemini service with API key
  Future<bool> initialize(String apiKey) async {
    if (apiKey.isEmpty) {
      print('⚠️ Gemini API key not provided');
      return false;
    }

    try {
      _model = GenerativeModel(
        model: _availableModels[0],
        apiKey: apiKey,
        generationConfig: GenerationConfig(
          temperature: 0.7,
          topP: 0.9,
          topK: 40,
          maxOutputTokens: 2048,
        ),
      );

      _isInitialized = true;
      print('✅ Gemini service initialized with model: ${_availableModels[0]}');
      return true;
    } catch (e) {
      print('❌ Failed to initialize Gemini: $e');
      return false;
    }
  }

  bool get isInitialized => _isInitialized;

  // Context utilizator (email configurat, etc.)
  String? _userEmail;

  /// Setează email-ul utilizatorului pentru context
  void setUserEmail(String? email) {
    _userEmail = email;
    print('📧 User email set: ${email ?? "not configured"}');
  }

  String _buildSystemPrompt() {
    final currentDate = DateFormat('dd MMMM yyyy', 'ro').format(DateTime.now());
    final currentTime = DateFormat('HH:mm').format(DateTime.now());

    // Adaugă informații despre email-ul configurat
    String emailContext = '';
    if (_userEmail != null && _userEmail!.isNotEmpty) {
      emailContext =
          '''

CONFIGURARE EMAIL UTILIZATOR:
- Adresa de email configurată: $_userEmail
- Când trimiți emailuri, le trimiți DE LA această adresă: $_userEmail
- Dacă utilizatorul întreabă "care e emailul meu" sau "de pe ce adresă trimiți", răspunde cu: $_userEmail
''';
    } else {
      emailContext = '''

CONFIGURARE EMAIL:
- Utilizatorul NU a configurat încă o adresă de email în aplicație
- Dacă utilizatorul cere să trimiți email, spune-i să configureze mai întâi emailul în Setări
''';
    }

    return '''Ești ASIS, un asistent personal AI vocal în limba română. Data curentă: $currentDate, ora: $currentTime.$emailContext

PERSONALITATE:
- Ești prietenos, empatic și util
- Răspunzi natural, ca într-o conversație reală cu un prieten
- Folosești un ton cald dar profesional
- Răspunsurile sunt concise (1-3 propoziții pentru întrebări simple)
- Pentru explicații complexe, poți fi mai detaliat
- Vorbești ca un om, nu ca un robot

CAPABILITĂȚI:
1. TASK-URI: Poți adăuga, lista, marca complete sau șterge task-uri
2. CUMPĂRĂTURI: Gestionezi liste de cumpărături și sugerezi reduceri
3. INFORMAȚII: Poți căuta informații pe internet când e necesar
4. EMAIL TRIMITERE: Poți trimite emailuri când utilizatorul cere explicit
5. EMAIL CITIRE: Poți citi și rezuma emailuri din inbox-ul utilizatorului
6. REMINDER-URI: Poți seta reminder-uri pentru task-uri
7. CĂUTARE: Poți căuta pe internet informații actuale
8. CALENDAR: Poți adăuga evenimente în Google Calendar
9. ÎNTÂLNIRI: Poți programa întâlniri cu Google Meet, trimite invitații și reminder-uri prin email

REGULI PENTRU PROGRAMARE ÎNTÂLNIRI:
- Când utilizatorul vrea să programeze o întâlnire/meeting, extrage: titlu, dată, oră, email invitat, nume invitat
- Creezi automat un link Google Meet
- Trimiți email de invitație persoanei respective
- Programezi reminder prin email cu 1 oră înainte pentru ambele persoane
- Adaugi evenimentul în calendarul utilizatorului

REGULI IMPORTANTE PENTRU ACȚIUNI:
- Când utilizatorul CERE EXPLICIT să adaugi ceva (ex: "adaugă lapte pe listă", "pune pâine pe lista de cumpărături", "salvează task"), EXECUTĂ IMEDIAT acțiunea
- Setează "needs_confirmation": false când comanda e clară și explicită
- Setează "needs_confirmation": true DOAR când utilizatorul doar menționează ceva vag fără a cere explicit
- După executare, confirmă ce ai făcut (ex: "Am adăugat laptele pe lista de cumpărături!")
- Pune întrebări de follow-up naturale ("Mai ai nevoie de altceva?")
- Când ai nevoie de informații actuale (vreme, știri, prețuri), caută pe internet

EXEMPLE ACȚIUNE IMEDIATĂ (needs_confirmation: false):
- "adaugă lapte pe lista de cumpărături" -> EXECUTĂ, confirmă
- "pune 2 kg mere pe listă" -> EXECUTĂ, confirmă
- "salvează task: să sun la doctor" -> EXECUTĂ, confirmă
- "șterge laptele de pe listă" -> EXECUTĂ, confirmă
- "programează o întâlnire cu Ion mâine la 14:00" -> EXECUTĂ, confirmă
- "fă un meet cu ana@email.com poimâine la 10" -> EXECUTĂ, confirmă

EXEMPLE CU CONFIRMARE (needs_confirmation: true):
- "am nevoie de lapte" (menționare, nu comandă) -> întreabă dacă vrea să adaugi
- "trebuie să sun la doctor" (menționare, nu comandă) -> întreabă dacă vrea să salvezi task
- "ar trebui să vorbesc cu Ion" (vag) -> întreabă detalii

RĂSPUNS FORMAT:
Răspunde DOAR cu un JSON valid în formatul:
{
    "response": "răspunsul tău vocal către utilizator - trebuie să sune natural când e citit cu voce tare",
    "intent": "tipul de acțiune detectată sau null",
    "action_data": {date relevante pentru acțiune} sau null,
    "needs_confirmation": false pentru comenzi explicite / true pentru mențiuni vagi,
    "follow_up_question": "întrebare de follow-up" sau null,
    "search_query": "termeni de căutare pe internet dacă e nevoie" sau null
}

INTENT-URI POSIBILE:
- "add_task": adaugă task-uri (action_data: {title: "...", description: "...", due_date: null, priority: "medium"} SAU pentru multiple: [{title: "..."} , {title: "..."}])
- "list_tasks": listează task-uri
- "complete_task": marchează task complet (action_data: {task_id: N} sau {task_title: "..."})
- "add_shopping_item": adaugă la cumpărături (action_data: {name: "...", quantity: "...", category: "..."} SAU pentru multiple: [{name: "lapte"}, {name: "pâine"}, {name: "ouă"}])
- "list_shopping": listează cumpărături
- "remove_shopping_item": șterge de pe listă (action_data: {item_id: N} sau {item_name: "..."})
- "send_email": trimite email (action_data: {to: "...", subject: "...", body: "..."})
- "read_emails": citește emailurile recente din inbox (action_data: {count: 5}) - implicit 5 emailuri
- "read_last_email": citește ultimul email primit (action_data: null)
- "search_emails": caută emailuri după subiect sau expeditor (action_data: {query: "..."})
- "summarize_email": rezumă un email specific (action_data: {index: N} - N=1 pentru ultimul)
- "search_internet": caută informații (action_data: {query: "..."})
- "schedule_meeting": programează întâlnire cu Meet (action_data: {title: "...", date: "YYYY-MM-DD", time: "HH:MM", attendee_email: "...", attendee_name: "...", description: "...", duration_minutes: 60, reminder_hours: 1})
- "add_calendar_event": adaugă eveniment simplu în calendar (action_data: {title: "...", date: "YYYY-MM-DD", time: "HH:MM", description: "...", duration_minutes: 60})
- "list_calendar_events": listează evenimentele din calendar
- "cancel_calendar_event": anulează eveniment (action_data: {title: "..."} sau {event_id: N})
- "general": conversație generală (fără acțiune specială)

REGULI PENTRU MULTIPLE PRODUSE/TASK-URI:
- Când utilizatorul cere să adaugi MAI MULTE produse sau task-uri deodată, folosește action_data ca ARRAY
- Exemplu: "adaugă lapte, pâine și ouă" -> action_data: [{name: "lapte"}, {name: "pâine"}, {name: "ouă"}]
- Exemplu: "am 3 task-uri: X, Y, Z" -> action_data: [{title: "X"}, {title: "Y"}, {title: "Z"}]

REGULI PENTRU CITIRE EMAIL:
- "citește-mi emailurile" sau "ce emailuri am" -> read_emails cu count: 5
- "citește ultimul email" sau "ce mi-a scris X" -> read_last_email
- "caută emailuri de la Ion" sau "emailuri despre proiect" -> search_emails
- "fă-mi rezumat la ultimul email" sau "rezumă emailul" -> summarize_email cu index: 1
- "rezumă emailul de la X" -> mai întâi search_emails pentru a găsi emailul

IMPORTANT: 
- Răspunsul trebuie să fie natural și fluid pentru a fi citit cu voce tare!
- Pentru comenzi explicite de adăugare/ștergere, ÎNTOTDEAUNA setează needs_confirmation: false și include action_data complet!
- Pentru întâlniri, extrage data în format YYYY-MM-DD și ora în format HH:MM
- Dacă utilizatorul spune "mâine", "poimâine", calculează data corectă bazată pe data curentă: $currentDate
''';
  }

  /// Process a user message and generate AI response
  Future<AIResponse> chat(
    String userMessage, {
    List<Map<String, String>>? conversationHistory,
  }) async {
    if (!_isInitialized || _model == null) {
      return AIResponse.error(
        'Serviciul AI nu este configurat. Verifică cheia API Gemini.',
      );
    }

    try {
      final systemPrompt = _buildSystemPrompt();
      final fullPrompt =
          '$systemPrompt\n\nMesajul utilizatorului: $userMessage';

      // Build content with history
      List<Content> contents = [];

      if (conversationHistory != null && conversationHistory.isNotEmpty) {
        for (final msg in conversationHistory.take(10)) {
          final role = msg['role'] == 'user' ? 'user' : 'model';
          contents.add(Content(role, [TextPart(msg['content'] ?? '')]));
        }
      }

      contents.add(Content.text(fullPrompt));

      // Generate response
      final response = await _model!.generateContent(contents);
      final responseText = response.text ?? '';

      return _parseResponse(responseText);
    } catch (e) {
      print('❌ Gemini chat error: $e');
      return AIResponse.error(e.toString());
    }
  }

  /// Process user message with additional search context
  Future<AIResponse> chatWithSearchContext(
    String userMessage,
    String searchContext, {
    List<Map<String, String>>? conversationHistory,
  }) async {
    if (!_isInitialized || _model == null) {
      return AIResponse.error(
        'Serviciul AI nu este configurat. Verifică cheia API Gemini.',
      );
    }

    try {
      final systemPrompt = _buildSystemPrompt();
      final fullPrompt =
          '''$systemPrompt

Informații găsite pe internet:
$searchContext

Mesajul utilizatorului: $userMessage

Răspunde la întrebarea utilizatorului folosind informațiile de mai sus.''';

      final response = await _model!.generateContent([
        Content.text(fullPrompt),
      ]);
      final responseText = response.text ?? '';

      return _parseResponse(responseText);
    } catch (e) {
      print('❌ Gemini chat with search error: $e');
      return AIResponse.error(e.toString());
    }
  }

  AIResponse _parseResponse(String responseText) {
    try {
      // Clean up the response - remove markdown code blocks if present
      String cleanedResponse = responseText.trim();

      if (cleanedResponse.startsWith('```json')) {
        cleanedResponse = cleanedResponse.substring(7);
      } else if (cleanedResponse.startsWith('```')) {
        cleanedResponse = cleanedResponse.substring(3);
      }

      if (cleanedResponse.endsWith('```')) {
        cleanedResponse = cleanedResponse.substring(
          0,
          cleanedResponse.length - 3,
        );
      }

      cleanedResponse = cleanedResponse.trim();

      // Try to find JSON in the response
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(cleanedResponse);
      if (jsonMatch != null) {
        final jsonStr = jsonMatch.group(0)!;
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        return AIResponse.fromJson(json);
      }

      // If no JSON found, treat the whole response as a general response
      return AIResponse(
        response: cleanedResponse.isNotEmpty
            ? cleanedResponse
            : 'Îmi pare rău, nu am putut procesa cererea.',
        intent: 'general',
      );
    } catch (e) {
      print('⚠️ Failed to parse AI response: $e');
      print('Raw response: $responseText');

      // Try to extract just the response text
      final responseMatch = RegExp(
        r'"response"\s*:\s*"([^"]*)"',
      ).firstMatch(responseText);
      if (responseMatch != null) {
        return AIResponse(
          response: responseMatch.group(1) ?? responseText,
          intent: 'general',
        );
      }

      return AIResponse(
        response: responseText.isNotEmpty
            ? responseText
            : 'Îmi pare rău, am întâmpinat o problemă. Poți repeta?',
        intent: 'general',
      );
    }
  }

  /// Reset the chat session (no-op for stateless chat)
  void resetChat() {
    // Stateless chat - no session to reset
  }
}
