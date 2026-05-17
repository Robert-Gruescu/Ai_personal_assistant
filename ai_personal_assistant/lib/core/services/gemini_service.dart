import 'dart:convert';
import 'dart:typed_data';
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

class GeminiImage {
  final Uint8List bytes;
  final String mimeType;

  GeminiImage({required this.bytes, required this.mimeType});
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

  String? _userEmail;

  void setUserEmail(String? email) {
    _userEmail = email;
    print('📧 User email set: ${email ?? "not configured"}');
  }

  String _buildSystemPrompt() {
    final currentDate = DateFormat('dd MMMM yyyy', 'ro').format(DateTime.now());
    final currentTime = DateFormat('HH:mm').format(DateTime.now());

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
2.1 PREȚURI LIVE: Poți compara prețuri live între magazine pentru lista de cumpărături și recomanzi magazinul mai avantajos acum
3. INFORMAȚII: Poți căuta informații pe internet când e necesar
4. EMAIL TRIMITERE: Poți trimite emailuri când utilizatorul cere explicit
5. EMAIL CITIRE: Poți citi și rezuma emailuri din inbox-ul utilizatorului
6. REMINDER-URI: Poți seta reminder-uri pentru task-uri
7. CĂUTARE: Poți căuta pe internet informații actuale
8. CALENDAR: Poți adăuga evenimente în Google Calendar
9. ÎNTÂLNIRI: Poți programa întâlniri cu Google Meet, trimite invitații și reminder-uri prin email
10. REDUCERI: Poți căuta reduceri și oferte de la supermarketuri din România

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
- NU afirma niciodată că ai executat o acțiune înainte de confirmarea execuției
- Dacă funcția nu este implementată sau nu poate fi executată, spune clar: "Nu pot face asta acum" și oferă motivul concret
- După executare, confirmă ce ai făcut (ex: "Am adăugat laptele pe lista de cumpărături!")
- Pune întrebări de follow-up naturale ("Mai ai nevoie de altceva?")
- Când ai nevoie de informații actuale (vreme, știri, prețuri), caută pe internet

REGULĂ CRITICĂ — DIFERENȚA DINTRE get_discounts ȘI search_internet:
Aceasta este cea mai importantă regulă pentru alegerea corectă a intent-ului:

→ Folosește "get_discounts" DOAR când utilizatorul vrea să VADĂ LISTA GENERALĂ DE REDUCERI/OFERTE a unui magazin:
   • "ce reduceri sunt la Lidl?"
   • "arată-mi ofertele de la Kaufland săptămâna asta"
   • "ce e la reducere acum?"
   • "ofertele Carrefour"
   • "ce promoții are Penny?"

→ Folosește "search_internet" când utilizatorul întreabă PREȚUL unui PRODUS SPECIFIC, chiar dacă menționează un magazin:
   • "cât costă o doză de Coca-Cola la Lidl?" → search_internet, query: "pret doza Coca Cola Lidl Romania"
   • "ce preț are laptele la Kaufland?" → search_internet, query: "pret lapte Kaufland Romania"
   • "cât costă benzina azi?" → search_internet
   • "prețul iPhone 15 la eMAG?" → search_internet
   • "cât face pâinea la Mega Image?" → search_internet

REGULA SIMPLĂ: Dacă întrebarea conține un PRODUS SPECIFIC + cuvinte ca "costă", "preț", "face", "este" → search_internet.
              Dacă întrebarea e generală despre reduceri/oferte/promoții → get_discounts.

REGULI PENTRU get_discounts:
- Dacă menționează un magazin specific, pune-l în stores: ["Magazin"]
- Dacă nu menționează magazine, lasă stores: null pentru a căuta la toate
- Dacă utilizatorul spune "actualizează", "caută din nou", "date noi", adaugă force_refresh: true în action_data
- Rezultatele includ automat produsele din lista de cumpărături marcate prioritar

EXEMPLE ACȚIUNE IMEDIATĂ (needs_confirmation: false):
- "adaugă lapte pe lista de cumpărături" -> EXECUTĂ, confirmă
- "pune 2 kg mere pe listă" -> EXECUTĂ, confirmă
- "salvează task: să sun la doctor" -> EXECUTĂ, confirmă
- "șterge laptele de pe listă" -> EXECUTĂ, confirmă
- "programează o întâlnire cu Ion mâine la 14:00" -> EXECUTĂ, confirmă
- "fă un meet cu ana@email.com poimâine la 10" -> EXECUTĂ, confirmă
- "ce reduceri sunt la Lidl?" -> get_discounts, stores: ["Lidl"]
- "arată ofertele Kaufland" -> get_discounts, stores: ["Kaufland"]
- "cât costă Coca-Cola la Lidl?" -> search_internet, query: "pret Coca Cola doza Lidl Romania"

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
- "add_task": adaugă task-uri (action_data: {title: "...", description: "...", due_date: null, priority: "medium"} SAU pentru multiple: {tasks: [{title: "..."}, {title: "..."}]})
- "list_tasks": listează task-uri
- "complete_task": marchează task complet (action_data: {task_id: N} sau {task_title: "..."})
- "add_shopping_item": adaugă la cumpărături (action_data: {name: "...", quantity: "...", category: "..."} SAU pentru multiple: {items: [{name: "lapte"}, {name: "pâine"}, {name: "ouă"}]})
- "list_shopping": listează cumpărături
- "remove_shopping_item": șterge de pe listă (action_data: {item_id: N} sau {item_name: "..."})
- "send_email": trimite email (action_data: {to: "...", subject: "...", body: "..."})
- "read_emails": citește emailurile recente din inbox (action_data: {count: 5})
- "read_last_email": citește ultimul email primit (action_data: null)
- "search_emails": caută emailuri după subiect sau expeditor (action_data: {query: "..."})
- "summarize_email": rezumă un email specific (action_data: {index: N} - N=1 pentru ultimul)
- "search_internet": caută informații sau prețuri specifice (action_data: {query: "..."})
- "compare_shopping_prices": compară prețuri live pentru lista de cumpărături (action_data: {items: ["lapte", "ouă", "pâine"]} sau null pentru lista curentă)
- "get_discounts": caută reduceri GENERALE de la supermarketuri .ro (action_data: {"stores": ["Lidl","Kaufland"]} sau null pentru toate; adaugă "force_refresh": true dacă utilizatorul cere date noi)
- "schedule_meeting": programează întâlnire cu Meet (action_data: {title: "...", date: "YYYY-MM-DD", time: "HH:MM", attendee_email: "...", attendee_name: "...", description: "...", duration_minutes: 60, reminder_hours: 1})
- "add_calendar_event": adaugă eveniment simplu în calendar (action_data: {title: "...", date: "YYYY-MM-DD", time: "HH:MM", description: "...", duration_minutes: 60})
- "list_calendar_events": listează evenimentele din calendar
- "cancel_calendar_event": anulează eveniment (action_data: {title: "..."} sau {event_id: N})
- "general": conversație generală (fără acțiune specială)

REGULI PENTRU MULTIPLE PRODUSE/TASK-URI:
- Când utilizatorul cere să adaugi MAI MULTE produse sau task-uri deodată, folosește mereu obiecte JSON cu cheie:
- Produse multiple: action_data: {items: [{name: "lapte"}, {name: "pâine"}, {name: "ouă"}]}
- Task-uri multiple: action_data: {tasks: [{title: "X"}, {title: "Y"}, {title: "Z"}]}
- NU trimite action_data ca array direct la rădăcină

REGULĂ PENTRU CUMPĂRĂTURI MULTE:
- Dacă utilizatorul adaugă multe produse (ex. listă mare), după confirmare oferă și o sugestie scurtă de 2-3 locuri potrivite de cumpărături.
- Dacă utilizatorul cere explicit cel mai ieftin magazin sau comparație de prețuri, setează intent="compare_shopping_prices".

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
- Răspunde ÎNTOTDEAUNA DOAR cu JSON valid, fără text în afara JSON-ului!
''';
  }

  Future<AIResponse> chat(
    String userMessage, {
    List<Map<String, String>>? conversationHistory,
    String? runtimeContext,
  }) async {
    if (!_isInitialized || _model == null) {
      return AIResponse.error(
        'Serviciul AI nu este configurat. Verifică cheia API Gemini.',
      );
    }

    try {
      final systemPrompt = _buildSystemPrompt();
      final contextBlock =
          (runtimeContext != null && runtimeContext.trim().isNotEmpty)
          ? '\n\n$runtimeContext'
          : '';
      final fullPrompt =
          '$systemPrompt$contextBlock\n\nMesajul utilizatorului: $userMessage';

      List<Content> contents = [];

      if (conversationHistory != null && conversationHistory.isNotEmpty) {
        for (final msg in conversationHistory.take(10)) {
          final role = msg['role'] == 'user' ? 'user' : 'model';
          contents.add(Content(role, [TextPart(msg['content'] ?? '')]));
        }
      }

      contents.add(Content.text(fullPrompt));

      final response = await _model!.generateContent(contents);
      final responseText = response.text ?? '';

      return _parseResponse(responseText);
    } catch (e) {
      print('❌ Gemini chat error: $e');
      return AIResponse.error(e.toString());
    }
  }

  /// Process user message with additional search context.
  /// IMPORTANT: acest apel trebuie să returneze text simplu, NU JSON,
  /// deoarece e folosit pentru a formula răspunsul final după căutare.
  Future<AIResponse> chatWithSearchContext(
    String userMessage,
    String searchContext, {
    List<Map<String, String>>? conversationHistory,
    String? runtimeContext,
  }) async {
    if (!_isInitialized || _model == null) {
      return AIResponse.error(
        'Serviciul AI nu este configurat. Verifică cheia API Gemini.',
      );
    }

    try {
      final currentDate = DateFormat(
        'dd MMMM yyyy',
        'ro',
      ).format(DateTime.now());
      final currentTime = DateFormat('HH:mm').format(DateTime.now());

      // Prompt simplificat pentru search context — cere text simplu, NU JSON
      final contextBlock =
          (runtimeContext != null && runtimeContext.trim().isNotEmpty)
          ? '\n\n$runtimeContext'
          : '';

      final fullPrompt =
          '''Ești ASIS, un asistent vocal în română. Data: $currentDate, ora: $currentTime.$contextBlock

Informații găsite pe internet:
$searchContext

Întrebarea utilizatorului: $userMessage

Răspunde DIRECT la întrebare în 1-3 propoziții, natural, ca și cum ai vorbi cu cineva.
NU folosi JSON. NU folosi formate speciale. Scrie doar textul răspunsului.
Dacă nu găsești informația exactă în datele de mai sus, spune că nu ai găsit un preț exact și sugerează să verifice direct pe site-ul magazinului.''';

      final response = await _model!.generateContent([
        Content.text(fullPrompt),
      ]);
      final responseText = response.text ?? '';

      // Returnează ca AIResponse cu intent general — textul e deja curat
      return AIResponse(response: responseText.trim(), intent: 'general');
    } catch (e) {
      print('❌ Gemini chat with search error: $e');
      return AIResponse.error(e.toString());
    }
  }

  Future<String> summarizeOffersFromImages(
    String userMessage,
    List<GeminiImage> images, {
    String? sourceTitle,
  }) async {
    if (!_isInitialized || _model == null) {
      return 'Serviciul AI nu este configurat. Verifica cheia API Gemini.';
    }

    if (images.isEmpty) {
      return 'Nu am putut citi ofertele din imagini.';
    }

    try {
      final titleLine = (sourceTitle != null && sourceTitle.trim().isNotEmpty)
          ? 'Source: ${sourceTitle.trim()}'
          : '';
      final prompt = [
        'User request: $userMessage',
        if (titleLine.isNotEmpty) titleLine,
        'Extract product offers from the catalog images.',
        'Return a concise list with product name and price.',
        'Respond in Romanian.',
        'If offers cannot be read, respond exactly: "Nu am putut citi ofertele din imagini."',
      ].join('\n');

      final parts = <Part>[TextPart(prompt)];
      for (final image in images) {
        parts.add(DataPart(image.mimeType, image.bytes));
      }

      final response = await _model!.generateContent([Content.multi(parts)]);

      return response.text ?? '';
    } catch (e) {
      print('❌ Gemini image summary error: $e');
      return 'Nu am putut citi ofertele din imagini.';
    }
  }

  AIResponse _parseResponse(String responseText) {
    try {
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

      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(cleanedResponse);
      if (jsonMatch != null) {
        final jsonStr = jsonMatch.group(0)!;
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        return AIResponse.fromJson(json);
      }

      return AIResponse(
        response: cleanedResponse.isNotEmpty
            ? cleanedResponse
            : 'Îmi pare rău, nu am putut procesa cererea.',
        intent: 'general',
      );
    } catch (e) {
      print('⚠️ Failed to parse AI response: $e');
      print('Raw response: $responseText');

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

  void resetChat() {
    // Stateless chat - no session to reset
  }

  /// Extrage informațiile relevante dintr-o pagină web față de o întrebare
  Future<String?> extractRelevantInfo({
    required String pageText,
    required String question,
    String? sourceUrl,
  }) async {
    if (!_isInitialized || _model == null) return null;

    try {
      final prompt =
          '''Ai primit textul unei pagini web și o întrebare.
Extrage DOAR informațiile relevante pentru întrebare din textul paginii.
Fii concis — maxim 3-5 propoziții.
Dacă nu există informații relevante, răspunde exact: "NERELEVANT"
${sourceUrl != null ? 'Sursa: $sourceUrl' : ''}

ÎNTREBARE: $question

TEXT PAGINĂ:
$pageText

Răspunde direct cu informațiile relevante, fără introducere:''';

      final response = await _model!.generateContent([Content.text(prompt)]);
      final text = response.text?.trim() ?? '';

      if (text == 'NERELEVANT' || text.isEmpty) return null;
      return text;
    } catch (e) {
      print('❌ extractRelevantInfo error: $e');
      return null;
    }
  }
}
