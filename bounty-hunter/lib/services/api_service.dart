import 'dart:convert';
import 'package:http/http.dart' as http;

const _tornBase = 'https://api.torn.com/v2';
const _ffBase = 'https://ffscouter.com/api/v1';

const _hospitalAdjToCountry = {
  'Mexican': 'Mexico',
  'Caymanian': 'Cayman Islands',
  'Canadian': 'Canada',
  'Hawaiian': 'Hawaii',
  'British': 'United Kingdom',
  'Argentinian': 'Argentina',
  'Argentine': 'Argentina',
  'Swiss': 'Switzerland',
  'Japanese': 'Japan',
  'Chinese': 'China',
  'Emirati': 'United Arab Emirates',
  'South African': 'South Africa',
};

const _flightMins = {
  'Mexico':               {'light_aircraft': 18,  'airliner': 26,  'airliner_business': 8,   'private_jet': 13},
  'Cayman Islands':       {'light_aircraft': 25,  'airliner': 35,  'airliner_business': 11,  'private_jet': 18},
  'Canada':               {'light_aircraft': 29,  'airliner': 41,  'airliner_business': 12,  'private_jet': 20},
  'Hawaii':               {'light_aircraft': 94,  'airliner': 134, 'airliner_business': 40,  'private_jet': 67},
  'United Kingdom':       {'light_aircraft': 111, 'airliner': 159, 'airliner_business': 48,  'private_jet': 80},
  'Argentina':            {'light_aircraft': 117, 'airliner': 167, 'airliner_business': 50,  'private_jet': 83},
  'Switzerland':          {'light_aircraft': 123, 'airliner': 175, 'airliner_business': 53,  'private_jet': 88},
  'Japan':                {'light_aircraft': 158, 'airliner': 225, 'airliner_business': 68,  'private_jet': 113},
  'China':                {'light_aircraft': 169, 'airliner': 242, 'airliner_business': 72,  'private_jet': 121},
  'United Arab Emirates': {'light_aircraft': 190, 'airliner': 271, 'airliner_business': 81,  'private_jet': 135},
  'South Africa':         {'light_aircraft': 208, 'airliner': 297, 'airliner_business': 89,  'private_jet': 149},
};

class TornApiException implements Exception {
  final String message;
  final int? code;
  TornApiException(this.message, {this.code});
  @override
  String toString() => 'TornApiException: $message${code != null ? ' (code $code)' : ''}';
}

class UserProfile {
  final int id;
  final String name;
  final int level;
  final int age;
  final Map<String, dynamic>? status;
  final int? factionId;
  final bool? revivable;

  const UserProfile({
    required this.id,
    required this.name,
    required this.level,
    required this.age,
    this.status,
    this.factionId,
    this.revivable,
  });

  String? get statusState => status?['state'] as String?;
  int get hospUntil => (status?['until'] as num?)?.toInt() ?? 0;
  String get statusDescription => status?['description'] as String? ?? '';
  String? get plane => status?['plane_image_type'] as String?;
}

class FFData {
  final double ff;
  final String? bsEstimate;
  const FFData({required this.ff, this.bsEstimate});
}

class BountyRaw {
  final int targetId;
  final String targetName;
  final int targetLevel;
  final int reward;
  final int quantity;

  const BountyRaw({
    required this.targetId,
    required this.targetName,
    required this.targetLevel,
    required this.reward,
    required this.quantity,
  });
}

class TornApiService {
  String apiKey;
  DateTime _lastRequest = DateTime.fromMillisecondsSinceEpoch(0);
  static const _rateDelay = Duration(milliseconds: 750);

  TornApiService(this.apiKey);

  Future<void> _rateLimit() async {
    final wait = _rateDelay - DateTime.now().difference(_lastRequest);
    if (wait > Duration.zero) await Future.delayed(wait);
    _lastRequest = DateTime.now();
  }

