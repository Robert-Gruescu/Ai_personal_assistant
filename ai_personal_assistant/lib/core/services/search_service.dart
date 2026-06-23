import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'discount_service.dart' show DiscountService;

// ─────────────────────────────────────────────────────────────────────────────
// CONFIGURARE
// ─────────────────────────────────────────────────────────────────────────────
//
// Motor principal: Magazin propriu (Supabase) — prețuri reale, fără credite
// Fallback: Serper.dev — pentru căutări generale pe internet
//
// În fișierul .env:
//   SERPER_API_KEY=cheia_ta_serper
//
// ─────────────────────────────────────────────────────────────────────────────

/// Produs din magazinul propriu
class ShopProduct {
  final int id;
  final String name;
  final String description;
  final double price;
  final String imageUrl;
  final int categoryId;
  final bool faraZahar;
  final bool bio;
  final int stock;

  ShopProduct({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.imageUrl,
    required this.categoryId,
    required this.faraZahar,
    required this.bio,
    required this.stock,
  });

  factory ShopProduct.fromJson(Map<String, dynamic> json) {
    return ShopProduct(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      price: (json['price'] ?? 0).toDouble(),
      imageUrl: json['image_url'] ?? '',
      categoryId: json['category_id'] ?? 0,
      faraZahar: json['fara_zahar'] ?? false,
      bio: json['bio'] ?? false,
      stock: json['stock'] ?? 0,
    );
  }

  /// Formatează produsul pentru AI
  String toAIString() {
    final extras = <String>[];
    if (faraZahar) extras.add('fără zahăr');
    if (bio) extras.add('bio');
    if (stock == 0) extras.add('stoc epuizat');

    return '${name}: ${price.toStringAsFixed(2)} lei'
        '${extras.isNotEmpty ? ' (${extras.join(', ')})' : ''}'
        ' — $description';
  }
}

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

  // Produse găsite în magazinul propriu
  final List<ShopProduct> shopProducts;

  SearchResponse({
    required this.success,
    required this.query,
    this.directAnswer,
    required this.results,
    this.error,
    this.shopProducts = const [],
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
    if (!success &&
        shopProducts.isEmpty &&
        (results.isEmpty && (directAnswer == null || directAnswer!.isEmpty))) {
      return 'Nu am găsit rezultate pentru: $query';
    }

    final buffer = StringBuffer();

    // Produse din magazinul propriu — prioritate maximă
    if (shopProducts.isNotEmpty) {
      buffer.writeln('Produse găsite în magazin pentru "$query":');
      buffer.writeln();
      for (final p in shopProducts.take(5)) {
        buffer.writeln('• ${p.toAIString()}');
      }
      buffer.writeln();
    }

    // Răspuns direct din internet
    if (directAnswer != null && directAnswer!.isNotEmpty) {
      buffer.writeln('Răspuns direct: $directAnswer');
      buffer.writeln();
    }

    // Rezultate internet
    if (results.isNotEmpty) {
      buffer.writeln('Rezultate căutare pentru "$query":');
      buffer.writeln();
      for (int i = 0; i < results.length && i < 5; i++) {
        final result = results[i];
        buffer.writeln('${i + 1}. ${result.title}');
        buffer.writeln('   ${result.snippet}');
        buffer.writeln();
      }
    }

    return buffer.toString();
  }
}

class CatalogPdfInfo {
  final String title;
  final String link;
  CatalogPdfInfo({required this.title, required this.link});
}

class ImageDownload {
  final Uint8List bytes;
  final String mimeType;
  ImageDownload({required this.bytes, required this.mimeType});
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

/// Internet Search Service
/// Motor principal: Magazin propriu (Supabase) — prețuri reale, fără credite
/// Fallback: Serper.dev — pentru căutări generale
class SearchService {
  static final SearchService _instance = SearchService._internal();
  factory SearchService() => _instance;
  SearchService._internal();

  // ── Supabase config ───────────────────────────────────────────────────────
  static String get _supabaseUrl => dotenv.env['SUPABASE_URL'] ?? '';
  static String get _supabaseAnonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? '';

  // ── Serper config ─────────────────────────────────────────────────────────
  static String get _serperApiKey => dotenv.env['SERPER_API_KEY'] ?? '';
  static const String _serperUrl = 'https://google.serper.dev/search';

