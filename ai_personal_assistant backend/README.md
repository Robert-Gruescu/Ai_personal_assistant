# 🎙️ AI Personal Assistant Backend

Backend complet funcțional pentru aplicația mobilă Flutter - **Voice AI Personal Assistant**

## ✨ Caracteristici

- 🎤 **Speech-to-Text (STT)** - Convertește vocea în text
- 🔊 **Text-to-Speech (TTS)** - Răspunsuri vocale în limba română
- 🤖 **Google Gemini AI** - Conversații inteligente și naturale
- 📝 **Gestionare Task-uri** - Adaugă, completează, șterge sarcini
- 🛒 **Liste de Cumpărături** - Organizează cumpărăturile pe categorii
- 📧 **Agent Email** - Trimite emailuri prin comandă vocală
- 🔍 **Căutare Internet** - Informații în timp real de pe web
- 🐳 **Docker Ready** - Deploy rapid și simplu

## 🏗️ Arhitectură

```
ai_personal_assistant backend/
├── app/
│   ├── __init__.py
│   ├── config.py           # Configurări și variabile de mediu
│   ├── main.py              # Entry point FastAPI
│   ├── api/                 # Endpoints REST
│   │   ├── voice.py         # 🎤 Procesare vocală
│   │   ├── conversations.py # 💬 Istoric conversații
│   │   ├── tasks.py         # ✅ Gestionare sarcini
│   │   ├── shopping.py      # 🛒 Liste cumpărături
│   │   └── agent.py         # 🤖 Acțiuni agent
│   ├── ai/                  # Servicii AI
│   │   ├── gemini_service.py
│   │   └── search_service.py
│   ├── voice/               # Procesare audio
│   │   ├── speech_to_text.py
│   │   └── text_to_speech.py
│   ├── agent/               # Executor acțiuni
│   │   ├── email_service.py
│   │   └── action_executor.py
│   └── db/                  # Baza de date
│       ├── database.py
│       └── models.py
├── Dockerfile
├── docker-compose.yml
├── requirements.txt
└── .env.example
```

## 🚀 Instalare Rapidă

### Opțiunea 1: Docker (Recomandat)

```bash
# 1. Clonează și intră în folder
cd "ai_personal_assistant backend"

# 2. Copiază și configurează .env
cp .env.example .env
# Editează .env și adaugă GEMINI_API_KEY

# 3. Pornește cu Docker
docker-compose up -d

# Serverul rulează pe http://localhost:8000
```

### Opțiunea 2: Local (Development)

