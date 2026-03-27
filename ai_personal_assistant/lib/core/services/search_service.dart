import 'dart:convert';
import 'package:http/http.dart' as http;

/// Search result from the internet
class SearchResult {
  final String title;
  final String snippet;
  final String link;

  SearchResult({
    required this.title,
    required this.snippet,
    required this.link,
  });

  factory SearchResult.fromJson(Map<String, dynamic> json) {
    return SearchResult(
      title: json['title'] ?? '',
      snippet: json['snippet'] ?? json['body'] ?? '',
      link: json['link'] ?? json['href'] ?? json['url'] ?? '',
    );
  }
}

/// Search response
class SearchResponse {
  final bool success;
  final String query;
  final String? directAnswer;
  final List<SearchResult> results;
  final String? error;

  SearchResponse({
    required this.success,
    required this.query,
    this.directAnswer,
    required this.results,
    this.error,
  });

  factory SearchResponse.error(String query, String errorMessage) {
    return SearchResponse(
      success: false,
      query: query,
      results: [],
      error: errorMessage,
    );
  }

  String formatForAI() {
    if (!success || results.isEmpty) {
      return 'Nu am găsit rezultate pentru: $query';
    }

    final buffer = StringBuffer();
    if (directAnswer != null && directAnswer!.isNotEmpty) {
      buffer.writeln('Răspuns direct: $directAnswer');
      buffer.writeln();
    }

    buffer.writeln('Rezultate căutare pentru "$query":');
    buffer.writeln();

    for (int i = 0; i < results.length && i < 5; i++) {
      final result = results[i];
      buffer.writeln('${i + 1}. ${result.title}');
      buffer.writeln('   ${result.snippet}');
      buffer.writeln('   Link: ${result.link}');
      buffer.writeln();
    }

    return buffer.toString();
  }
}

class StorePriceMatch {
  final String item;
  final String store;
  final double price;
  final String sourceTitle;
  final String sourceLink;

  StorePriceMatch({
    required this.item,
    required this.store,
    required this.price,
    required this.sourceTitle,
    required this.sourceLink,
  });

  Map<String, dynamic> toJson() => {
    'item': item,
    'store': store,
    'price': price,
    'source_title': sourceTitle,
    'source_link': sourceLink,
  };
}

class StorePriceSummary {
  final String store;
  final double estimatedTotal;
  final int matchedItems;
  final int missingItems;

  StorePriceSummary({
    required this.store,
    required this.estimatedTotal,
    required this.matchedItems,
    required this.missingItems,
  });

  Map<String, dynamic> toJson() => {
    'store': store,
    'estimated_total': estimatedTotal,
    'matched_items': matchedItems,
    'missing_items': missingItems,
  };
}

class ShoppingPriceComparisonResponse {
  final bool success;
  final String? recommendedStore;
  final String? rationale;
  final List<StorePriceSummary> storeSummaries;
  final List<StorePriceMatch> matchedPrices;
  final List<String> scannedItems;
  final String? error;

  ShoppingPriceComparisonResponse({
    required this.success,
    this.recommendedStore,
    this.rationale,
    required this.storeSummaries,
    required this.matchedPrices,
    required this.scannedItems,
    this.error,
  });

  factory ShoppingPriceComparisonResponse.error(String message) {
    return ShoppingPriceComparisonResponse(
      success: false,
      storeSummaries: const [],
      matchedPrices: const [],
      scannedItems: const [],
      error: message,
    );
  }

  Map<String, dynamic> toJson() => {
    'success': success,
    'recommended_store': recommendedStore,
    'rationale': rationale,
    'store_summaries': storeSummaries.map((s) => s.toJson()).toList(),
    'matched_prices': matchedPrices.map((m) => m.toJson()).toList(),
    'scanned_items': scannedItems,
    'error': error,
  };
}

/// Internet Search Service using DuckDuckGo
class SearchService {
  static final SearchService _instance = SearchService._internal();
  factory SearchService() => _instance;
  SearchService._internal();

  static const String _duckDuckGoInstantUrl = 'https://api.duckduckgo.com/';
  static const String _duckDuckGoHtmlUrl = 'https://html.duckduckgo.com/html/';

  static const List<String> _defaultStores = [
    'Lidl',
    'Kaufland',
    'Carrefour',
    'Auchan',
  ];

