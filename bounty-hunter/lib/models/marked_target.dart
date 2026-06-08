import 'dart:convert';
import 'dart:math' as math;

class MarkedTarget {
  final int id;
  final String name;
  final int level;

  const MarkedTarget({
    required this.id,
    required this.name,
    required this.level,
  });

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'level': level};

  factory MarkedTarget.fromJson(Map<String, dynamic> j) => MarkedTarget(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String? ?? 'Player ${j['id']}',
        level: (j['level'] as num?)?.toInt() ?? 0,
      );

  MarkedTarget copyWith({String? name, int? level}) =>
      MarkedTarget(id: id, name: name ?? this.name, level: level ?? this.level);

  static List<MarkedTarget> listFromJson(String s) {
    final raw = jsonDecode(s) as List<dynamic>;
    return raw
        .map((e) => MarkedTarget.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static String listToJson(List<MarkedTarget> list) =>
      jsonEncode(list.map((t) => t.toJson()).toList());
}

class TargetStatus {
  final String? state;
  final int until;
  final bool? revivable;
  final bool inFactionWar;
  final String description;
  final int? landingTs;

  const TargetStatus({
    this.state,
    this.until = 0,
    this.revivable,
    this.inFactionWar = false,
    this.description = '',
    this.landingTs,
  });

  int get remaining {
    final end = (state == 'Traveling' || state == 'Abroad')
        ? (landingTs ?? 0)
        : until;
    return math.max(
        0, end - DateTime.now().millisecondsSinceEpoch ~/ 1000);
  }

  bool get isAttackable =>
      state == 'Okay' || state == 'Hospital';
}