```bash
# 1. Creează virtual environment
python -m venv venv
venv\Scripts\activate  # Windows
# source venv/bin/activate  # Linux/Mac

# 2. Instalează dependențele
pip install -r requirements.txt

# 3. Instalează FFmpeg (necesar pentru audio)
# Windows: choco install ffmpeg
# Linux: apt-get install ffmpeg
# Mac: brew install ffmpeg

# 4. Configurează .env
cp .env.example .env
# Adaugă GEMINI_API_KEY în .env

# 5. Rulează serverul
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

## 🔑 Configurare API Keys

### Google Gemini (OBLIGATORIU)

1. Accesează https://makersuite.google.com/app/apikey
2. Creează un API key
3. Adaugă în `.env`: `GEMINI_API_KEY=your_key_here`

### SerpAPI (Opțional - pentru căutări)

1. Înregistrează-te pe https://serpapi.com/
2. Copiază API key-ul
3. Adaugă în `.env`: `SERPAPI_KEY=your_key`

> Fără SerpAPI, se folosește DuckDuckGo gratuit ca fallback

### Gmail SMTP (Opțional - pentru email)

1. Activează 2FA pe contul Google
2. Creează App Password: https://myaccount.google.com/apppasswords
3. Configurează în `.env`:

```
SMTP_USER=your_email@gmail.com
SMTP_PASSWORD=your_app_password
```

## 📡 API Endpoints

### 🎤 Voice Processing

| Endpoint                    | Metodă | Descriere                                            |
| --------------------------- | ------ | ---------------------------------------------------- |
| `/api/voice/process`        | POST   | **Pipeline complet**: Audio → STT → AI → TTS → Audio |
| `/api/voice/speech-to-text` | POST   | Convertește audio în text                            |
| `/api/voice/text-to-speech` | POST   | Convertește text în audio                            |
| `/api/voice/chat`           | POST   | Chat text (fallback)                                 |

### 💬 Conversations

| Endpoint                  | Metodă | Descriere                |
| ------------------------- | ------ | ------------------------ |
| `/api/conversations`      | GET    | Lista conversațiilor     |
| `/api/conversations/{id}` | GET    | Detalii conversație      |
| `/api/conversations`      | POST   | Creează conversație nouă |
| `/api/conversations/{id}` | DELETE | Șterge conversație       |

### ✅ Tasks

| Endpoint                   | Metodă | Descriere            |
| -------------------------- | ------ | -------------------- |
| `/api/tasks`               | GET    | Lista sarcinilor     |
| `/api/tasks`               | POST   | Adaugă sarcină       |
| `/api/tasks/{id}`          | PUT    | Actualizează sarcină |
| `/api/tasks/{id}`          | DELETE | Șterge sarcină       |
| `/api/tasks/{id}/complete` | POST   | Marchează completată |

### 🛒 Shopping

| Endpoint                        | Metodă | Descriere             |
| ------------------------------- | ------ | --------------------- |
| `/api/shopping`                 | GET    | Lista cumpărături     |
| `/api/shopping`                 | POST   | Adaugă item           |
| `/api/shopping/{id}`            | PUT    | Actualizează item     |
| `/api/shopping/{id}`            | DELETE | Șterge item           |
| `/api/shopping/{id}/purchase`   | POST   | Marchează cumpărat    |
| `/api/shopping/clear-purchased` | POST   | Șterge cele cumpărate |

### 🤖 Agent

| Endpoint             | Metodă | Descriere        |
| -------------------- | ------ | ---------------- |
| `/api/agent/email`   | POST   | Trimite email    |
| `/api/agent/search`  | POST   | Căutare internet |
| `/api/agent/history` | GET    | Istoric acțiuni  |

## 📱 Integrare Flutter

### 1. Adaugă dependențele în `pubspec.yaml`:

```yaml
dependencies:
  http: ^1.2.0
  record: ^5.0.4 # Înregistrare audio
  audioplayers: ^5.2.1 # Redare audio
  path_provider: ^2.1.2
  permission_handler: ^11.3.0
```

### 2. Service pentru comunicare cu backend-ul:

```dart
// lib/services/assistant_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class AssistantService {
  // Schimbă cu IP-ul serverului tău
  // Pentru emulator Android: 10.0.2.2
  // Pentru dispozitiv fizic: IP-ul calculatorului
  static const String baseUrl = 'http://10.0.2.2:8000';

  /// Procesează audio și primește răspuns vocal
  Future<Map<String, dynamic>> processVoice(File audioFile) async {
    final uri = Uri.parse('$baseUrl/api/voice/process');

    final request = http.MultipartRequest('POST', uri);
    request.files.add(
      await http.MultipartFile.fromPath('audio', audioFile.path),
    );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      return json.decode(response.body);
      // Răspuns include:
      // - transcription: textul recunoscut
      // - response: răspunsul AI
      // - audio: audio în base64
      // - action: acțiunea executată (dacă există)
    } else {
      throw Exception('Error: ${response.body}');
    }
  }

  /// Chat text (fără voce)
  Future<Map<String, dynamic>> sendMessage(String message) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/voice/chat'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'text': message}),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Error: ${response.body}');
    }
  }

  /// Obține lista de task-uri
  Future<List<dynamic>> getTasks({bool? completed}) async {
    String url = '$baseUrl/api/tasks';
    if (completed != null) {
      url += '?completed=$completed';
    }

    final response = await http.get(Uri.parse(url));
    final data = json.decode(response.body);
    return data['tasks'];
  }

  /// Obține lista de cumpărături
  Future<Map<String, dynamic>> getShoppingList() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/shopping'),
    );
    return json.decode(response.body);
  }
}
```

### 3. Widget pentru înregistrare vocală:

```dart
// lib/widgets/voice_button.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import '../services/assistant_service.dart';

class VoiceButton extends StatefulWidget {
  final Function(String, String)? onResponse;

  const VoiceButton({super.key, this.onResponse});

  @override
  State<VoiceButton> createState() => _VoiceButtonState();
}

class _VoiceButtonState extends State<VoiceButton> {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  final AssistantService _service = AssistantService();

  bool _isRecording = false;
  bool _isProcessing = false;
  String? _recordingPath;

