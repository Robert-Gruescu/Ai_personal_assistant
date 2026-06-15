import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MODELE
// ─────────────────────────────────────────────────────────────────────────────

class DiscountItem {
  final String name;
  final String store;
  final String? originalPrice;
  final String? discountedPrice;
  final String? discountPercent;
  final String? validUntil;
  final String? category;
  final DateTime fetchedAt;

  DiscountItem({
    required this.name,
    required this.store,
    this.originalPrice,
    this.discountedPrice,
    this.discountPercent,
    this.validUntil,
    this.category,
    required this.fetchedAt,
  });

  bool get isExpired =>
      DateTime.now().difference(fetchedAt).inHours >= DiscountService.cacheHours;

  Map<String, dynamic> toJson() => {
        'name': name,
        'store': store,
        'original_price': originalPrice,
        'discounted_price': discountedPrice,
        'discount_percent': discountPercent,
        'valid_until': validUntil,
        'category': category,
        'fetched_at': fetchedAt.toIso8601String(),
      };

  factory DiscountItem.fromJson(Map<String, dynamic> j) => DiscountItem(
        name: j['name'] ?? '',
        store: j['store'] ?? '',
        originalPrice: j['original_price'],
        discountedPrice: j['discounted_price'],
        discountPercent: j['discount_percent'],
        validUntil: j['valid_until'],
        category: j['category'],
        fetchedAt: DateTime.tryParse(j['fetched_at'] ?? '') ?? DateTime.now(),
      );

  String toReadable() {
    final parts = <String>[name];
    if (discountedPrice != null) parts.add(discountedPrice!);
    if (discountPercent != null) parts.add('-$discountPercent%');
    if (validUntil != null) parts.add('valabil $validUntil');
    return parts.join(' — ');
  }
}

class StoreDiscountResult {
  final String store;
  final List<DiscountItem> allDiscounts;
  final List<DiscountItem> matchingShoppingList;
  final bool fromCache;
  final String? catalogPeriod;
  final String? error;

  StoreDiscountResult({
    required this.store,
    required this.allDiscounts,
    required this.matchingShoppingList,
    this.fromCache = false,
    this.catalogPeriod,
    this.error,
  });
}

class DiscountResponse {
  final bool success;
  final List<StoreDiscountResult> storeResults;
  final List<DiscountItem> prioritizedItems;
  final List<DiscountItem> otherItems;
  final String? error;

  DiscountResponse({
    required this.success,
    required this.storeResults,
    required this.prioritizedItems,
    required this.otherItems,
    this.error,
  });

  factory DiscountResponse.error(String msg) => DiscountResponse(
        success: false,
        storeResults: [],
        prioritizedItems: [],
        otherItems: [],
        error: msg,
      );