  Future<Map<String, dynamic>> _get(String url) async {
    await _rateLimit();
    final uri = Uri.parse(url).replace(queryParameters: {
      ...Uri.parse(url).queryParameters,
      if (!Uri.parse(url).queryParameters.containsKey('key')) 'key': apiKey,
    });
    final res = await http.get(uri).timeout(const Duration(seconds: 20));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw TornApiException('HTTP ${res.statusCode}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (data.containsKey('error')) {
      final err = data['error'] as Map<String, dynamic>;
      final code = (err['code'] as num?)?.toInt();
      throw TornApiException(
          err['error'] as String? ?? 'API error', code: code);
    }
    return data;
  }

  Future<UserProfile> validateKey() async {
    final data = await _get('$_tornBase/user/profile?key=$apiKey');
    final p = (data['profile'] as Map<String, dynamic>?) ?? data;
    return _parseProfile(p);
  }

  Future<({List<BountyRaw> bounties, int delaySec})> fetchAllBounties() async {
    final allBounties = <BountyRaw>[];
    int delaySec = 0;
    int safety = 10;
    String? nextUrl =
        '$_tornBase/torn/bounties?limit=100&offset=0&key=$apiKey';

    while (nextUrl != null && safety-- > 0) {
      final data = await _get(nextUrl);
      final raw = data['bounties'] as List<dynamic>?;
      if (raw != null) {
        for (final b in raw) {
          final m = b as Map<String, dynamic>;
          allBounties.add(BountyRaw(
            targetId: (m['target_id'] as num).toInt(),
            targetName: m['target_name'] as String? ?? 'Unknown',
            targetLevel: (m['target_level'] as num?)?.toInt() ?? 0,
            reward: (m['reward'] as num?)?.toInt() ?? 0,
            quantity: (m['quantity'] as num?)?.toInt() ?? 1,
          ));
        }
      }
      if (data.containsKey('bounties_delay')) {
        delaySec = (data['bounties_delay'] as num).toInt();
      }
      final meta = data['_metadata'] as Map<String, dynamic>?;
      final links = meta?['links'] as Map<String, dynamic>?;
      nextUrl = links?['next'] as String?;
      if (raw == null || raw.isEmpty) nextUrl = null;
    }

    return (bounties: allBounties, delaySec: delaySec);
  }

  Future<UserProfile?> fetchUserProfile(int id) async {
    try {
      final data = await _get('$_tornBase/user/$id/profile?key=$apiKey');
      final p = (data['profile'] as Map<String, dynamic>?) ?? data;
      return _parseProfile(p);
    } catch (_) {
      return null;
    }
  }

  Future<Map<int, Map<String, dynamic>>> fetchGlobalWars() async {
    try {
      final data = await _get(
          'https://api.torn.com/torn/?selections=rankedwars,territorywars&key=$apiKey');
      final warIds = <int>{};
      for (final war
          in (data['rankedwars'] as Map<String, dynamic>? ?? {}).values) {
        final w = war as Map<String, dynamic>;
        for (final fid
            in (w['factions'] as Map<String, dynamic>? ?? {}).keys) {
          final n = int.tryParse(fid);
          if (n != null && n > 0) warIds.add(n);
        }
      }
      for (final war
          in (data['territorywars'] as Map<String, dynamic>? ?? {}).values) {
        final w = war as Map<String, dynamic>;
        for (final key in ['assaulting_faction', 'defending_faction']) {
          final fid = (w[key] as num?)?.toInt();
          if (fid != null && fid > 0) warIds.add(fid);
        }
      }
      return {for (final id in warIds) id: {}};
    } catch (_) {
      return {};
    }
  }

  UserProfile _parseProfile(Map<String, dynamic> p) {
    final faction = p['faction'] as Map<String, dynamic>?;
    final factionId = (faction?['id'] as num?)?.toInt() ??
        (faction?['faction_id'] as num?)?.toInt() ??
        (p['faction_id'] as num?)?.toInt();
    return UserProfile(
      id: (p['id'] as num).toInt(),
      name: p['name'] as String? ?? p['player_name'] as String? ?? '',
      level: (p['level'] as num?)?.toInt() ?? 0,
      age: (p['age'] as num?)?.toInt() ?? 0,
      status: p['status'] as Map<String, dynamic>?,
      factionId: factionId,
      revivable: p['revivable'] as bool?,
    );
  }

