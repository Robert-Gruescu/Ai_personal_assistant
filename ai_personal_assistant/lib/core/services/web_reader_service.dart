// web_reader_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'gemini_service.dart';

class WebReaderService {
  static final WebReaderService _instance = WebReaderService._internal();
  factory WebReaderService() => _instance;
  WebReaderService._internal();

  final GeminiService _gemini = GeminiService();

  static String get _serperApiKey => dotenv.env['SERPER_API_KEY'] ?? '';
  static const String _serperScrapeUrl = 'https://scrape.serper.dev';

  // Site-uri care folosesc JavaScript rendering — prețurile nu apar în HTML static
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

  // Site-uri blocate — irelevante pentru prețuri/informații concrete
  static const List<String> _blockedDomains = [
    'tiktok.com',
    'youtube.com',
    't.co',
  ];

  bool _isJsRendered(String url) {
    final lower = url.toLowerCase();
    return _jsRenderedDomains.any((domain) => lower.contains(domain));
  }

  bool _isBlocked(String url) {
    final lower = url.toLowerCase();
    return _blockedDomains.any((domain) => lower.contains(domain));
  }

  /// Metodă principală — optimizată pentru minimum apeluri API:
  /// - Încearcă HTTP static gratuit întâi (0 credite Serper)
  /// - Dacă toate sunt JS-rendered, face 1 singur apel Serper Scrape
  /// - 1 singur apel Gemini pentru tot contextul combinat
  Future<String> readTopResultsForQuestion({
    required List<String> urls,
    required String question,
    int maxPages = 2,
  }) async {
    // Filtrează domeniile blocate
    final filteredUrls = urls.where((u) => !_isBlocked(u)).toList();

    if (filteredUrls.isEmpty) {
      print('⚠️ Toate URL-urile sunt blocate sau irelevante');
      return '';
    }

    final staticUrls = filteredUrls
        .where((u) => !_isJsRendered(u))
        .take(maxPages)
        .toList();

    final jsUrls = filteredUrls.where((u) => _isJsRendered(u)).take(1).toList();

    final textParts = <String>[];

    // PASUL 1: Fetch static (gratuit)
    for (final url in staticUrls) {
      print('📖 Static fetch: $url');
      final html = await _fetchHtml(url);
      if (html != null) {
        final text = _extractText(html);
        if (text.isNotEmpty) {
          textParts.add('Sursa: $url\n$text');
          if (textParts.length >= maxPages) break;
        }
      }
    }

    // PASUL 2: Dacă nu avem context, încearcă 1 singur JS-rendered cu Serper Scrape
    if (textParts.isEmpty && jsUrls.isNotEmpty) {
      final url = jsUrls.first;
      print('🔄 Serper Scrape (1 credit): $url');
      final html = await _fetchWithSerperScrape(url);
      if (html != null) {
        final text = _extractText(html);
        if (text.isNotEmpty) {
          textParts.add('Sursa: $url\n$text');
        }
      }
    }

    if (textParts.isEmpty) return '';

    // PASUL 3: UN SINGUR apel Gemini pentru tot contextul combinat
    final combinedText = textParts.join('\n\n---\n\n');
    final relevant = await _gemini.extractRelevantInfo(
      pageText: combinedText,
      question: question,
    );

    return relevant ?? '';
  }

  // ── SERPER SCRAPE API (costă credite — folosit doar ca fallback) ──────────

  Future<String?> _fetchWithSerperScrape(String url) async {
    if (_serperApiKey.isEmpty) return null;

    try {
      final response = await http
          .post(
            Uri.parse(_serperScrapeUrl),
            headers: {
              'X-API-KEY': _serperApiKey,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'url': url}),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final text = data['text'] as String?;
          if (text != null && text.trim().isNotEmpty) {
            print('✅ Serper Scrape OK: ${text.length} chars');
            return text;
          }
          final html = data['html'] as String?;
          if (html != null && html.trim().isNotEmpty) return html;
        } catch (_) {
          if (response.body.isNotEmpty) return response.body;
        }
      } else {
        print('⚠️ Serper Scrape: ${response.statusCode} pentru $url');
      }
    } catch (e) {
      print('⚠️ Serper Scrape error: $e');
    }

    return null;
  }

  // ── HTTP STATIC (gratuit) ─────────────────────────────────────────────────

  Future<String?> _fetchHtml(String url) async {
    try {
      final response = await http
          .get(
            Uri.parse(url),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
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

  // ── TEXT EXTRACTION ───────────────────────────────────────────────────────

  String _extractText(String html) {
    // Dacă e deja text simplu (de la Serper Scrape cu câmpul "text")
    if (!html.contains('<') || !html.contains('>')) {
      final cleaned = html
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceAll(RegExp(r'\n{3,}'), '\n\n')
          .trim();
      return cleaned.length > 6000 ? cleaned.substring(0, 6000) : cleaned;
    }

    String text = html
        .replaceAll(
          RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '')
        .replaceAll(
          RegExp(r'<(br|p|div|h[1-6]|li|tr)[^>]*>', caseSensitive: false),
          '\n',
        )
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&euro;', '€')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();

    return text.length > 6000 ? text.substring(0, 6000) : text;
  }
}
