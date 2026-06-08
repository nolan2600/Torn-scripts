import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  static const _kTornKey = 'bh_tornKey';
  static const _kFFKey = 'bh_ffKey';
  static const _kSettings = 'bh_settings';
  static const _kTargets = 'bh_targets';
  static const _kAlertIds = 'bh_alertIds';
  static const _kWatchedItems = 'bh_watched_items';
  static const _kPriceHistory = 'bh_price_history';
  static const _kItemsCache = 'bh_items_cache';
  static const _kItemsCacheTs = 'bh_items_cache_ts';

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  SharedPreferences get _p {
    if (_prefs == null) throw StateError('StorageService not initialized');
    return _prefs!;
  }

  // --- API keys ---
  String? getTornKey() => _p.getString(_kTornKey);
  Future<void> saveTornKey(String key) => _p.setString(_kTornKey, key);
  Future<void> clearTornKey() => _p.remove(_kTornKey);

  String? getFFKey() => _p.getString(_kFFKey);
  Future<void> saveFFKey(String key) => _p.setString(_kFFKey, key);
  Future<void> clearFFKey() => _p.remove(_kFFKey);

  // --- Settings ---
  String? getSettingsJson() => _p.getString(_kSettings);
  Future<void> saveSettingsJson(String json) => _p.setString(_kSettings, json);

  // --- Marked targets ---
  String? getTargetsJson() => _p.getString(_kTargets);
  Future<void> saveTargetsJson(String json) => _p.setString(_kTargets, json);

  // --- Per-target bell toggles for bounty board (ids that have bell ON) ---
  List<String> getAlertIds() =>
      _p.getStringList(_kAlertIds) ?? const [];
  Future<void> saveAlertIds(List<String> ids) =>
      _p.setStringList(_kAlertIds, ids);

  // --- Market Watch ---
  String? getWatchedItemsJson() => _p.getString(_kWatchedItems);
  Future<void> saveWatchedItemsJson(String json) =>
      _p.setString(_kWatchedItems, json);

  String? getPriceHistoryJson() => _p.getString(_kPriceHistory);
  Future<void> savePriceHistoryJson(String json) =>
      _p.setString(_kPriceHistory, json);

  String? getItemsCacheJson() => _p.getString(_kItemsCache);
  Future<void> saveItemsCacheJson(String json) =>
      _p.setString(_kItemsCache, json);

  int? getItemsCacheTs() => _p.getInt(_kItemsCacheTs);
  Future<void> saveItemsCacheTs(int ts) => _p.setInt(_kItemsCacheTs, ts);
}