  /// Search the internet for information
  Future<SearchResponse> search(String query, {int numResults = 5}) async {
    try {
      print('🔍 Searching for: $query');

      // Try DuckDuckGo Instant Answer API first
      final instantResult = await _searchDuckDuckGoInstant(query);
      if (instantResult != null && instantResult.isNotEmpty) {
        return SearchResponse(
          success: true,
          query: query,
          directAnswer: instantResult,
          results: [],
        );
      }

      // Try scraping DuckDuckGo HTML results
      final results = await _searchDuckDuckGoHtml(query, numResults);

      if (results.isNotEmpty) {
        return SearchResponse(success: true, query: query, results: results);
      }

      // Fallback: Try Google Custom Search if available
      // For now, return empty results
      return SearchResponse(
        success: false,
        query: query,
        results: [],
        error: 'Nu am putut găsi rezultate pentru această căutare.',
      );
    } catch (e) {
      print('❌ Search error: $e');
      return SearchResponse.error(query, e.toString());
    }
  }

  /// Search using DuckDuckGo Instant Answer API
  Future<String?> _searchDuckDuckGoInstant(String query) async {
    try {
      final uri = Uri.parse(_duckDuckGoInstantUrl).replace(
        queryParameters: {
          'q': query,
          'format': 'json',
          'no_redirect': '1',
          'no_html': '1',
        },
      );

      final response = await http
          .get(
            uri,
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Check for Abstract (main answer)
        final abstract = data['Abstract'] as String?;
        if (abstract != null && abstract.isNotEmpty) {
          return abstract;
        }

        // Check for Answer
        final answer = data['Answer'] as String?;
        if (answer != null && answer.isNotEmpty) {
          return answer;
        }

        // Check for Definition
        final definition = data['Definition'] as String?;
        if (definition != null && definition.isNotEmpty) {
          return definition;
        }
      }

      return null;
    } catch (e) {
      print('⚠️ DuckDuckGo Instant API error: $e');
      return null;
    }
  }

  /// Search using DuckDuckGo HTML (web scraping)
  Future<List<SearchResult>> _searchDuckDuckGoHtml(
    String query,
    int numResults,
  ) async {
    try {
      final uri = Uri.parse(_duckDuckGoHtmlUrl);

      final response = await http
          .post(
            uri,
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: {'q': query, 'kl': 'ro-ro'},
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return _parseHtmlResults(response.body, numResults);
      }

      return [];
    } catch (e) {
      print('⚠️ DuckDuckGo HTML search error: $e');
      return [];
    }
  }

  /// Parse HTML search results
  List<SearchResult> _parseHtmlResults(String html, int maxResults) {
    final results = <SearchResult>[];

    try {
      // Simple regex-based parsing for DuckDuckGo HTML results
      // Pattern for result titles and snippets
      final titlePattern = RegExp(
        r'<a[^>]*class="[^"]*result__a[^"]*"[^>]*href="([^"]*)"[^>]*>([\s\S]*?)</a>',
      );
      final snippetPattern = RegExp(
        r'<a[^>]*class="[^"]*result__snippet[^"]*"[^>]*>([\s\S]*?)</a>',
      );

      final titleMatches = titlePattern.allMatches(html).toList();
      final snippetMatches = snippetPattern.allMatches(html).toList();

      final count = titleMatches.length < snippetMatches.length
          ? titleMatches.length
          : snippetMatches.length;

      for (int i = 0; i < count && i < maxResults; i++) {
        final titleMatch = titleMatches[i];
        final snippetMatch = snippetMatches[i];

        String url = titleMatch.group(1) ?? '';
        String title = _cleanHtml(titleMatch.group(2) ?? '');
        String snippet = _cleanHtml(snippetMatch.group(1) ?? '');

        // Skip ad results
        if (url.contains('duckduckgo.com') || url.isEmpty) continue;

        // Decode URL
        if (url.startsWith('//duckduckgo.com/l/?uddg=')) {
          url = Uri.decodeFull(
            url.replaceFirst('//duckduckgo.com/l/?uddg=', ''),
          );
          final ampIndex = url.indexOf('&');
          if (ampIndex > 0) {
            url = url.substring(0, ampIndex);
          }
        }

        if (title.isNotEmpty && url.isNotEmpty) {
          results.add(SearchResult(title: title, snippet: snippet, link: url));
        }
      }
    } catch (e) {
      print('⚠️ HTML parsing error: $e');
    }

    return results;
  }