  static const int _maxPdfBytes = 25 * 1024 * 1024;
  static const int _maxCatalogChars = 12000;
  static const int _maxOfferLines = 120;
  static const int _maxFlyerPages = 2;

  static const List<String> _defaultStores = [
    'Lidl',
    'Kaufland',
    'Carrefour',
    'Auchan',
  ];

  final Map<String, SearchResponse> _searchCache = {};

  // Cache scurt al produselor din magazin (pentru căutarea locală pe tokeni).
  List<ShopProduct>? _shopProductsCache;
  DateTime? _shopProductsCacheAt;
  static const Duration _shopCacheTtl = Duration(minutes: 5);

  bool get _serperConfigured =>
      _serperApiKey.isNotEmpty && _serperApiKey != 'PUNE_SERPER_API_KEY_AICI';

  // ── PUBLIC: căutare principală ───────────────────────────────────────────

  Future<SearchResponse> search(String query, {int numResults = 5}) async {
    print('🔍 Searching for: $query');

    final cacheKey = '${query}_$numResults';
    if (_searchCache.containsKey(cacheKey)) {
      print('📦 Search cache hit: $query');
      return _searchCache[cacheKey]!;
    }

    // PASUL 1: Caută întâi în magazinul propriu (gratuit, fără limite)
    final shopProducts = await _searchInShop(query);
    if (shopProducts.isNotEmpty) {
      print(
        '🛒 Găsite ${shopProducts.length} produse în magazin pentru "$query"',
      );
    }

    // PASUL 2: Caută pe internet cu Serper (doar dacă e nevoie de info extra)
    SearchResponse internetResult = SearchResponse(
      success: true,
      query: query,
      results: [],
      shopProducts: shopProducts,
    );

    if (_serperConfigured) {
      final serperResult = await _searchSerper(query, numResults: numResults);
      internetResult = SearchResponse(
        success: serperResult.success || shopProducts.isNotEmpty,
        query: query,
        directAnswer: serperResult.directAnswer,
        results: serperResult.results,
        shopProducts: shopProducts,
        error: serperResult.error,
      );
    } else if (shopProducts.isEmpty) {
      return SearchResponse(
        success: false,
        query: query,
        results: [],
        error:
            'SERPER_API_KEY lipsește din .env și nu am găsit produse în magazin.',
      );
    }

    // Cache
    if (internetResult.success &&
        (internetResult.results.isNotEmpty ||
            internetResult.shopProducts.isNotEmpty)) {
      if (_searchCache.length >= 50) {
        _searchCache.remove(_searchCache.keys.first);
      }
      _searchCache[cacheKey] = internetResult;
    }

    return internetResult;
  }

  // ── MAGAZIN PROPRIU (Supabase) ────────────────────────────────────────────

  /// Căutare în magazinul propriu (Supabase) — INDEPENDENTĂ de căutarea pe
  /// internet. Nu mai folosește fraza brută ca substring (cum greșea înainte:
  /// „cât costă o doză de coca cola în RO" nu se potrivea cu „Coca-Cola"). Acum:
  ///   1. extrage cuvintele-cheie ale produsului din întrebare (scoate „cât
  ///      costă / o / doză / în RO" etc.);
  ///   2. aduce produsele (cache 5 min, magazinul e mic);
  ///   3. le potrivește LOCAL, pe tokeni, normalizat (fără diacritice/cratime),
  ///      bidirecțional — așa „coca cola", „Coca-Cola", „o doză de cola" găsesc
  ///      toate „Coca-Cola". Adăugarea de produse noi nu cere nicio schimbare.
  Future<List<ShopProduct>> _searchInShop(String query) async {
    final tokens = _productTokens(query);
    if (tokens.isEmpty) return [];

    final products = await _getCachedShopProducts();
    if (products.isEmpty) return [];

    final matches = _matchShopProducts(products, query, tokens);
    if (matches.isNotEmpty) {
      print(
        '✅ Supabase (local): ${matches.length} produse pentru "${tokens.join(' ')}"',
      );
    }
    return matches;
  }

