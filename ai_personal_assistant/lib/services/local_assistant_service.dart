import 'dart:convert';
import '../core/services/services.dart';
import '../core/models/models.dart';

/// Voice response data
class VoiceResponse {
  final String transcription;
  final String response;
  final Map<String, dynamic>? action;
  final bool success;
  final String? error;
  final String? intent;
  final bool needsConfirmation;

  VoiceResponse({
    required this.transcription,
    required this.response,
    this.action,
    required this.success,
    this.error,
    this.intent,
    this.needsConfirmation = false,
  });
}

/// Chat response data
class ChatResponse {
  final String response;
  final Map<String, dynamic>? action;
  final bool success;
  final String? error;
  final String? intent;
  final bool needsConfirmation;

  ChatResponse({
    required this.response,
    this.action,
    required this.success,
    this.error,
    this.intent,
    this.needsConfirmation = false,
  });
}

/// Task item for UI
class TaskItem {
  final int id;
  final String title;
  final String? description;
  final DateTime? dueDate;
  final int priority;
  final String? category;
  final bool isCompleted;

  TaskItem({
    required this.id,
    required this.title,
    this.description,
    this.dueDate,
    this.priority = 2,
    this.category,
    this.isCompleted = false,
  });

  factory TaskItem.fromJson(Map<String, dynamic> json) {
    return TaskItem(
      id: json['id'] is int
          ? json['id']
          : int.tryParse(json['id'].toString()) ?? 0,
      title: json['title'] ?? '',
      description: json['description'],
      dueDate: json['due_date'] != null
          ? DateTime.tryParse(json['due_date'])
          : null,
      priority: json['priority'] ?? 2,
      category: json['category'],
      isCompleted: json['is_completed'] ?? false,
    );
  }
}

/// Shopping item for UI
class ShoppingItemUI {
  final int id;
  final String name;
  final String quantity;
  final String? category;
  final bool isPurchased;
  final String? notes;
  final double? priceEstimate;

  ShoppingItemUI({
    required this.id,
    required this.name,
    required this.quantity,
    this.category,
    this.isPurchased = false,
    this.notes,
    this.priceEstimate,
  });

  factory ShoppingItemUI.fromJson(Map<String, dynamic> json) {
    return ShoppingItemUI(
      id: json['id'] is int
          ? json['id']
          : int.tryParse(json['id'].toString()) ?? 0,
      name: json['name'] ?? '',
      quantity: json['quantity'] ?? '1',
      category: json['category'],
      isPurchased: json['is_purchased'] ?? false,
      notes: json['notes'],
      priceEstimate: json['price_estimate']?.toDouble(),
    );
  }
}

/// Shopping list for UI
class ShoppingList {
  final List<ShoppingItemUI> items;
  final int count;
  final double totalEstimate;

  ShoppingList({
    required this.items,
    required this.count,
    required this.totalEstimate,
  });

  factory ShoppingList.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List? ?? [])
        .map((item) => ShoppingItemUI.fromJson(item))
        .toList();
    return ShoppingList(
      items: items,
      count: json['count'] ?? items.length,
      totalEstimate: (json['total_estimate'] ?? 0).toDouble(),
    );
  }
}

/// Local Assistant Service - All processing done on device
class LocalAssistantService {
  static final LocalAssistantService _instance =
      LocalAssistantService._internal();
  factory LocalAssistantService() => _instance;
  LocalAssistantService._internal();

  // Core services
  final ConfigService _config = ConfigService();
  final DatabaseService _db = DatabaseService();
  final GeminiService _gemini = GeminiService();
  final SpeechToTextService _stt = SpeechToTextService();
  final TextToSpeechService _tts = TextToSpeechService();
  final ActionExecutor _executor = ActionExecutor();
  final SearchService _search = SearchService();
  final EmailService _email = EmailService();
  final NotificationService _notification = NotificationService();
  final DeviceCalendarService _deviceCalendar = DeviceCalendarService();

