import 'dart:convert';

class TornItem {
  final int id;
  final String name;
  final String type;
  final int marketValue;

  const TornItem({
    required this.id,
    required this.name,
    required this.type,
    required this.marketValue,
  });

  factory TornItem.fromJson(int id, Map<String, dynamic> j) => TornItem(
        id: id,
        name: j['name'] as String? ?? 'Unknown',
        type: j['type'] as String? ?? '',
        marketValue: (j['market_value'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'market_value': marketValue,
      };
}

class WatchedItem {
  final int id;
  final String name;
  final String type;
  final int marketValue;
  final int? alertThreshold;
  final bool alertAbove;

  const WatchedItem({
    required this.id,
    required this.name,
    required this.type,
    required this.marketValue,
    this.alertThreshold,
    this.alertAbove = false,
  });

  factory WatchedItem.fromJson(Map<String, dynamic> j) => WatchedItem(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String? ?? 'Unknown',
        type: j['type'] as String? ?? '',
        marketValue: (j['market_value'] as num?)?.toInt() ?? 0,
        alertThreshold: (j['alert_threshold'] as num?)?.toInt(),
        alertAbove: j['alert_above'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'market_value': marketValue,
        if (alertThreshold != null) 'alert_threshold': alertThreshold,
        if (alertAbove) 'alert_above': alertAbove,
      };

  static List<WatchedItem> listFromJson(String raw) {
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => WatchedItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static String listToJson(List<WatchedItem> items) =>
      jsonEncode(items.map((e) => e.toJson()).toList());
}

class PricePoint {
  final int timestamp;
  final int price;

  const PricePoint({required this.timestamp, required this.price});

  factory PricePoint.fromJson(Map<String, dynamic> j) => PricePoint(
        timestamp: (j['ts'] as num).toInt(),
        price: (j['price'] as num).toInt(),
      );

  Map<String, dynamic> toJson() => {'ts': timestamp, 'price': price};
}

class MarketListing {
  final int price;
  final int quantity;
  final String? sellerName;

  const MarketListing({
    required this.price,
    required this.quantity,
    this.sellerName,
  });
}

class LiveItemData {
  final int cheapestPrice;
  final List<MarketListing> listings;
  final DateTime fetchedAt;

  const LiveItemData({
    required this.cheapestPrice,
    required this.listings,
    required this.fetchedAt,
  });
}