  /// Aduce toate produsele din magazin cu un cache scurt (evită un request la
  /// fiecare căutare). Reutilizează `getAllShopProducts`.
  Future<List<ShopProduct>> _getCachedShopProducts() async {
    final now = DateTime.now();
    if (_shopProductsCache != null &&
        _shopProductsCacheAt != null &&
        now.difference(_shopProductsCacheAt!) < _shopCacheTtl) {
      return _shopProductsCache!;
    }
    final products = await getAllShopProducts();
    if (products.isNotEmpty) {
      _shopProductsCache = products;
      _shopProductsCacheAt = now;
    }
    return products;
  }

  /// Extrage cuvintele-cheie relevante ale produsului dintr-o întrebare,
  /// eliminând umplutura (preț, unități, articole, „în RO" etc.).
  List<String> _productTokens(String query) {
    const stop = {
      'pret', 'preturi', 'costa', 'cost', 'cat', 'cata', 'cate', 'face',
      'este', 'sunt', 'are', 'mult', 'multa', 'lei', 'ron', 'la', 'din', 'in',
      'ro', 'romania', 'magazin', 'magazinul', 'un', 'o', 'de', 'despre',
      'vreau', 'sa', 'imi', 'mi', 'spui', 'spune', 'cumpar', 'caut', 'gaseste',
      'doza', 'doze', 'sticla', 'cutie', 'pachet', 'punga', 'bucata', 'buc',
      'kg', 'gram', 'grame', 'litru', 'litri', 'cu', 'si', 'sau', 'ai',
      'aveti', 'avem', 'pe', 'el', 'ea', 'cum',
    };
    return _normalizeShop(query)
        .split(' ')
        .where((w) => w.length >= 3 && !stop.contains(w))
        .toList();
  }

  /// Potrivire locală pe tokeni, normalizată și bidirecțională.
  List<ShopProduct> _matchShopProducts(
    List<ShopProduct> products,
    String query,
    List<String> tokens,
  ) {
    final queryNorm = _normalizeShop(query);
    final scored = <MapEntry<ShopProduct, int>>[];

    for (final p in products) {
      final nameNorm = _normalizeShop(p.name);
      final nameTokens =
          nameNorm.split(' ').where((w) => w.length >= 3).toList();

      int score = 0;
      // direcția 1: cuvintele din întrebare apar în numele produsului
      // (ex. „coca", „cola" → „coca cola")
      for (final t in tokens) {
        if (nameNorm.contains(t)) score += 2;
      }
      // direcția 2: cuvintele din nume apar în întrebare
      // (ex. „lapte" din numele produsului în „laptele" din întrebare)
      for (final nt in nameTokens) {
        if (queryNorm.contains(nt)) score += 2;
      }
      if (score > 0) scored.add(MapEntry(p, score));
    }

    scored.sort((a, b) {
      final byScore = b.value.compareTo(a.value);
      if (byScore != 0) return byScore;
      // la scor egal, numele mai scurt e de regulă mai relevant
      return a.key.name.length.compareTo(b.key.name.length);
    });

    return scored.take(5).map((e) => e.key).toList();
  }

  /// Normalizare pentru potrivire: minuscule, fără diacritice, fără cratime/
  /// punctuație („Coca-Cola" → „coca cola").
  String _normalizeShop(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'[ăâ]'), 'a')
      .replaceAll(RegExp(r'[îí]'), 'i')
      .replaceAll(RegExp(r'[șş]'), 's')
      .replaceAll(RegExp(r'[țţ]'), 't')
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  // ── LINKURI PRODUS (pentru popup-ul de după căutare) ──────────────────────

  /// URL-ul public al magazinului propriu (pagina unui produs: /produs/{id}).
  static const String _storeBaseUrl = 'https://magazin-online-five.vercel.app';

  /// Domenii de încredere pentru linkul de internet.
  static const List<String> _trustedLinkDomains = [
    'emag.ro', 'pret.ro', 'compari.ro', 'carrefour.ro', 'auchan.ro',
    'mega-image.ro', 'kaufland.ro', 'lidl.ro', 'profi.ro',
  ];