  String formatForAI() {
    if (!success || (prioritizedItems.isEmpty && otherItems.isEmpty)) {
      return 'Nu am găsit reduceri disponibile momentan.';
    }

    final buf = StringBuffer();

    if (prioritizedItems.isNotEmpty) {
      buf.writeln('Reduceri la produse din lista ta:');
      for (final item in prioritizedItems.take(6)) {
        buf.writeln('• ${item.toReadable()} (${item.store})');
      }
      buf.writeln();
    }

    final remaining = 10 - prioritizedItems.take(6).length;
    if (otherItems.isNotEmpty && remaining > 0) {
      buf.writeln('Alte reduceri găsite:');
      for (final item in otherItems.take(remaining)) {
        buf.writeln('• ${item.toReadable()} (${item.store})');
      }
    }

    final periods = storeResults
        .where((r) => r.catalogPeriod != null && r.allDiscounts.isNotEmpty)
        .map((r) => '${r.store}: ${r.catalogPeriod}')
        .join(', ');
    if (periods.isNotEmpty) {
      buf.writeln('\nValabile: $periods');
    }

    return buf.toString().trim();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SERVICE
// ─────────────────────────────────────────────────────────────────────────────

/// Sursa datelor: mooldo.ro — agregator cataloage supermarketuri .ro
/// Flux: shop page → link catalog activ → pagina catalog → extrage produse
/// Cache 24h SharedPreferences, ștergere automată la expirare
class DiscountService {
  static final DiscountService _instance = DiscountService._internal();
  factory DiscountService() => _instance;
  DiscountService._internal();

  static const int cacheHours = 24;
  static const String _cachePrefix = 'discount_v2_';

  static const Map<String, String> _storeSlugs = {
    'Lidl': 'lidl',
    'Kaufland': 'kaufland',
    'Carrefour': 'carrefour',
    'Penny': 'penny',
    'Mega Image': 'mega-image',
    'Auchan': 'auchan',
    'Profi': 'profi',
  };

  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/124.0 Safari/537.36',
    'Accept-Language': 'ro-RO,ro;q=0.9',
    'Accept': 'text/html,application/xhtml+xml',
  };

  // ── PUBLIC ──────────────────────────────────────────────────────────────────

  Future<DiscountResponse> getDiscounts({
    List<String> shoppingListItems = const [],
    List<String>? stores,
    bool forceRefresh = false,
  }) async {
    final targetStores = stores ?? _storeSlugs.keys.toList();
    final normalizedList =
        shoppingListItems.map(_normalize).where((e) => e.isNotEmpty).toList();

    try {
      final storeResults = <StoreDiscountResult>[];
      for (final store in targetStores) {
        if (!_storeSlugs.containsKey(store)) continue;
        storeResults.add(await _getStoreDiscounts(
          store: store,
          shoppingList: normalizedList,
          forceRefresh: forceRefresh,
        ));
      }

      final allItems = storeResults.expand((r) => r.allDiscounts).toList();
      final prioritized = <DiscountItem>[];
      final others = <DiscountItem>[];

      for (final item in allItems) {
        final nameNorm = _normalize(item.name);
        final matches = normalizedList.isNotEmpty &&
            normalizedList.any((s) => _fuzzyMatch(nameNorm, s));
        (matches ? prioritized : others).add(item);
      }

      prioritized.sort(_byDiscount);
      others.sort(_byDiscount);

      return DiscountResponse(
        success: true,
        storeResults: storeResults,
        prioritizedItems: prioritized,
        otherItems: others,
      );
    } catch (e) {
      print('DiscountService error: $e');
      return DiscountResponse.error('Eroare la căutarea reducerilor: $e');
    }
  }

  // ── REDUCERI DE PE SITE (endpoint /api/reduceri) ─────────────────────────────
  //
  // Citește reducerile DE PE SITE-ul propriu (funcția serverless care expune
  // tabelul weekly_deals), NU direct din baza de date și NU prin scraping.
  // Înlocuiește sursa mooldo.ro.

  static const String _siteDiscountsUrl =
      'https://magazin-online-five.vercel.app/api/reduceri';

  List<DiscountItem>? _siteCache;
  DateTime? _siteCacheAt;
  static const Duration _siteCacheTtl = Duration(minutes: 10);

  Future<DiscountResponse> getSiteDiscounts({
    List<String> shoppingListItems = const [],
    bool forceRefresh = false,
  }) async {
    final normalizedList =
        shoppingListItems.map(_normalize).where((e) => e.isNotEmpty).toList();

    try {
      final items = await _fetchSiteDeals(forceRefresh: forceRefresh);
      if (items.isEmpty) {
        return DiscountResponse(
          success: true,
          storeResults: const [],
          prioritizedItems: const [],
          otherItems: const [],
        );
      }

      final prioritized = <DiscountItem>[];
      final others = <DiscountItem>[];
      for (final item in items) {
        final nameNorm = _normalize(item.name);
        final matches = normalizedList.isNotEmpty &&
            normalizedList.any((s) => _fuzzyMatch(nameNorm, s));
        (matches ? prioritized : others).add(item);
      }
      prioritized.sort(_byDiscount);
      others.sort(_byDiscount);

      return DiscountResponse(
        success: true,
        storeResults: [
          StoreDiscountResult(
            store: 'Magazinul tău',
            allDiscounts: items,
            matchingShoppingList: prioritized,
          ),
        ],
        prioritizedItems: prioritized,
        otherItems: others,
      );
    } catch (e) {
      print('Site discounts error: $e');
      return DiscountResponse.error('Eroare la citirea reducerilor: $e');
    }
  }

  Future<List<DiscountItem>> _fetchSiteDeals({bool forceRefresh = false}) async {
    final now = DateTime.now();
    if (!forceRefresh &&
        _siteCache != null &&
        _siteCacheAt != null &&
        now.difference(_siteCacheAt!) < _siteCacheTtl) {
      return _siteCache!;
    }

    final resp = await http
        .get(Uri.parse(_siteDiscountsUrl), headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      print('Site reduceri: HTTP ${resp.statusCode}');
      return _siteCache ?? [];
    }

    final data = jsonDecode(resp.body);
    if (data is! List) return [];

    final items = <DiscountItem>[];
    for (final raw in data) {
      if (raw is! Map) continue;
      final name = (raw['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      final price = raw['price'];
      final oldPrice = raw['old_price'];
      final percent = raw['discount_percent'];
      items.add(DiscountItem(
        name: name,
        store: 'Magazinul tău',
        originalPrice: oldPrice != null ? '${_fmtPrice(oldPrice)} lei' : null,
        discountedPrice: price != null ? '${_fmtPrice(price)} lei' : null,
        discountPercent: percent?.toString(),
        validUntil: _formatValid(raw['valid_until']),
        category: raw['category']?.toString(),
        fetchedAt: now,
      ));
    }
    _siteCache = items;
    _siteCacheAt = now;
    return items;
  }

  String _fmtPrice(dynamic v) {
    final d = (v is num) ? v.toDouble() : double.tryParse(v.toString());
    return d != null ? d.toStringAsFixed(2) : v.toString();
  }

  String? _formatValid(dynamic v) {
    if (v == null) return null;
    final d = DateTime.tryParse(v.toString());
    if (d == null) return v.toString();
    try {
      return DateFormat('d MMMM yyyy', 'ro').format(d);
    } catch (_) {
      return v.toString();
    }
  }

  Future<void> clearCache({String? store}) async {
    final prefs = await SharedPreferences.getInstance();
    if (store != null) {
      await prefs.remove('$_cachePrefix${store.toLowerCase()}');
    } else {
      for (final s in _storeSlugs.keys) {
        await prefs.remove('$_cachePrefix${s.toLowerCase()}');
      }
    }
  }

  // ── FETCH PER MAGAZIN ────────────────────────────────────────────────────────

  Future<StoreDiscountResult> _getStoreDiscounts({
    required String store,
    required List<String> shoppingList,
    required bool forceRefresh,
  }) async {
    if (!forceRefresh) {
      final cached = await _loadCache(store);
      if (cached != null) {
        return StoreDiscountResult(
          store: store,
          allDiscounts: cached,
          matchingShoppingList: _filterMatching(cached, shoppingList),
          fromCache: true,
        );
      }
    }

    final slug = _storeSlugs[store]!;
    String? catalogUrl;
    String? catalogPeriod;

    try {
      final resp = await http
          .get(Uri.parse('https://mooldo.ro/ro/shops/$slug'), headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        final parsed = _parseCatalogLink(resp.body);
        catalogUrl = parsed['url'];
        catalogPeriod = parsed['period'];
      }
    } catch (e) {
      print('Eroare fetch shop $store: $e');
    }

    if (catalogUrl == null) {
      return StoreDiscountResult(
        store: store,
        allDiscounts: [],
        matchingShoppingList: [],
        error: 'Nu am găsit catalog activ pentru $store',
      );
    }

    final items = await _parseCatalogPage(catalogUrl, store, catalogPeriod);
    if (items.isNotEmpty) await _saveCache(store, items);

    return StoreDiscountResult(
      store: store,
      allDiscounts: items,
      matchingShoppingList: _filterMatching(items, shoppingList),
      catalogPeriod: catalogPeriod,
      error: items.isEmpty
          ? 'Nu am putut extrage produse din catalogul $store'
          : null,
    );
  }

  // ── PARSING mooldo.ro ────────────────────────────────────────────────────────

  Map<String, String?> _parseCatalogLink(String html) {
    final linkMatch =
        RegExp(r'href="(/ro/catalog/[^"]+)"').firstMatch(html);
    final periodMatch =
        RegExp(r'(\d{1,2}\s*[-–]\s*\d{1,2}\s+\w+\s+\d{4})').firstMatch(html);
    return {
      'url': linkMatch != null ? 'https://mooldo.ro${linkMatch.group(1)}' : null,
      'period': periodMatch?.group(1),
    };
  }

  Future<List<DiscountItem>> _parseCatalogPage(
    String url,
    String store,
    String? validUntil,
  ) async {
    try {
      final resp = await http
          .get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) return [];
      return _extractProducts(resp.body, store, validUntil);
    } catch (e) {
      print('Eroare fetch catalog $store: $e');
      return [];
    }
  }

  List<DiscountItem> _extractProducts(
    String html,
    String store,
    String? validUntil,
  ) {
    final items = <DiscountItem>[];
    final seen = <String>{};
    final now = DateTime.now();

    void tryAdd({
      required String name,
      String? oldPrice,
      String? newPrice,
      String? percent,
    }) {
      final cleaned = _cleanText(name);
      if (cleaned.length < 4) return;
      if (_isUiNoise(cleaned)) return;
      final key = _normalize(cleaned);
      if (key.length < 3 || !seen.add(key)) return;

      items.add(DiscountItem(
        name: cleaned,
        store: store,
        originalPrice: oldPrice,
        discountedPrice: newPrice,
        discountPercent: percent,
        validUntil: validUntil,
        category: _guessCategory(cleaned),
        fetchedAt: now,
      ));
    }

    // Pattern 1 — bloc cu procent, preț vechi, preț nou, nume produs
    for (final m in RegExp(
      r'-(\d{1,2})%[\s\S]{0,60}?(\d{1,4}[.,]\d{1,2})\s*lei'
      r'[\s\S]{0,100}?(\d{1,4}[.,]\d{1,2})\s*lei'
      r'[\s\S]{0,200}?([A-ZĂÂÎȘȚ][^\n<]{5,80})',
      caseSensitive: false,
    ).allMatches(html)) {
      tryAdd(
        name: m.group(4) ?? '',
        oldPrice: '${m.group(2)} lei',
        newPrice: '${m.group(3)} lei',
        percent: m.group(1),
      );
      if (items.length >= 20) break;
    }

    // Pattern 2 — fallback: preț + text descriptiv
    if (items.length < 5) {
      for (final m in RegExp(
        r'(\d{1,4}[.,]\d{1,2})\s*lei\s+([A-ZĂÂÎȘȚ][^\n<]{5,70})',
        caseSensitive: false,
      ).allMatches(html)) {
        tryAdd(name: m.group(2) ?? '', newPrice: '${m.group(1)} lei');
        if (items.length >= 20) break;
      }
    }

    // Pattern 3 — alt-text imagini catalog
    if (items.length < 3) {
      for (final m in RegExp(
        r'alt="[^"]*(?:pagina|page)[^"]*:\s*([^"]{10,100})"',
        caseSensitive: false,
      ).allMatches(html)) {
        for (final part in (m.group(1) ?? '').split(RegExp(r'[,;]'))) {
          tryAdd(name: part.trim());
          if (items.length >= 20) break;
        }
        if (items.length >= 20) break;
      }
    }

    print('$store: ${items.length} produse extrase');
    return items;
  }

  // ── CACHE ────────────────────────────────────────────────────────────────────

  Future<List<DiscountItem>?> _loadCache(String store) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_cachePrefix${store.toLowerCase()}');
      if (raw == null) return null;
      final list = (jsonDecode(raw) as List)
          .map((e) => DiscountItem.fromJson(e as Map<String, dynamic>))
          .toList();
      if (list.isNotEmpty && list.first.isExpired) {
        await prefs.remove('$_cachePrefix${store.toLowerCase()}');
        return null;
      }
      return list;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCache(String store, List<DiscountItem> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_cachePrefix${store.toLowerCase()}',
        jsonEncode(items.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      print('Eroare salvare cache $store: $e');
    }
  }

  // ── HELPERS ──────────────────────────────────────────────────────────────────

  List<DiscountItem> _filterMatching(
      List<DiscountItem> items, List<String> list) {
    if (list.isEmpty) return [];
    return items
        .where((i) => list.any((s) => _fuzzyMatch(_normalize(i.name), s)))
        .toList();
  }

  int _byDiscount(DiscountItem a, DiscountItem b) {
    double p(String? s) =>
        s == null ? 0 : double.tryParse(s.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
    return p(b.discountPercent).compareTo(p(a.discountPercent));
  }

  bool _fuzzyMatch(String itemName, String listItem) =>
      listItem.split(' ').where((w) => w.length > 2).any(itemName.contains);

  String _normalize(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'[ăâ]'), 'a')
      .replaceAll(RegExp(r'[îí]'), 'i')
      .replaceAll(RegExp(r'[șş]'), 's')
      .replaceAll(RegExp(r'[țţ]'), 't')
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  String _cleanText(String raw) => raw
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  bool _isUiNoise(String text) {
    const noise = [
      'abonează', 'urmărește', 'descarcă', 'aplicația', 'mooldo',
      'facebook', 'instagram', 'newsletter', 'cookie', 'catalogul',
      'reduceri generale', 'toate ofertele',
    ];
    final lower = text.toLowerCase();
    return noise.any(lower.contains);
  }

  String? _guessCategory(String name) {
    final n = _normalize(name);
    if (RegExp(r'\b(lapte|iaurt|branza|smantana|unt|kefir)\b').hasMatch(n)) {
      return 'Lactate';
    }
    if (RegExp(r'\b(carne|pui|porc|vita|peste|salam|sunca|mezel)\b').hasMatch(n)) {
      return 'Carne & mezeluri';
    }
    if (RegExp(r'\b(paine|covrigi|franzela|biscuiti|tort|prajitura)\b').hasMatch(n)) {
      return 'Panificație & dulciuri';
    }
    if (RegExp(r'\b(mere|pere|banana|portocale|legume|rosii|cartofi)\b').hasMatch(n)) {
      return 'Fructe & legume';
    }
    if (RegExp(r'\b(detergent|sapun|sampon|hartie|servetele|burete)\b').hasMatch(n)) {
      return 'Curățenie & igienă';
    }
    if (RegExp(r'\b(cafea|ceai|suc|apa|bere|vin)\b').hasMatch(n)) {
      return 'Băuturi';
    }
    return null;
  }
}