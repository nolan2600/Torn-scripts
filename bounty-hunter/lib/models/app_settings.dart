import 'dart:convert';

const kBsRanges = [
  {'id': 'bs-2k',   'label': '2k – 25k',    'min': 2000.0,       'max': 25000.0},
  {'id': 'bs-20k',  'label': '20k – 250k',  'min': 20000.0,      'max': 250000.0},
  {'id': 'bs-200k', 'label': '200k – 2.5m', 'min': 200000.0,     'max': 2500000.0},
  {'id': 'bs-2m',   'label': '2m – 25m',    'min': 2000000.0,    'max': 25000000.0},
  {'id': 'bs-20m',  'label': '20m – 250m',  'min': 20000000.0,   'max': 250000000.0},
  {'id': 'bs-200m', 'label': '200m+',       'min': 200000000.0,  'max': double.infinity},
];

class AppSettings {
  final int minPrice;
  final double minFF;
  final double maxFF;
  final int hospitalMaxMin;
  final int refreshSec;
  final bool includeUnknownFF;
  final bool revivableOnly;
  final List<String> bsRanges;
  final bool hospAlerts;
  final bool hideWarTargets;
  final bool markedAlerts;
  final int marketRefreshSec;

  const AppSettings({
    this.minPrice = 500000,
    this.minFF = 1.0,
    this.maxFF = 3.0,
    this.hospitalMaxMin = 5,
    this.refreshSec = 60,
    this.includeUnknownFF = false,
    this.revivableOnly = false,
    this.bsRanges = const [],
    this.hospAlerts = false,
    this.hideWarTargets = false,
    this.markedAlerts = false,
    this.marketRefreshSec = 0,
  });

  static const AppSettings defaults = AppSettings();

  AppSettings copyWith({
    int? minPrice,
    double? minFF,
    double? maxFF,
    int? hospitalMaxMin,
    int? refreshSec,
    bool? includeUnknownFF,
    bool? revivableOnly,
    List<String>? bsRanges,
    bool? hospAlerts,
    bool? hideWarTargets,
    bool? markedAlerts,
    int? marketRefreshSec,
  }) =>
      AppSettings(
        minPrice: minPrice ?? this.minPrice,
        minFF: minFF ?? this.minFF,
        maxFF: maxFF ?? this.maxFF,
        hospitalMaxMin: hospitalMaxMin ?? this.hospitalMaxMin,
        refreshSec: refreshSec ?? this.refreshSec,
        includeUnknownFF: includeUnknownFF ?? this.includeUnknownFF,
        revivableOnly: revivableOnly ?? this.revivableOnly,
        bsRanges: bsRanges ?? this.bsRanges,
        hospAlerts: hospAlerts ?? this.hospAlerts,
        hideWarTargets: hideWarTargets ?? this.hideWarTargets,
        markedAlerts: markedAlerts ?? this.markedAlerts,
        marketRefreshSec: marketRefreshSec ?? this.marketRefreshSec,
      );

  Map<String, dynamic> toJson() => {
        'minPrice': minPrice,
        'minFF': minFF,
        'maxFF': maxFF,
        'hospitalMaxMin': hospitalMaxMin,
        'refreshSec': refreshSec,
        'includeUnknownFF': includeUnknownFF,
        'revivableOnly': revivableOnly,
        'bsRanges': bsRanges,
        'hospAlerts': hospAlerts,
        'hideWarTargets': hideWarTargets,
        'markedAlerts': markedAlerts,
        'marketRefreshSec': marketRefreshSec,
      };

  String toJsonString() => jsonEncode(toJson());

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        minPrice: (j['minPrice'] as num?)?.toInt() ?? 500000,
        minFF: (j['minFF'] as num?)?.toDouble() ?? 1.0,
        maxFF: (j['maxFF'] as num?)?.toDouble() ?? 3.0,
        hospitalMaxMin: (j['hospitalMaxMin'] as num?)?.toInt() ?? 5,
        refreshSec: (j['refreshSec'] as num?)?.toInt() ?? 60,
        includeUnknownFF: j['includeUnknownFF'] as bool? ?? false,
        revivableOnly: j['revivableOnly'] as bool? ?? false,
        bsRanges: (j['bsRanges'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        hospAlerts: j['hospAlerts'] as bool? ?? false,
        hideWarTargets: j['hideWarTargets'] as bool? ?? false,
        markedAlerts: j['markedAlerts'] as bool? ?? false,
        marketRefreshSec: (j['marketRefreshSec'] as num?)?.toInt() ?? 0,
      );

  factory AppSettings.fromJsonString(String s) =>
      AppSettings.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
