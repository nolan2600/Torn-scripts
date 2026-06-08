import 'package:flutter/foundation.dart';
import '../models/app_settings.dart';
import '../services/storage_service.dart';

class SettingsProvider extends ChangeNotifier {
  AppSettings _settings = AppSettings.defaults;
  String _tornKey = '';
  String _ffKey = '';
  bool _loaded = false;

  AppSettings get settings => _settings;
  String get tornKey => _tornKey;
  String get ffKey => _ffKey;
  bool get hasKey => _tornKey.isNotEmpty;
  bool get loaded => _loaded;

  Future<void> load() async {
    await StorageService.instance.init();
    _tornKey = StorageService.instance.getTornKey() ?? '';
    _ffKey = StorageService.instance.getFFKey() ?? '';
    final raw = StorageService.instance.getSettingsJson();
    if (raw != null) {
      try {
        _settings = AppSettings.fromJsonString(raw);
      } catch (_) {
        _settings = AppSettings.defaults;
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> saveTornKey(String key) async {
    _tornKey = key;
    await StorageService.instance.saveTornKey(key);
    notifyListeners();
  }

  Future<void> clearTornKey() async {
    _tornKey = '';
    await StorageService.instance.clearTornKey();
    notifyListeners();
  }

  Future<void> saveFFKey(String key) async {
    _ffKey = key;
    await StorageService.instance.saveFFKey(key);
    notifyListeners();
  }

  Future<void> clearFFKey() async {
    _ffKey = '';
    await StorageService.instance.clearFFKey();
    notifyListeners();
  }

  Future<void> update(AppSettings updated) async {
    _settings = updated;
    await StorageService.instance.saveSettingsJson(updated.toJsonString());
    notifyListeners();
  }

  Future<void> reset() async {
    _settings = AppSettings.defaults;
    await StorageService.instance.saveSettingsJson(_settings.toJsonString());
    notifyListeners();
  }
}