  @override
  void dispose() {
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) {
      return;
    }

    final dir = await getTemporaryDirectory();
    _recordingPath = '${dir.path}/recording.wav';

    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.wav),
      path: _recordingPath!,
    );

    setState(() => _isRecording = true);
  }

  Future<void> _stopRecording() async {
    await _recorder.stop();
    setState(() {
      _isRecording = false;
      _isProcessing = true;
    });

    try {
      final file = File(_recordingPath!);
      final result = await _service.processVoice(file);

      // Redă răspunsul audio
      if (result['audio'] != null) {
        final bytes = base64Decode(result['audio']);
        await _player.play(BytesSource(bytes));
      }

      // Callback cu transcrierea și răspunsul
      widget.onResponse?.call(
        result['transcription'] ?? '',
        result['response'] ?? '',
      );
    } catch (e) {
      debugPrint('Error: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (_) => _startRecording(),
      onLongPressEnd: (_) => _stopRecording(),
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _isRecording
            ? Colors.red
            : (_isProcessing ? Colors.orange : Colors.blue),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Icon(
          _isRecording
            ? Icons.mic
            : (_isProcessing ? Icons.hourglass_empty : Icons.mic_none),
          color: Colors.white,
          size: 40,
        ),
      ),
    );
  }
}
```

### 4. Exemplu de utilizare în screen:

```dart
// lib/screens/assistant_screen.dart
import 'package:flutter/material.dart';
import '../widgets/voice_button.dart';

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final List<ChatMessage> _messages = [];

  void _onResponse(String userText, String assistantText) {
    setState(() {
      _messages.add(ChatMessage(text: userText, isUser: true));
      _messages.add(ChatMessage(text: assistantText, isUser: false));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ASIS - Asistentul Tău')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              reverse: true,
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[_messages.length - 1 - index];
                return Align(
                  alignment: msg.isUser
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.all(8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: msg.isUser ? Colors.blue : Colors.grey[300],
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      msg.text,
                      style: TextStyle(
                        color: msg.isUser ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: VoiceButton(onResponse: _onResponse),
          ),
        ],
      ),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;

  ChatMessage({required this.text, required this.isUser});
}
```

## 🎯 Comenzi Vocale Suportate

Asistentul ASIS înțelege comenzi în limba română:

### Task-uri

- "Adaugă task: să merg la doctor mâine"
- "Ce sarcini am de făcut?"
- "Arată-mi taskurile incomplete"
- "Șterge toate taskurile completate"

### Cumpărături

- "Adaugă pe lista de cumpărături: lapte și pâine"
- "Ce am de cumpărat?"
- "Șterge laptele de pe listă"

### Email

- "Trimite un email lui ion@email.com cu subiectul Întâlnire"

### Căutări

- "Caută pe internet vremea în București"
- "Ce știri sunt azi?"

### Conversație

- Orice întrebare generală va primi răspuns de la AI

## 🔧 Debugging

### Verifică dacă serverul rulează:

```bash
curl http://localhost:8000/health
# Răspuns: {"status": "healthy", "version": "1.0.0"}
```

### Testează pipeline-ul vocal:

```bash
# Test STT
curl -X POST http://localhost:8000/api/voice/speech-to-text \
  -F "audio=@test_audio.wav"

# Test TTS
curl -X POST http://localhost:8000/api/voice/text-to-speech \
  -H "Content-Type: application/json" \
  -d '{"text": "Bună ziua!"}' \
  --output response.mp3
```

### Logs Docker:

```bash
docker-compose logs -f assistant-backend
```

## 📝 Note Importante

1. **Audio Format**: Serverul acceptă WAV, MP3, WEBM, OGG
2. **Limba**: Configurată implicit pentru Română (ro-RO)
3. **FFmpeg**: Necesar pentru procesarea audio
4. **CORS**: Activat pentru toate originile (development)

## 🐛 Probleme Comune

### "Microfonul nu funcționează"

- Verifică permisiunile în app
- Android: `RECORD_AUDIO`, `INTERNET`
- iOS: `NSMicrophoneUsageDescription`

### "Connection refused"

- Verifică dacă serverul rulează
- Pentru Android emulator folosește `10.0.2.2` în loc de `localhost`
- Verifică firewall-ul

### "No module named 'google.generativeai'"

```bash
pip install google-generativeai
```

---

**Backend creat pentru aplicația AI Personal Assistant Flutter** 🚀
