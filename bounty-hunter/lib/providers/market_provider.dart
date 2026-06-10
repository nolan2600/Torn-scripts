import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/market_models.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../services/notification_service.dart';
import 'settings_provider.dart';

class MarketProvider extends ChangeNotifier {
  final SettingsProvider _settings;
  late TornApiService _api;

  MarketProvider(this._settings) {
    _api = TornApiService(_settings.tornKey);
    _load();
  }

  // ── State ──────────────────────────────────────────────────
  List<WatchedItem> watchedItems = [];
  Map<int, TornItem> itemsCache = {};
  Map<int, LiveItemData> liveData = {};
  Map<int, List<PricePoint>> priceHistory = {};

  bool itemsCacheLoaded = false;
  bool cacheLoading = false;
  String? cacheError;

  bool marketRefreshing = false;
  String? marketError;
  DateTime? lastMarketRefresh;

  // Flip calculator
  TornItem? flipItem;
  LiveItemData? flipLiveData;
  bool flipLoading = false;

  bool _disposed = false;
  Timer? _autoRefreshTimer;
  final Set<int> _triggeredItems = {};

  void onSettingsChanged() {
    _api.apiKey = _settings.tornKey;
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _stopAutoRefresh();
    _disposed = true;
    super.dispose();
  }

  // ── Auto-refresh timer ─────────────────────────────────────
  void _startAutoRefresh() {
    _stopAutoRefresh();
    final intervalSec = _settings.settings.marketRefreshSec;
    if (intervalSec <= 0) return;
    _autoRefreshTimer = Timer.periodic(Duration(seconds: intervalSec), (_) {
      if (!_disposed && _settings.hasKey && watchedItems.isNotEmpty) {
        refreshWatchlist();
      }
    });
  }