  bool _isInitialized = false;
  String? _currentConversationId;
  List<Map<String, String>> _conversationHistory = [];

  bool get isInitialized => _isInitialized;
  String? get currentConversationId => _currentConversationId;

  /// Initialize all services
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      print('🚀 Initializing Local Assistant Service...');

      await _config.initialize();
      await _db.initialize();

      final apiKey = await _config.geminiApiKey;
      if (apiKey != null && apiKey.isNotEmpty) {
        await _gemini.initialize(apiKey);
      } else {
        print('⚠️ Gemini API key not configured');
      }

      final language = await _config.speechLanguage;
      final ttsRate = await _config.ttsRate;
      final ttsVolume = await _config.ttsVolume;
      await _tts.initialize(
        language: language,
        rate: ttsRate,
        volume: ttsVolume,
      );

      await _stt.initialize(language: language);
      await _notification.initialize();
      await _deviceCalendar.initialize();

      final emailConfig = await _config.getEmailConfig();
      if (emailConfig['smtp_user'] != null &&
          emailConfig['smtp_password'] != null) {
        _email.initialize(
          smtpHost: emailConfig['smtp_host'],
          smtpPort: emailConfig['smtp_port'],
          smtpUser: emailConfig['smtp_user'],
          smtpPassword: emailConfig['smtp_password'],
          imapHost: emailConfig['imap_host'],
          imapPort: emailConfig['imap_port'],
        );
        _gemini.setUserEmail(emailConfig['smtp_user']);
      } else {
        _gemini.setUserEmail(null);
      }