  static String? playerCountry(Map<String, dynamic>? status) {
    if (status == null) return null;
    final state = status['state'] as String?;
    final desc = status['description'] as String? ?? '';
    if (state == 'Okay' || state == 'Jail' || state == 'Federal') {
      return 'Torn';
    }
    if (state == 'Abroad') {
      final m = RegExp(r'^In\s+(.+)$').firstMatch(desc);
      return m?.group(1)?.trim();
    }
    if (state == 'Hospital') {
      if (RegExp(r'^In hospital\b', caseSensitive: false).hasMatch(desc)) {
        return 'Torn';
      }
      final m =
          RegExp(r'^In an?\s+(.+?)\s+hospital\b', caseSensitive: false)
              .firstMatch(desc);
      if (m != null) return _hospitalAdjToCountry[m.group(1)?.trim()];
    }
    return null;
  }

  static int computeLandingTs(String desc, String? plane) {
    final country = _resolveCountry(desc);
    if (country == null) return 0;
    final durations = _flightMins[country];
    if (durations == null) return 0;
    final mins = durations[plane] ?? durations['airliner'] ?? 0;
    if (mins == 0) return 0;
    return DateTime.now().millisecondsSinceEpoch ~/ 1000 + mins * 60;
  }

  static String? _resolveCountry(String desc) {
    final d = desc.toLowerCase();
    for (final name in _flightMins.keys) {
      if (d.contains(name.toLowerCase())) return name;
    }
    if (d.contains('mex')) return 'Mexico';
    if (d.contains('cayman')) return 'Cayman Islands';
    if (d.contains('hawaii')) return 'Hawaii';
    if (d.contains('united kingdom') || d.contains('london')) {
      return 'United Kingdom';
    }
    if (d.contains('argentin')) return 'Argentina';
    if (d.contains('swiss')) return 'Switzerland';
    if (d.contains('japan')) return 'Japan';
    if (d.contains('china')) return 'China';
    if (d.contains('emirates') || d.contains('dubai')) {
      return 'United Arab Emirates';
    }
    if (d.contains('south africa')) return 'South Africa';
    return null;
  }
}

class FFScouterService {
  static Future<({Map<int, FFData> map, String? error})> fetchStats(
      String key, List<int> userIds) async {
    if (key.isEmpty) return (map: {}, error: 'no_key');
    if (userIds.isEmpty) return (map: {}, error: null);

    final map = <int, FFData>{};
    String? error;

    for (var i = 0; i < userIds.length; i += 200) {
      final chunk = userIds.skip(i).take(200).join(',');
      final url =
          '$_ffBase/get-stats?key=${Uri.encodeComponent(key)}&targets=$chunk';
      try {
        final res = await http.get(Uri.parse(url)).timeout(
            const Duration(seconds: 20));
        if (res.statusCode < 200 || res.statusCode >= 300) {
          error = 'HTTP ${res.statusCode}';
          continue;
        }
        final data = jsonDecode(res.body);
        if (data is! List) {
          error = 'unexpected_response';
          continue;
        }
        for (final p in data) {
          final pm = p as Map<String, dynamic>;
          final ff = (pm['fair_fight'] as num?)?.toDouble();
          if (ff == null) continue;
          final id = (pm['player_id'] as num).toInt();
          map[id] = FFData(
              ff: ff, bsEstimate: pm['bs_estimate_human'] as String?);
        }
      } catch (e) {
        error = e.toString();
      }
    }

    return (map: map, error: error);
  }

  static Future<({bool ok, String message})> validateKey(String key) async {
    if (!RegExp(r'^[A-Za-z0-9]{16}$').hasMatch(key)) {
      return (ok: false, message: 'Must be 16 alphanumeric characters.');
    }
    try {
      final res = await http
          .get(Uri.parse('$_ffBase/check-key?key=${Uri.encodeComponent(key)}'))
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data.containsKey('code')) {
        return (ok: false, message: data['error'] as String? ?? 'Invalid key');
      }
      if (data['is_registered'] != true) {
        return (ok: false, message: 'Not registered — sign up at ffscouter.com');
      }
      final premium = data['is_premium'] == true;
      return (ok: true, message: premium ? 'Valid — premium.' : 'Valid.');
    } catch (e) {
      return (ok: false, message: 'Could not reach FFScouter: $e');
    }
  }
}
