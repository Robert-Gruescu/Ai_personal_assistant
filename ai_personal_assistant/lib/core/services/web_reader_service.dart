// web_reader_service.dart

import 'package:http/http.dart' as http;
import 'gemini_service.dart';

class WebReaderService {
  static final WebReaderService _instance = WebReaderService._internal();
  factory WebReaderService() => _instance;
  WebReaderService._internal();

  final GeminiService _gemini = GeminiService();

  // Domenii care folosesc JavaScript rendering — prețurile nu apar în HTML static
  static const List<String> _jsRenderedDomains = [
    'lidl.ro',
    'kaufland.ro',
    'carrefour.ro',
    'auchan.ro',
    'mega-image.ro',
    'profi.ro',
    'penny.ro',
    'selgros.ro',
    'metro.ro',
  ];

  bool _isJsRendered(String url) {
    final lower = url.toLowerCase();
    return _jsRenderedDomains.any((domain) => lower.contains(domain));
  }

  /// Fetch + extrage text relevant din pagină față de întrebare
  Future<String?> readPageForQuestion({
    required String url,
    required String question,
  }) async {
    try {
      // Sari peste site-urile care folosesc JS rendering
      if (_isJsRendered(url)) {
        print('⏭️ Skipping JS-rendered site: $url');
        return null;
      }

      final html = await _fetchHtml(url);
      if (html == null) return null;

      final text = _extractText(html);
      if (text.isEmpty) return null;

      // Trimite textul paginii + întrebarea la Gemini să extragă ce e relevant
      final response = await _gemini.extractRelevantInfo(
        pageText: text,
        question: question,
        sourceUrl: url,
      );

      return response;
    } catch (e) {
      print('⚠️ WebReader error for $url: $e');
      return null;
    }
  }

  /// Citește primele N pagini din rezultate și combină informațiile.
  /// Ia mai multe URL-uri decât maxPages ca să compenseze skip-urile.
  Future<String> readTopResultsForQuestion({
    required List<String> urls,
    required String question,
    int maxPages = 2,
  }) async {
    final results = <String>[];
    // Luăm maxPages + 3 URL-uri extra ca să avem suficiente după ce sărim JS-rendered
    final candidates = urls.take(maxPages + 3).toList();

    for (final url in candidates) {
      if (results.length >= maxPages) break;

      if (_isJsRendered(url)) {
        print('⏭️ Skipping JS-rendered: $url');
        continue;
      }

      print('📖 Reading: $url');
      final content = await readPageForQuestion(url: url, question: question);
      if (content != null && content.trim().isNotEmpty) {
        results.add(content);
      }
    }

    if (results.isEmpty) return '';
    return results.join('\n\n---\n\n');
  }

  Future<String?> _fetchHtml(String url) async {
    try {
      final response = await http
          .get(
            Uri.parse(url),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
              'Accept': 'text/html,application/xhtml+xml',
              'Accept-Language': 'ro-RO,ro;q=0.9,en;q=0.8',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) return response.body;
      print('⚠️ HTTP ${response.statusCode} for $url');
      return null;
    } catch (e) {
      print('⚠️ Fetch error for $url: $e');
      return null;
    }
  }

  String _extractText(String html) {
    String text = html
        // Elimină scripturi și stiluri
        .replaceAll(
          RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false),
          '',
        )
        // Elimină comentarii HTML
        .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '')
        // Păstrează newline la taguri de bloc
        .replaceAll(
          RegExp(r'<(br|p|div|h[1-6]|li|tr)[^>]*>', caseSensitive: false),
          '\n',
        )
        // Elimină toate tagurile rămase
        .replaceAll(RegExp(r'<[^>]+>'), '')
        // Decodează entități HTML comune
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&euro;', '€')
        .replaceAll('&lei;', 'lei')
        // Curăță spații multiple
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();

    // Limitează la 8000 caractere — suficient pentru Gemini
    return text.length > 8000 ? text.substring(0, 8000) : text;
  }
}