  /// Construiește linkurile de produs pentru popup:
  /// 1-2 din magazinul propriu (sigure, construite din `id`) +
  /// 1 link de internet verificat (domeniu de încredere SAU accesibil, și
  /// relevant — numele produsului apare în titlu).
  Future<List<Map<String, dynamic>>> buildProductLinks(
    SearchResponse resp, {
    String? productTerm,
  }) async {
    final links = <Map<String, dynamic>>[];

    for (final p in resp.shopProducts.take(2)) {
      links.add({
        'label': p.name,
        'subtitle': '${p.price.toStringAsFixed(2)} lei — ${DiscountService.storeName}',
        'url': '$_storeBaseUrl/produs/${p.id}',
        'source': 'shop',
      });
    }

    final internet = await _pickInternetLink(resp.results, productTerm);
    if (internet != null) links.add(internet);

    return links;
  }

  Future<Map<String, dynamic>?> _pickInternetLink(
    List<SearchResult> results,
    String? term,
  ) async {
    if (results.isEmpty) return null;
    final tokens = (term != null && term.isNotEmpty)
        ? _productTokens(term)
        : <String>[];

    bool relevant(SearchResult r) {
      if (tokens.isEmpty) return true;
      final t = _normalizeShop(r.title);
      return tokens.any((tok) => t.contains(tok));
    }

    bool trusted(SearchResult r) {
      final l = r.link.toLowerCase();
      return _trustedLinkDomains.any((d) => l.contains(d));
    }

    // Ordine de preferință: încredere + relevant → relevant → orice.
    final ordered = <SearchResult>[
      ...results.where((r) => trusted(r) && relevant(r)),
      ...results.where((r) => relevant(r) && !trusted(r)),
      ...results,
    ];

    final seen = <String>{};
    for (final r in ordered) {
      if (r.link.isEmpty || !seen.add(r.link)) continue;
      // Domeniile de încredere le acceptăm direct; restul, doar dacă răspund.
      if (trusted(r) || await _isReachable(r.link)) {
        return {
          'label': r.title.isNotEmpty ? r.title : _domainOf(r.link),
          'subtitle': _domainOf(r.link),
          'url': r.link,
          'source': 'internet',
        };
      }
    }
    return null;
  }

  Future<bool> _isReachable(String url) async {
    try {
      final head = await http
          .head(Uri.parse(url))
          .timeout(const Duration(seconds: 6));
      return head.statusCode < 400;
    } catch (_) {
      return false;
    }
  }

  String _domainOf(String url) {
    try {
      return Uri.parse(url).host.replaceFirst('www.', '');
    } catch (_) {
      return url;
    }
  }