      _isInitialized = true;
      print('✅ Local Assistant Service initialized successfully');
      return true;
    } catch (e) {
      print('❌ Failed to initialize Local Assistant Service: $e');
      return false;
    }
  }

  Future<bool> configureApiKey(String apiKey) async {
    await _config.setGeminiApiKey(apiKey);
    return await _gemini.initialize(apiKey);
  }

  Future<void> reloadEmailConfig() async {
    print('📧 Reloading email configuration...');
    final emailConfig = await _config.getEmailConfig();

    final smtpUser = emailConfig['smtp_user'];
    final smtpPassword = emailConfig['smtp_password'];

    if (smtpUser != null &&
        smtpUser.toString().isNotEmpty &&
        smtpPassword != null &&
        smtpPassword.toString().isNotEmpty) {
      _email.initialize(
        smtpHost: emailConfig['smtp_host'],
        smtpPort: emailConfig['smtp_port'],
        smtpUser: smtpUser,
        smtpPassword: smtpPassword,
        imapHost: emailConfig['imap_host'],
        imapPort: emailConfig['imap_port'],
      );
      _gemini.setUserEmail(smtpUser);
      print('✅ Email configuration reloaded: $smtpUser');
    } else {
      _gemini.setUserEmail(null);
      print('⚠️ Email not configured properly');
    }
  }

  /// Process text message
  Future<ChatResponse> sendMessage(String message) async {
    if (!_isInitialized) {
      await initialize();
    }

    if (!_gemini.isInitialized) {
      return ChatResponse(
        response:
            'Serviciul AI nu este configurat. Te rog configurează cheia API Gemini în setări.',
        success: false,
        error: 'AI not configured',
      );
    }

    try {
      print('💬 Processing message: $message');

      final persistentContext = await _buildPersistentContext();

      // Get AI response
      final aiResult = await _gemini.chat(
        message,
        conversationHistory: _conversationHistory,
        runtimeContext: persistentContext,
      );

      String responseText = aiResult.response;
      ActionResult? actionResult;
      Map<String, dynamic>? resolvedActionData = aiResult.actionData == null
          ? null
          : Map<String, dynamic>.from(aiResult.actionData!);

      if (aiResult.intent == 'search_internet') {
        final query = resolvedActionData?['query'] as String?;
        if ((query == null || query.trim().isEmpty) &&
            aiResult.searchQuery != null &&
            aiResult.searchQuery!.trim().isNotEmpty) {
          resolvedActionData = resolvedActionData ?? {};
          resolvedActionData['query'] = aiResult.searchQuery!.trim();
        }
      }

      // Handle search intent fără action dedicat
      if (aiResult.needsSearch && aiResult.intent != 'search_internet') {
        print('🔍 Searching for: ${aiResult.searchQuery}');
        final searchResult = await _search.search(aiResult.searchQuery!);
        if (searchResult.success) {
          final searchContext = searchResult.formatForAI();
          final aiWithSearch = await _gemini.chatWithSearchContext(
            message,
            searchContext,
            conversationHistory: _conversationHistory,
            runtimeContext: persistentContext,
          );
          responseText = _extractCleanResponse(aiWithSearch.response);
        }
      }

      // Execute action if detected
      if (aiResult.hasAction && !aiResult.needsConfirmation) {
        print('🚀 Executing action: ${aiResult.intent}');
        actionResult = await _executor.execute(
          aiResult.intent!,
          resolvedActionData,
        );

        if (actionResult.success) {
          if (aiResult.intent == 'search_internet') {
            responseText = await _buildSearchResponse(
              message: message,
              actionResult: actionResult,
              persistentContext: persistentContext,
            );
          } else {
            responseText = _updateResponseWithActionResult(
              aiResult.intent!,
              actionResult,
              responseText,
            );
          }
        } else {
          responseText = _buildActionFailureResponse(
            aiResult.intent!,
            actionResult.error,
          );
        }
      }

      // Update conversation history
      _conversationHistory.add({'role': 'user', 'content': message});
      _conversationHistory.add({'role': 'assistant', 'content': responseText});

      // Keep only last 20 messages
      if (_conversationHistory.length > 20) {
        _conversationHistory = _conversationHistory.sublist(
          _conversationHistory.length - 20,
        );
      }

      // Save to database
      if (_currentConversationId != null) {
        await _db.addMessageToConversation(
          _currentConversationId!,
          'user',
          message,
        );
        await _db.addMessageToConversation(
          _currentConversationId!,
          'assistant',
          responseText,
        );
      }

      return ChatResponse(
        response: responseText,
        action: actionResult?.toJson(),
        success: actionResult?.success ?? true,
        error: actionResult?.success == false ? actionResult?.error : null,
        intent: aiResult.intent,
        needsConfirmation: aiResult.needsConfirmation,
      );
    } catch (e) {
      print('❌ Error processing message: $e');
      return ChatResponse(
        response: 'Îmi pare rău, am întâmpinat o problemă. Poți repeta?',
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Construiește răspunsul pentru search_internet folosind toate sursele disponibile:
  /// page_content (conținut complet pagini), formatted (snippets), catalog_text (PDF)
  Future<String> _buildSearchResponse({
    required String message,
    required ActionResult actionResult,
    required String persistentContext,
  }) async {
    final data = actionResult.data ?? {};

    final formatted = data['formatted']?.toString() ?? '';
    final pageContent = data['page_content']?.toString() ?? '';
    final catalogText = data['catalog_text']?.toString() ?? '';
    final catalogTitle = data['catalog_title']?.toString() ?? '';
    final catalogImages = (data['catalog_images'] as List? ?? [])
        .map((e) => e.toString())
        .where((e) => e.trim().isNotEmpty)
        .toList();

    // Construiește contextul complet din toate sursele disponibile
    final contextParts = <String>[];

    if (formatted.trim().isNotEmpty) {
      contextParts.add(formatted.trim());
    }

    if (pageContent.trim().isNotEmpty) {
      contextParts.add(
        'Conținut detaliat din pagini web:\n${pageContent.trim()}',
      );
    }

    if (catalogText.trim().isNotEmpty) {
      final catalogContext = catalogTitle.trim().isNotEmpty
          ? 'Catalog: $catalogTitle\n\n$catalogText'
          : catalogText;
      contextParts.add(catalogContext);
    }

    // Dacă avem context text — trimite la Gemini
    if (contextParts.isNotEmpty) {
      final fullContext = contextParts.join('\n\n---\n\n');
      final aiWithSearch = await _gemini.chatWithSearchContext(
        '$message\n\nInstructions: folosește DOAR informațiile de mai sus '
        'pentru a răspunde. Nu include linkuri. Răspunde în română, '
        'concis și natural. Dacă nu găsești informația exactă, spune '
        'că nu ai găsit-o și sugerează să verifice direct pe site.',
        fullContext,
        conversationHistory: _conversationHistory,
        runtimeContext: persistentContext,
      );
      return _stripLinks(_extractCleanResponse(aiWithSearch.response));
    }

    // Fallback: imagini din flyer/catalog
    if (catalogImages.isNotEmpty) {
      final images = <GeminiImage>[];
      for (final url in catalogImages.take(2)) {
        final download = await _search.downloadImage(url);
        if (download != null) {
          images.add(
            GeminiImage(bytes: download.bytes, mimeType: download.mimeType),
          );
        }
      }

      if (images.isNotEmpty) {
        final summary = await _gemini.summarizeOffersFromImages(
          message,
          images,
          sourceTitle: catalogTitle,
        );
        return _stripLinks(summary);
      }
    }

    // Fallback final: răspuns generic din date Serper
    return _updateResponseWithActionResult(
      'search_internet',
      actionResult,
      'Nu am găsit informații relevante.',
    );
  }

  /// Extrage textul curat dintr-un răspuns AI.
  /// Dacă răspunsul e deja text simplu, îl returnează ca atare.
  /// Dacă e JSON, extrage câmpul "response".
  String _extractCleanResponse(String raw) {
    if (raw.trim().isEmpty) return raw;

    final trimmed = raw.trim();
    if (!trimmed.startsWith('{') && !trimmed.startsWith('```')) {
      return trimmed;
    }

    try {
      String cleaned = trimmed;
      if (cleaned.startsWith('```json')) {
        cleaned = cleaned.substring(7);
      } else if (cleaned.startsWith('```')) {
        cleaned = cleaned.substring(3);
      }
      if (cleaned.endsWith('```')) {
        cleaned = cleaned.substring(0, cleaned.length - 3);
      }
      cleaned = cleaned.trim();

      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(cleaned);
      if (jsonMatch != null) {
        final json = jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
        final response = json['response'] as String?;
        if (response != null && response.trim().isNotEmpty) {
          return response.trim();
        }
      }
    } catch (_) {}

    final match = RegExp(
      r'"response"\s*:\s*"((?:[^"\\]|\\.)*)"',
    ).firstMatch(raw);
    if (match != null) {
      return match
          .group(1)!
          .replaceAll(r'\n', '\n')
          .replaceAll(r'\t', '\t')
          .replaceAll(r'\"', '"')
          .trim();
    }

    return raw.trim();
  }

  /// Update response text based on action result
  String _updateResponseWithActionResult(
    String intent,
    ActionResult result,
    String originalResponse,
  ) {
    if (!result.success) return originalResponse;

    final data = result.data ?? {};

    switch (intent) {
      case 'list_shopping':
        final items = data['items'] as List? ?? [];
        if (items.isEmpty) return 'Lista ta de cumpărături este goală.';
        final itemNames = items.map((i) => i['name']).join(', ');
        return 'Pe lista ta de cumpărături ai: $itemNames.';

      case 'list_tasks':
        final tasks = data['tasks'] as List? ?? [];
        if (tasks.isEmpty) return 'Nu ai niciun task activ.';
        final taskTitles = tasks.map((t) => t['title']).join(', ');
        return 'Ai următoarele task-uri: $taskTitles.';

      case 'list_calendar_events':
        final events = data['events'] as List? ?? [];
        if (events.isEmpty) return 'Nu ai evenimente programate.';
        final eventTitles = events.map((e) => e['title']).join(', ');
        return 'Ai următoarele evenimente: $eventTitles.';

      case 'search_internet':
        final directAnswer = data['direct_answer'] as String?;
        final results = data['results'] as List? ?? [];
        if ((directAnswer == null || directAnswer.trim().isEmpty) &&
            results.isEmpty) {
          return 'Nu am găsit rezultate pentru această căutare.';
        }

        final buffer = StringBuffer();
        if (directAnswer != null && directAnswer.trim().isNotEmpty) {
          buffer.writeln('Răspuns direct: ${directAnswer.trim()}');
          if (results.isNotEmpty) buffer.writeln();
        }

        if (results.isNotEmpty) {
          buffer.writeln('Rezultate:');
          final maxResults = results.length < 3 ? results.length : 3;
          for (int i = 0; i < maxResults; i++) {
            final r = results[i] as Map? ?? {};
            final title = r['title']?.toString() ?? '';
            final snippet = r['snippet']?.toString() ?? '';
            if (title.isNotEmpty) buffer.writeln('${i + 1}. $title');
            if (snippet.isNotEmpty) buffer.writeln('   $snippet');
            if (i < maxResults - 1) buffer.writeln();
          }
        }

        return buffer.toString().trim();

      default:
        return result.message ?? originalResponse;
    }
  }

  String _buildActionFailureResponse(String intent, String? error) {
    final reason = (error != null && error.trim().isNotEmpty)
        ? error.trim()
        : 'Nu am putut determina motivul exact.';
    final hint = _actionFailureHint(intent, reason);
    final actionLabel = _actionLabel(intent);
    return 'Nu am putut $actionLabel. Motiv: $reason${hint.isNotEmpty ? ' $hint' : ''}';
  }

  String _actionFailureHint(String intent, String reason) {
    final lowerReason = reason.toLowerCase();

    if (intent == 'send_email' ||
        intent == 'read_emails' ||
        intent == 'read_last_email' ||
        intent == 'search_emails') {
      return 'Verifică în Setări > Configurare Email dacă adresa și parola de aplicație sunt corecte.';
    }

    if (lowerReason.contains('acțiune necunoscută') ||
        lowerReason.contains('actiune necunoscuta')) {
      return 'Funcția nu este implementată încă în aplicație.';
    }

    if (intent == 'search_internet') {
      return 'Verifică conexiunea la internet și încearcă din nou.';
    }

    if (intent == 'compare_shopping_prices') {
      return 'Nu am găsit suficiente date live de preț acum. Încearcă din nou puțin mai târziu sau cu produse mai specifice.';
    }

    if (intent == 'schedule_meeting' ||
        intent == 'add_calendar_event' ||
        intent == 'cancel_calendar_event' ||
        intent == 'list_calendar_events') {
      return 'Verifică formatul datei/orei și permisiunile pentru calendar/notificări.';
    }

    return '';
  }

  String _stripLinks(String text) {
    final withoutUrls = text.replaceAll(
      RegExp(r'(https?://\S+|www\.\S+)', caseSensitive: false),
      '',
    );
    final withoutLinkLabels = withoutUrls.replaceAll(
      RegExp(r'\bLink\s*:\s*', caseSensitive: false),
      '',
    );
    return withoutLinkLabels
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  String _actionLabel(String intent) {
    switch (intent) {
      case 'send_email':
        return 'trimite emailul';
      case 'read_emails':
      case 'read_last_email':
      case 'search_emails':
        return 'accesa emailurile';
      case 'add_task':
      case 'list_tasks':
      case 'complete_task':
      case 'delete_task':
        return 'executa acțiunea pe task-uri';
      case 'add_shopping_item':
      case 'list_shopping':
      case 'remove_shopping_item':
        return 'executa acțiunea pe lista de cumpărături';
      case 'schedule_meeting':
      case 'add_calendar_event':
      case 'list_calendar_events':
      case 'cancel_calendar_event':
        return 'executa acțiunea din calendar';
      case 'search_internet':
        return 'face căutarea pe internet';
      case 'compare_shopping_prices':
        return 'compara prețurile live între magazine';
      case 'get_discounts':
        return 'căuta reducerile';
      default:
        return 'executa această acțiune';
    }
  }

  Future<String> _buildPersistentContext() async {
    try {
      final tasks = await _db.getAllTasks(completed: false);
      final shoppingItems = await _db.getAllShoppingItems(purchased: false);

      final taskSummary = tasks.isEmpty
          ? 'Nu există task-uri active.'
          : tasks.take(12).map((t) => t.title).join(', ');

      final shoppingSummary = shoppingItems.isEmpty
          ? 'Lista de cumpărături este goală.'
          : shoppingItems
                .take(20)
                .map((i) => '${i.name} (${i.quantity})')
                .join(', ');

      return '''
CONTEXT PERSISTENT DIN APLICAȚIE (actual, din baza locală):
- Task-uri active (${tasks.length}): $taskSummary
- Produse de cumpărat (${shoppingItems.length}): $shoppingSummary

Regulă: dacă utilizatorul întreabă ce are pe liste, folosește acest context actual fără să ceri repetarea informațiilor.
''';
    } catch (e) {
      return 'CONTEXT PERSISTENT indisponibil momentan: $e';
    }
  }

  Future<bool> startListening() async {
    if (!_isInitialized) await initialize();
    return await _stt.startListening();
  }

  Future<String?> stopListening() async {
    await _stt.stopListening();
    final result = _stt.getResult();
    return result.success ? result.text : null;
  }

  Future<void> speak(String text) async {
    if (!_isInitialized) await initialize();
    await _tts.speak(text);
  }

  Future<void> stopSpeaking() async {
    await _tts.stop();
  }

  Future<List<TaskItem>> getTasks({bool? completed}) async {
    final tasks = await _db.getAllTasks(completed: completed);
    return tasks
        .map(
          (t) => TaskItem(
            id: t.id.hashCode,
            title: t.title,
            description: t.description,
            dueDate: t.dueDate,
            priority: t.priority,
            category: t.category,
            isCompleted: t.isCompleted,
          ),
        )
        .toList();
  }

  Future<ShoppingList> getShoppingList({bool? purchased}) async {
    final items = await _db.getAllShoppingItems(purchased: purchased);
    final total = await _db.getShoppingListTotal();

    return ShoppingList(
      items: items
          .map(
            (i) => ShoppingItemUI(
              id: i.id.hashCode,
              name: i.name,
              quantity: i.quantity,
              category: i.category,
              isPurchased: i.isPurchased,
              notes: i.notes,
              priceEstimate: i.priceEstimate,
            ),
          )
          .toList(),
      count: items.length,
      totalEstimate: total,
    );
  }

  Future<String> createConversation({String? title}) async {
    final conversation = await _db.createConversation(title: title);
    _currentConversationId = conversation.id;
    _conversationHistory.clear();
    return conversation.id;
  }

  Future<void> switchConversation(String conversationId) async {
    _currentConversationId = conversationId;
    final conversation = await _db.getConversation(conversationId);
    if (conversation != null) {
      _conversationHistory = conversation.messages
          .map((m) => {'role': m.role, 'content': m.content})
          .toList();
    }
  }

  Future<List<Conversation>> getConversations() async {
    return await _db.getAllConversations();
  }

  Future<bool> checkHealth() async {
    return _isInitialized && _gemini.isInitialized;
  }

  void clearHistory() {
    _conversationHistory.clear();
  }

  void dispose() {
    _stt.dispose();
    _tts.dispose();
  }
}