  /// Clean HTML tags from string
  String _cleanHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Search for news articles
  Future<SearchResponse> searchNews(String query, {int numResults = 5}) async {
    // Add "news" or "știri" to the query for news results
    final newsQuery = '$query știri ultimele';
    return search(newsQuery, numResults: numResults);
  }

  /// Compare live prices for a shopping list across stores.
  /// Uses live web snippets, so results are estimates and depend on available indexed offers.
  Future<ShoppingPriceComparisonResponse> compareShoppingListPrices(
    List<String> items, {
    List<String>? stores,
  }) async {
    final cleanItems = items
        .map((i) => i.trim())
        .where((i) => i.isNotEmpty)
        .toSet()
        .toList();

    if (cleanItems.isEmpty) {
      return ShoppingPriceComparisonResponse.error(
        'Lista de produse este goală.',
      );
    }

    final scanItems = cleanItems.take(8).toList();
    final scanStores = (stores == null || stores.isEmpty)
        ? _defaultStores
        : stores.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

    if (scanStores.isEmpty) {
      return ShoppingPriceComparisonResponse.error(
        'Nu am magazine pentru comparație.',
      );
    }

    try {
      final matches = <StorePriceMatch>[];

      for (final item in scanItems) {
        for (final store in scanStores) {
          final match = await _findLivePrice(item: item, store: store);
          if (match != null) {
            matches.add(match);
          }
        }
      }

      if (matches.isEmpty) {
        return ShoppingPriceComparisonResponse.error(
          'Nu am găsit suficiente prețuri live pentru comparație acum.',
        );
      }

      final summaries = <StorePriceSummary>[];
      for (final store in scanStores) {
        final storeMatches = matches.where((m) => m.store == store).toList();
        final total = storeMatches.fold<double>(0, (sum, m) => sum + m.price);
        final matchedCount = storeMatches.length;
        final missingCount = scanItems.length - matchedCount;

        // Penalize missing prices to avoid over-favoring stores with partial data.
        final penalty = missingCount * 12.0;
        summaries.add(
          StorePriceSummary(
            store: store,
            estimatedTotal: total + penalty,
            matchedItems: matchedCount,
            missingItems: missingCount,
          ),
        );
      }

      summaries.sort((a, b) => a.estimatedTotal.compareTo(b.estimatedTotal));
      final best = summaries.first;

      final bestMatches = matches.where((m) => m.store == best.store).toList()
        ..sort((a, b) => a.price.compareTo(b.price));

      final highlighted = bestMatches.take(3).map((m) => m.item).toList();
      final rationale = highlighted.isNotEmpty
          ? 'Estimarea cea mai bună este la ${best.store}. Produse avantajoase acum: ${highlighted.join(', ')}.'
          : 'Estimarea totală cea mai bună este la ${best.store}.';

      return ShoppingPriceComparisonResponse(
        success: true,
        recommendedStore: best.store,
        rationale: rationale,
        storeSummaries: summaries,
        matchedPrices: matches,
        scannedItems: scanItems,
      );
    } catch (e) {
      return ShoppingPriceComparisonResponse.error(
        'Eroare la compararea prețurilor live: $e',
      );
    }
  }

  Future<StorePriceMatch?> _findLivePrice({
    required String item,
    required String store,
  }) async {
    final query = '$item preț $store România reducere săptămâna aceasta';
    final results = await _searchDuckDuckGoHtml(query, 5);

    for (final result in results) {
      final price = _extractPrice('${result.title} ${result.snippet}');
      if (price != null) {
        return StorePriceMatch(
          item: item,
          store: store,
          price: price,
          sourceTitle: result.title,
          sourceLink: result.link,
        );
      }
    }

    return null;
  }

  double? _extractPrice(String text) {
    final normalized = text.toLowerCase().replaceAll(',', '.');

    final withCurrency = RegExp(
      r'(\d{1,4}(?:\.\d{1,2})?)\s*(lei|ron|r\.?o\.?n\.?)',
      caseSensitive: false,
    );
    final currencyMatch = withCurrency.firstMatch(normalized);
    if (currencyMatch != null) {
      final value = double.tryParse(currencyMatch.group(1)!);
      if (value != null && value > 0 && value < 5000) {
        return value;
      }
    }

    final generic = RegExp(r'\b(\d{1,3}(?:\.\d{1,2})?)\b');
    final genericMatches = generic.allMatches(normalized).toList();
    for (final match in genericMatches) {
      final value = double.tryParse(match.group(1)!);
      if (value != null && value >= 1 && value <= 1000) {
        return value;
      }
    }

    return null;
  }
}