  /// Caută toate produsele din magazin (pentru lista completă)
  Future<List<ShopProduct>> getAllShopProducts() async {
    try {
      final uri = Uri.parse(
        '$_supabaseUrl/products?select=id,name,description,price,image_url,category_id,fara_zahar,bio,stock'
        '&order=name',
      );

      final response = await http
          .get(
            uri,
            headers: {
              'apikey': _supabaseAnonKey,
              'Authorization': 'Bearer $_supabaseAnonKey',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        return data.map((p) => ShopProduct.fromJson(p)).toList();
      }
      return [];
    } catch (e) {
      print('⚠️ getAllShopProducts error: $e');
      return [];
    }
  }

  // ── SERPER.DEV (fallback pentru căutări generale) ────────────────────────

  Future<SearchResponse> _searchSerper(
    String query, {
    int numResults = 5,
  }) async {
    try {
      final body = jsonEncode({
        'q': query,
        'gl': 'ro',
        'hl': 'ro',
        'num': numResults.clamp(1, 10),
      });

      final response = await http
          .post(
            Uri.parse(_serperUrl),
            headers: {
              'X-API-KEY': _serperApiKey,
              'Content-Type': 'application/json',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        final answerBox = data['answerBox'] as Map<String, dynamic>?;
        String? directAnswer;
        if (answerBox != null) {
          directAnswer =
              answerBox['answer'] as String? ??
              answerBox['snippet'] as String? ??
              answerBox['title'] as String?;
        }

        final organic = data['organic'] as List? ?? [];
        final results = organic.map((item) {
          return SearchResult(
            title: item['title'] ?? '',
            snippet: item['snippet'] ?? '',
            link: item['link'] ?? '',
          );
        }).toList();

        print('✅ Serper: ${results.length} rezultate pentru "$query"');
        return SearchResponse(
          success: true,
          query: query,
          directAnswer: directAnswer,
          results: results,
        );
      } else if (response.statusCode == 429) {
        print('⚠️ Serper: limită depășită');
        return SearchResponse(
          success: false,
          query: query,
          results: [],
          error: 'Limita de căutări Serper a fost depășită.',
        );
      } else {
        print('⚠️ Serper error: ${response.statusCode}');
        return SearchResponse(
          success: false,
          query: query,
          results: [],
          error: 'Eroare Serper: ${response.statusCode}',
        );
      }
    } catch (e) {
      print('❌ Serper error: $e');
      return SearchResponse(
        success: false,
        query: query,
        results: [],
        error: e.toString(),
      );
    }
  }

  // ── METODE PUBLICE AUXILIARE ─────────────────────────────────────────────

  Future<SearchResponse> searchNews(String query, {int numResults = 5}) async {
    return search('$query știri ultimele', numResults: numResults);
  }

  Future<Map<String, String>?> extractCatalogOffers(
    String query,
    List<SearchResult> results,
  ) async {
    final pdfInfo = await _findCatalogPdf(query, results);
    if (pdfInfo == null) return null;

    final text = await _extractPdfText(pdfInfo.link);
    if (text == null || text.trim().isEmpty) return null;

    final compact = _compactCatalogText(text);
    if (compact.trim().isEmpty) return null;

    return {
      'catalog_title': pdfInfo.title,
      'catalog_link': pdfInfo.link,
      'catalog_text': compact,
    };
  }

  Future<List<String>> findFlyerImageUrls(
    String query,
    List<SearchResult> results, {
    int maxPages = _maxFlyerPages,
  }) async {
    final flyerUrl = _findFlyerPageUrl(results);
    if (flyerUrl == null) return [];

    final base = _extractFlyerBase(flyerUrl);
    if (base == null) return [];

    final imageUrls = <String>[];
    for (int page = 1; page <= maxPages; page++) {
      final imageUrl = await _extractFlyerImageUrl('$base/page/$page');
      if (imageUrl != null && !imageUrls.contains(imageUrl)) {
        imageUrls.add(imageUrl);
      }
    }
    return imageUrls;
  }

  Future<ImageDownload?> downloadImage(String url) async {
    try {
      final response = await http
          .get(
            Uri.parse(url),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            },
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return null;

      final contentType = response.headers['content-type'] ?? '';
      final mimeType = contentType.split(';').first.trim();
      final resolvedType = mimeType.isNotEmpty
          ? mimeType
          : _guessImageMimeType(url);
      if (!resolvedType.startsWith('image/')) return null;

      return ImageDownload(bytes: response.bodyBytes, mimeType: resolvedType);
    } catch (e) {
      print('⚠️ Image download error: $e');
      return null;
    }
  }

  // ── PRICE COMPARISON ─────────────────────────────────────────────────────

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

    try {
      final matches = <StorePriceMatch>[];
      for (final item in scanItems) {
        for (final store in scanStores) {
          final match = await _findLivePrice(item: item, store: store);
          if (match != null) matches.add(match);
        }
      }

      if (matches.isEmpty) {
        return ShoppingPriceComparisonResponse.error(
          'Nu am găsit suficiente prețuri live pentru comparație.',
        );
      }

      final summaries = <StorePriceSummary>[];
      for (final store in scanStores) {
        final storeMatches = matches.where((m) => m.store == store).toList();
        final total = storeMatches.fold<double>(0, (s, m) => s + m.price);
        final missing = scanItems.length - storeMatches.length;
        summaries.add(
          StorePriceSummary(
            store: store,
            estimatedTotal: total + missing * 12.0,
            matchedItems: storeMatches.length,
            missingItems: missing,
          ),
        );
      }

      summaries.sort((a, b) => a.estimatedTotal.compareTo(b.estimatedTotal));
      final best = summaries.first;
      final highlighted = matches
          .where((m) => m.store == best.store)
          .map((m) => m.item)
          .toSet()
          .take(3)
          .toList();

      return ShoppingPriceComparisonResponse(
        success: true,
        recommendedStore: best.store,
        rationale: highlighted.isNotEmpty
            ? 'Estimarea cea mai bună este la ${best.store}. Produse avantajoase: ${highlighted.join(', ')}.'
            : 'Estimarea totală cea mai bună este la ${best.store}.',
        storeSummaries: summaries,
        matchedPrices: matches,
        scannedItems: scanItems,
      );
    } catch (e) {
      return ShoppingPriceComparisonResponse.error(
        'Eroare la compararea prețurilor: $e',
      );
    }
  }

  Future<StorePriceMatch?> _findLivePrice({
    required String item,
    required String store,
  }) async {
    final result = await search('$item preț $store România', numResults: 5);
    for (final r in result.results) {
      final price = _extractPrice('${r.title} ${r.snippet}');
      if (price != null) {
        return StorePriceMatch(
          item: item,
          store: store,
          price: price,
          sourceTitle: r.title,
          sourceLink: r.link,
        );
      }
    }
    return null;
  }

  double? _extractPrice(String text) {
    final normalized = text.toLowerCase().replaceAll(',', '.');
    final withCurrency = RegExp(
      r'(\d{1,4}(?:\.\d{1,2})?)\s*(lei|ron)',
      caseSensitive: false,
    );
    final m = withCurrency.firstMatch(normalized);
    if (m != null) {
      final value = double.tryParse(m.group(1)!);
      if (value != null && value > 0 && value < 5000) return value;
    }
    return null;
  }

  // ── PDF / FLYER HELPERS ──────────────────────────────────────────────────

  String? _findFlyerPageUrl(List<SearchResult> results) {
    for (final r in results) {
      if (r.link.contains('/view/flyer/page/')) return r.link;
    }
    return null;
  }

  String? _extractFlyerBase(String url) {
    final m = RegExp(r'^(https?://[^\s]+/view/flyer)/page/\d+').firstMatch(url);
    return m?.group(1);
  }

  Future<String?> _extractFlyerImageUrl(String pageUrl) async {
    try {
      final response = await http
          .get(
            Uri.parse(pageUrl),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            },
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return null;

      for (final m in RegExp(
        r'https?://[^\s"\)]+\.(?:png|jpg|jpeg)',
        caseSensitive: false,
      ).allMatches(response.body)) {
        final url = m.group(0) ?? '';
        if (url.contains('leaflets') || url.contains('imgproxy')) return url;
      }
      return null;
    } catch (e) {
      print('⚠️ Flyer page error: $e');
      return null;
    }
  }

  String _guessImageMimeType(String url) {
    final lower = url.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    return 'image/png';
  }

  Future<CatalogPdfInfo?> _findCatalogPdf(
    String query,
    List<SearchResult> results,
  ) async {
    final candidates = <SearchResult>[...results];

    final pdfSearch = await search('$query catalog pdf', numResults: 8);
    for (final r in pdfSearch.results) {
      if (!candidates.any((c) => c.link == r.link)) candidates.add(r);
    }

    for (final r in candidates) {
      if (r.link.toLowerCase().contains('.pdf')) {
        return CatalogPdfInfo(title: r.title, link: r.link);
      }
    }
    return null;
  }

  Future<String?> _extractPdfText(String url) async {
    try {
      final response = await http
          .get(
            Uri.parse(url),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            },
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode != 200) return null;
      final bytes = response.bodyBytes;
      if (bytes.isEmpty || bytes.length > _maxPdfBytes) return null;

      final document = PdfDocument(inputBytes: bytes);
      final extractor = PdfTextExtractor(document);
      final text = extractor.extractText();
      document.dispose();

      if (text.trim().length < 200) return null;
      return text;
    } catch (e) {
      print('⚠️ PDF extraction error: $e');
      return null;
    }
  }

  String _compactCatalogText(String text) {
    final lines = text
        .replaceAll('\r', '')
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final pricePattern = RegExp(
      r'(\d{1,4}(?:[.,]\d{1,2})?)\s*(lei|ron)',
      caseSensitive: false,
    );

    final extracted = <String>[];
    final seen = <String>{};

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (pricePattern.hasMatch(line)) {
        if (i > 0 && !pricePattern.hasMatch(lines[i - 1])) {
          if (seen.add(lines[i - 1])) extracted.add(lines[i - 1]);
        }
        if (seen.add(line)) extracted.add(line);
      }
      if (extracted.length >= _maxOfferLines) break;
    }

    final result = extracted.isEmpty
        ? lines.take(_maxOfferLines).join('\n')
        : extracted.join('\n');

    return result.length <= _maxCatalogChars
        ? result
        : result.substring(0, _maxCatalogChars);
  }

  void clearSearchCache() {
    _searchCache.clear();
  }
}
