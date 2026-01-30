import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class AssistantService {
  // Pentru Windows/Desktop - folosește localhost
  // Pentru Android Emulator - folosește 10.0.2.2
  // Pentru dispozitiv fizic - folosește IP-ul calculatorului
  static const String baseUrl = 'http://localhost:8000';

  /// Procesează audio complet: Audio → STT → AI → TTS → Audio
  Future<VoiceResponse> processVoice(File audioFile) async {
    try {
      final uri = Uri.parse('$baseUrl/api/voice/process');

      final request = http.MultipartRequest('POST', uri);
      request.files.add(
        await http.MultipartFile.fromPath('audio', audioFile.path),
      );
      // Specify audio format
      request.fields['audio_format'] = 'wav';

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 60),
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final bool isSuccess = data['success'] ?? true;
        final String? errorMsg = data['error'] as String?;

        return VoiceResponse(
          transcription: data['transcription'] ?? data['user_text'] ?? '',
          response: data['response'] ?? data['response_text'] ?? '',
          audioBase64: data['audio'] ?? data['audio_base64'],
          action: data['action'] ?? data['action_result'],
          success: isSuccess,
          error: errorMsg ?? (isSuccess ? null : 'Eroare necunoscută'),
        );
      } else {
        String errorMsg = 'Eroare server: ${response.statusCode}';
        try {
          final error = json.decode(response.body);
          errorMsg = error['detail'] ?? error['error'] ?? errorMsg;
        } catch (_) {}
        return VoiceResponse(
          transcription: '',
          response: errorMsg,
          success: false,
          error: errorMsg,
        );
      }
    } catch (e) {
      return VoiceResponse(
        transcription: '',
        response: 'Eroare de conexiune: $e',
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Chat text (fallback când nu merge audio)
  Future<ChatResponse> sendMessage(
    String message, {
    String? conversationId,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/voice/chat'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'text': message,
              if (conversationId != null)
                'conversation_id': int.tryParse(conversationId),
            }),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return ChatResponse(
          response: data['response'] ?? data['response_text'] ?? '',
          audioBase64: data['audio'] ?? data['audio_base64'],
          action: data['action'] ?? data['action_result'],
          conversationId: data['conversation_id']?.toString(),
          success: data['success'] ?? true,
        );
      } else {
        return ChatResponse(
          response: 'Eroare: ${response.body}',
          success: false,
        );
      }
    } catch (e) {
      return ChatResponse(response: 'Eroare de conexiune: $e', success: false);
    }
  }

  /// Text to Speech - returnează base64 audio
  Future<String?> textToSpeech(String text) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/voice/text-to-speech-base64'),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: {'text': text},
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['audio'] ?? data['audio_base64'];
      }
      return null;
    } catch (e) {
      print('TTS Error: $e');
      return null;
    }
  }

  /// Obține lista de task-uri
  Future<List<TaskItem>> getTasks({bool? completed}) async {
    try {
      String url = '$baseUrl/api/tasks';
      if (completed != null) {
        url += '?completed=$completed';
      }

      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List tasks = data['tasks'] ?? [];
        return tasks.map((t) => TaskItem.fromJson(t)).toList();
      }
      return [];
    } catch (e) {
      print('Get tasks error: $e');
      return [];
    }
  }

  /// Obține lista de cumpărături
  Future<ShoppingList> getShoppingList({bool? purchased}) async {
    try {
      String url = '$baseUrl/api/shopping';
      if (purchased != null) {
        url += '?purchased=$purchased';
      }

      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return ShoppingList.fromJson(data);
      }
      return ShoppingList(items: [], count: 0, totalEstimate: 0);
    } catch (e) {
      print('Get shopping list error: $e');
      return ShoppingList(items: [], count: 0, totalEstimate: 0);
    }
  }

  /// Verifică dacă serverul este online
  Future<bool> checkHealth() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      print('Health check failed: $e');
      return false;
    }
  }
}

// === MODELE DE DATE ===

class VoiceResponse {
  final String transcription;
  final String response;
  final String? audioBase64;
  final Map<String, dynamic>? action;
  final bool success;
  final String? error;

  VoiceResponse({
    required this.transcription,
    required this.response,
    this.audioBase64,
    this.action,
    required this.success,
    this.error,
  });
}

class ChatResponse {
  final String response;
  final String? audioBase64;
  final Map<String, dynamic>? action;
  final String? conversationId;
  final bool success;

  ChatResponse({
    required this.response,
    this.audioBase64,
    this.action,
    this.conversationId,
    required this.success,
  });
}

class TaskItem {
  final int id;
  final String title;
  final String? description;
  final bool isCompleted;
  final String? dueDate;
  final String? priority;

  TaskItem({
    required this.id,
    required this.title,
    this.description,
    required this.isCompleted,
    this.dueDate,
    this.priority,
  });

  factory TaskItem.fromJson(Map<String, dynamic> json) {
    return TaskItem(
      id: json['id'],
      title: json['title'],
      description: json['description'],
      isCompleted: json['is_completed'] ?? false,
      dueDate: json['due_date'],
      priority: json['priority'],
    );
  }
}

class ShoppingItem {
  final int id;
  final String name;
  final String quantity;
  final String? category;
  final bool isPurchased;
  final double? priceEstimate;

  ShoppingItem({
    required this.id,
    required this.name,
    required this.quantity,
    this.category,
    required this.isPurchased,
    this.priceEstimate,
  });

  factory ShoppingItem.fromJson(Map<String, dynamic> json) {
    return ShoppingItem(
      id: json['id'],
      name: json['name'],
      quantity: json['quantity'] ?? '1',
      category: json['category'],
      isPurchased: json['is_purchased'] ?? false,
      priceEstimate: json['price_estimate']?.toDouble(),
    );
  }
}

class ShoppingList {
  final List<ShoppingItem> items;
  final int count;
  final double totalEstimate;

  ShoppingList({
    required this.items,
    required this.count,
    required this.totalEstimate,
  });

  factory ShoppingList.fromJson(Map<String, dynamic> json) {
    final List itemsList = json['items'] ?? [];
    return ShoppingList(
      items: itemsList.map((i) => ShoppingItem.fromJson(i)).toList(),
      count: json['count'] ?? 0,
      totalEstimate: (json['total_estimate'] ?? 0).toDouble(),
    );
  }
}