  void _stopAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
  }

  // ── Startup load ───────────────────────────────────────────
  Future<void> _load() async {
    await StorageService.instance.init();
    _loadWatchedItems();
    _loadPriceHistory();
    _loadItemsCache();
    _startAutoRefresh();
    if (!_disposed) notifyListeners();
  }

  void _loadWatchedItems() {
    final raw = StorageService.instance.getWatchedItemsJson();
    if (raw == null || raw.isEmpty) return;
    try {
      watchedItems = WatchedItem.listFromJson(raw);
    } catch (_) {
      watchedItems = [];
    }
  }

  void _loadPriceHistory() {
    final raw = StorageService.instance.getPriceHistoryJson();
    if (raw == null || raw.isEmpty) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      priceHistory = {
        for (final e in map.entries)
          if (int.tryParse(e.key) != null)
            int.parse(e.key): (e.value as List<dynamic>)
                .map((p) => PricePoint.fromJson(p as Map<String, dynamic>))
                .toList(),
      };
    } catch (_) {}
  }

  void _loadItemsCache() {
    final raw = StorageService.instance.getItemsCacheJson();
    if (raw == null || raw.isEmpty) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      itemsCache = {
        for (final e in map.entries)
          if (int.tryParse(e.key) != null)
            int.parse(e.key): TornItem.fromJson(
                int.parse(e.key), e.value as Map<String, dynamic>),
      };
      itemsCacheLoaded = itemsCache.isNotEmpty;
    } catch (_) {}
  }

  // ── Items cache ────────────────────────────────────────────
  Future<void> ensureItemsCache({bool forceRefresh = false}) async {
    if (!_settings.hasKey) return;
    final ts = StorageService.instance.getItemsCacheTs() ?? 0;
    final age = DateTime.now().millisecondsSinceEpoch ~/ 1000 - ts;
    if (!forceRefresh && itemsCacheLoaded && age < 86400) return;

    cacheLoading = true;
    cacheError = null;
    if (!_disposed) notifyListeners();

    try {
      _api.apiKey = _settings.tornKey;
      final items = await _api.fetchAllItems();
      itemsCache = items;
      itemsCacheLoaded = true;
      final cacheJson = jsonEncode({
        for (final e in items.entries) '${e.key}': e.value.toJson(),
      });
      await StorageService.instance.saveItemsCacheJson(cacheJson);
      await StorageService.instance.saveItemsCacheTs(
          DateTime.now().millisecondsSinceEpoch ~/ 1000);
    } catch (e) {
      cacheError = e.toString().replaceFirst('Exception: ', '');
    }

    cacheLoading = false;
    if (!_disposed) notifyListeners();
  }

  List<TornItem> searchItems(String query) {
    if (query.isEmpty) return [];
    final q = query.toLowerCase();
    final results = itemsCache.values
        .where((i) => i.name.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) {
        final aStart = a.name.toLowerCase().startsWith(q);
        final bStart = b.name.toLowerCase().startsWith(q);
        if (aStart && !bStart) return -1;
        if (bStart && !aStart) return 1;
        return a.name.compareTo(b.name);
      });
    return results;
  }

  // ── Watchlist CRUD ─────────────────────────────────────────
  bool isWatched(int id) => watchedItems.any((w) => w.id == id);

  void addToWatchlist(TornItem item) {
    if (isWatched(item.id)) return;
    watchedItems = [
      ...watchedItems,
      WatchedItem(
        id: item.id,
        name: item.name,
        type: item.type,
        marketValue: item.marketValue,
      ),
    ];
    _saveWatchedItems();
    notifyListeners();
  }

  void removeFromWatchlist(int id) {
    watchedItems = watchedItems.where((w) => w.id != id).toList();
    liveData.remove(id);
    _triggeredItems.remove(id);
    _saveWatchedItems();
    notifyListeners();
  }

  void setAlertThreshold(int itemId, int? threshold, {bool alertAbove = false}) {
    watchedItems = watchedItems.map((w) {
      if (w.id != itemId) return w;
      return WatchedItem(
        id: w.id,
        name: w.name,
        type: w.type,
        marketValue: w.marketValue,
        alertThreshold: threshold,
        alertAbove: alertAbove,
      );
    }).toList();
    _triggeredItems.remove(itemId);
    _saveWatchedItems();
    notifyListeners();
  }

  Future<void> _saveWatchedItems() async {
    await StorageService.instance
        .saveWatchedItemsJson(WatchedItem.listToJson(watchedItems));
  }

  // ── Market refresh ─────────────────────────────────────────
  Future<void> refreshWatchlist() async {
    if (watchedItems.isEmpty || !_settings.hasKey || marketRefreshing) return;
    marketRefreshing = true;
    marketError = null;
    if (!_disposed) notifyListeners();

    _api.apiKey = _settings.tornKey;
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    for (final item in List<WatchedItem>.from(watchedItems)) {
      if (_disposed) break;
      LiveItemData? data;
      try {
        data = await _api.fetchItemMarket(item.id, limitOne: true);
      } catch (e) {
        marketError = e.toString()
            .replaceFirst('TornApiException: ', '')
            .replaceFirst('Exception: ', '');
        if (!_disposed) notifyListeners();
        continue;
      }
      if (data == null) continue;
      liveData[item.id] = data;

      // Record price snapshot (keep last 50)
      final pts = List<PricePoint>.from(priceHistory[item.id] ?? []);
      pts.add(PricePoint(timestamp: nowSec, price: data.cheapestPrice));
      if (pts.length > 50) pts.removeRange(0, pts.length - 50);
      priceHistory[item.id] = pts;

      // Price alert — only notify on transition into triggered state
      final threshold = item.alertThreshold;
      if (threshold != null && data.cheapestPrice > 0) {
        final triggered = item.alertAbove
            ? data.cheapestPrice >= threshold
            : data.cheapestPrice <= threshold;
        final wasTriggered = _triggeredItems.contains(item.id);
        if (triggered && !wasTriggered) {
          _triggeredItems.add(item.id);
          NotificationService.instance.showPriceAlert(
            itemId: item.id,
            itemName: item.name,
            price: data.cheapestPrice,
            threshold: threshold,
            alertAbove: item.alertAbove,
          );
        } else if (!triggered) {
          _triggeredItems.remove(item.id);
        }
      } else {
        _triggeredItems.remove(item.id);
      }

      if (!_disposed) notifyListeners();
    }

    await _savePriceHistory();
    lastMarketRefresh = DateTime.now();
    marketRefreshing = false;
    if (!_disposed) notifyListeners();
  }

  Future<void> _savePriceHistory() async {
    final map = {
      for (final e in priceHistory.entries)
        '${e.key}': e.value.map((p) => p.toJson()).toList(),
    };
    await StorageService.instance.savePriceHistoryJson(jsonEncode(map));
  }

  // ── Flip calculator ────────────────────────────────────────
  Future<void> loadFlipItem(TornItem item) async {
    flipItem = item;
    flipLiveData = null;
    flipLoading = true;
    marketError = null;
    if (!_disposed) notifyListeners();

    _api.apiKey = _settings.tornKey;
    try {
      flipLiveData = await _api.fetchItemMarket(item.id);
    } catch (e) {
      marketError = e.toString()
          .replaceFirst('TornApiException: ', '')
          .replaceFirst('Exception: ', '');
    }
    flipLoading = false;
    if (!_disposed) notifyListeners();
  }

  Future<void> refreshFlipPrice() async {
    if (flipItem == null || !_settings.hasKey || flipLoading) return;
    flipLoading = true;
    marketError = null;
    if (!_disposed) notifyListeners();
    try {
      flipLiveData = await _api.fetchItemMarket(flipItem!.id);
    } catch (e) {
      marketError = e.toString()
          .replaceFirst('TornApiException: ', '')
          .replaceFirst('Exception: ', '');
    }
    flipLoading = false;
    if (!_disposed) notifyListeners();
  }

  void clearFlipItem() {
    flipItem = null;
    flipLiveData = null;
    if (!_disposed) notifyListeners();
  }
}
