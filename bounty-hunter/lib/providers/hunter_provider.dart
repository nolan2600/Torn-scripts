import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../models/app_settings.dart';
import '../models/bounty.dart';
import '../models/marked_target.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../services/notification_service.dart';
import 'settings_provider.dart';

enum RefreshState { idle, loading, success, error }

class HunterProvider extends ChangeNotifier {
  final SettingsProvider _settings;
  late TornApiService _api;

  HunterProvider(this._settings) {
    _api = TornApiService(_settings.tornKey);
    _loadTargets();
  }

  // ── State ──────────────────────────────────────────────────
  List<BountyEntry> bounties = [];
  Map<int, TargetStatus> targetStatuses = {};
  List<MarkedTarget> markedTargets = [];
  Set<String> bellIds = {};      // bounty target IDs with bell on
  Set<int> warFactionIds = {};
  RefreshState refreshState = RefreshState.idle;
  String? lastError;
  DateTime? lastRefreshAt;
  int? myUserId;
  int? myLevel;
  int? myAge;
  String? myCountry;

  bool _disposed = false;
  bool _refreshing = false;
  Timer? _refreshTimer;

  // ── Public helpers ─────────────────────────────────────────
  int get secondsUntilRefresh {
    if (_nextRefreshAt == null) return 0;
    return math.max(
        0,
        _nextRefreshAt!.difference(DateTime.now()).inSeconds);
  }

  DateTime? _nextRefreshAt;

  AppSettings get _s => _settings.settings;

  // ── Lifecycle ──────────────────────────────────────────────
  void onSettingsChanged() {
    _api.apiKey = _settings.tornKey;
    _restartTimer();
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    super.dispose();
  }

  void startPolling() {
    _restartTimer();
    if (bounties.isEmpty && _settings.hasKey) _tick();
  }

  void stopPolling() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  void _restartTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    final interval = _s.refreshSec;
    if (interval <= 0 || !_settings.hasKey) return;
    _refreshTimer = Timer.periodic(Duration(seconds: interval), (_) => _tick());
    _nextRefreshAt = DateTime.now().add(Duration(seconds: interval));
  }

  Future<void> _tick() async {
    if (!_settings.hasKey) return;
    await refresh();
    await refreshTargets();
  }

  // ── Bounty refresh ─────────────────────────────────────────
  Future<void> refresh() async {
    if (_disposed || _refreshing) return;
    _refreshing = true;
    _api.apiKey = _settings.tornKey;
    refreshState = RefreshState.loading;
    lastError = null;
    notifyListeners();

    try {
      // Validate key + get own identity
      try {
        final me = await _api.validateKey();
        myUserId = me.id;
        myLevel = me.level;
        myAge = me.age;
        myCountry = TornApiService.playerCountry(me.status);
      } catch (_) {}

      final result = await _api.fetchAllBounties();
      final raw = result.bounties;

      // Deduplicate — keep highest reward per target, sum counts
      final grouped = <int, BountyRaw>{};
      final counts = <int, int>{};
      for (final b in raw) {
        counts[b.targetId] = (counts[b.targetId] ?? 0) + b.quantity;
        if (!grouped.containsKey(b.targetId) ||
            b.reward > grouped[b.targetId]!.reward) {
          grouped[b.targetId] = b;
        }
      }

      // Basic filter: min reward + not self
      final byBasic = grouped.values
          .where((b) =>
              b.reward >= _s.minPrice &&
              (myUserId == null || b.targetId != myUserId))
          .toList();

      // FF scores
      final ffKey = _settings.ffKey;
      final ids = byBasic.map((b) => b.targetId).toList();
      final ffResult = await FFScouterService.fetchStats(ffKey, ids);
      final ffMap = ffResult.map;
      final includeUnknown = _s.includeUnknownFF || ffResult.error != null;

      // FF filter
      final byFF = byBasic.where((b) {
        final ff = ffMap[b.targetId]?.ff;
        if (ff == null) return includeUnknown;
        return ff >= _s.minFF && ff <= _s.maxFF;
      }).toList();

      // BS filter
      final selectedRanges = _s.bsRanges;
      final byBS = selectedRanges.isEmpty
          ? byFF
          : byFF.where((b) {
              final bsRaw = ffMap[b.targetId]?.bsEstimate;
              if (bsRaw == null) return true;
              final bsNum = _parseBs(bsRaw);
              if (bsNum == null) return true;
              return selectedRanges.any((rid) {
                final range = kBsRanges.firstWhere(
                    (r) => r['id'] == rid,
                    orElse: () => const {});
                if (range.isEmpty) return false;
                return bsNum >= (range['min'] as double) &&
                    bsNum <= (range['max'] as double);
              });
            }).toList();

      // Fetch profiles for status
      final warIds = await _fetchWarIds();
      warFactionIds = warIds;

      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final hospWindowSec = _s.hospitalMaxMin * 60;
      final matches = <BountyEntry>[];

      await _fetchProfilesBatched(byBS.map((b) => b.targetId).toList(),
          (id, profile) {
        final b = byBS.firstWhere((x) => x.targetId == id);
        final status = profile?.status;
        final state = status?['state'] as String?;
        final until = (status?['until'] as num?)?.toInt() ?? 0;
        final remaining = math.max(0, until - nowSec);
        final factionId = profile?.factionId;
        final inWar = factionId != null && warFactionIds.contains(factionId);
        final targetCountry = TornApiService.playerCountry(status);
        final ffData = ffMap[id];
        final bountyCount = counts[id] ?? 1;

        if (myCountry != null &&
            targetCountry != null &&
            targetCountry != myCountry) return;
        if (_s.hideWarTargets && inWar) return;

        if (state == 'Okay') {
          matches.add(BountyEntry(
            targetId: id,
            targetName: b.targetName,
            targetLevel: b.targetLevel,
            reward: b.reward,
            bountyCount: bountyCount,
            ff: ffData?.ff,
            bsEstimate: ffData?.bsEstimate,
            statusState: 'Okay',
            factionId: factionId,
            inFactionWar: inWar,
          ));
        } else if (state == 'Hospital' && remaining <= hospWindowSec) {
          final revivable = profile?.revivable;
          if (_s.revivableOnly && revivable != true) return;
          matches.add(BountyEntry(
            targetId: id,
            targetName: b.targetName,
            targetLevel: b.targetLevel,
            reward: b.reward,
            bountyCount: bountyCount,
            ff: ffData?.ff,
            bsEstimate: ffData?.bsEstimate,
            statusState: 'Hospital',
            hospUntil: until,
            revivable: revivable,
            factionId: factionId,
            inFactionWar: inWar,
          ));
        }
      });

      matches.sort((a, b) => b.reward.compareTo(a.reward));
      bounties = matches;
      lastRefreshAt = DateTime.now();
      refreshState = RefreshState.success;
      _scheduleHospitalAlerts();
    } catch (e) {
      if (e is TornApiException) {
        lastError = e.message;
      } else {
        final s = e.toString();
        if (s.contains('SocketException') || s.contains('ClientException') ||
            s.contains('SocketFailed') || s.contains('No address associated') ||
            s.contains('Failed host lookup') || s.contains('errno = 7')) {
          lastError = 'Network error — check your connection';
        } else {
          lastError = s.replaceFirst('Exception: ', '');
        }
      }
      refreshState = RefreshState.error;
    }

    _refreshing = false;
    if (!_disposed) {
      _nextRefreshAt = _s.refreshSec > 0
          ? DateTime.now().add(Duration(seconds: _s.refreshSec))
          : null;
      notifyListeners();
    }
  }

  // ── Profile batched fetch ──────────────────────────────────
  static const _concurrency = 3;
  final _profileCache = <int, ({UserProfile? profile, DateTime fetchedAt})>{};

  Future<void> _fetchProfilesBatched(
      List<int> ids, void Function(int, UserProfile?) callback) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final stale = <int>[];
    for (final id in ids.toSet()) {
      final c = _profileCache[id];
      if (c != null) {
        final isHosp = c.profile?.statusState == 'Hospital';
        final age = nowMs - c.fetchedAt.millisecondsSinceEpoch;
        if (isHosp || age < 20000) {
          callback(id, c.profile);
          continue;
        }
      }
      stale.add(id);
    }

    final idx = [0];
    await Future.wait(
      List.generate(_concurrency, (_) async {
        while (true) {
          final i = idx[0]++;
          if (i >= stale.length) break;
          final id = stale[i];
          final profile = await _api.fetchUserProfile(id);
          _profileCache[id] =
              (profile: profile, fetchedAt: DateTime.now());
          callback(id, profile);
        }
      }),
    );
  }

  Future<Set<int>> _fetchWarIds() async {
    if (!_settings.hasKey) return {};
    try {
      final wars = await _api.fetchGlobalWars();
      return wars.keys.toSet();
    } catch (_) {
      return warFactionIds; // return cached
    }
  }

  // ── Marked targets ─────────────────────────────────────────
  Future<void> _loadTargets() async {
    await StorageService.instance.init();
    final raw = StorageService.instance.getTargetsJson();
    if (raw != null && raw.isNotEmpty) {
      try {
        markedTargets = MarkedTarget.listFromJson(raw);
      } catch (_) {
        markedTargets = [];
      }
    }
    final savedBells = StorageService.instance.getAlertIds();
    bellIds = savedBells.toSet();
    notifyListeners();
  }

  Future<void> _saveTargets() async {
    await StorageService.instance
        .saveTargetsJson(MarkedTarget.listToJson(markedTargets));
  }

  void addTarget(MarkedTarget t) {
    if (markedTargets.any((x) => x.id == t.id)) return;
    markedTargets = [...markedTargets, t];
    _saveTargets();
    notifyListeners();
  }

  void removeTarget(int id) {
    markedTargets = markedTargets.where((t) => t.id != id).toList();
    _saveTargets();
    notifyListeners();
  }

  bool isMarked(int id) => markedTargets.any((t) => t.id == id);

  Future<void> refreshTargets() async {
    if (markedTargets.isEmpty || !_settings.hasKey) return;
    final ids = markedTargets.map((t) => t.id).toList();
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final Map<int, TargetStatus> newStatuses = {};
    final warIds = await _fetchWarIds();

    await _fetchProfilesBatched(ids, (id, profile) {
      if (profile == null) return;
      final status = profile.status;
      final state = status?['state'] as String?;
      final until = (status?['until'] as num?)?.toInt() ?? 0;
      final desc = status?['description'] as String? ?? '';
      final factionId = profile.factionId;
      final inWar = factionId != null && warIds.contains(factionId);

      int? landingTs;
      if (state == 'Traveling') {
        landingTs =
            TornApiService.computeLandingTs(desc, profile.plane);
        if ((landingTs ?? 0) <= nowSec) landingTs = null;
      }

      newStatuses[id] = TargetStatus(
        state: state,
        until: until,
        revivable: profile.revivable,
        inFactionWar: inWar,
        description: desc,
        landingTs: landingTs,
      );
    });

    // Update names from API
    final updatedTargets = markedTargets.map((t) {
      final c = _profileCache[t.id];
      final p = c?.profile;
      if (p != null && p.name.isNotEmpty && p.name != t.name) {
        return t.copyWith(name: p.name, level: p.level);
      }
      return t;
    }).toList();
    markedTargets = updatedTargets;
    _saveTargets();

    targetStatuses = newStatuses;
    _scheduleTargetAlerts();
    if (!_disposed) notifyListeners();
  }

  // ── Bell / alert toggles ───────────────────────────────────
  void toggleBell(int targetId) {
    final id = targetId.toString();
    if (bellIds.contains(id)) {
      bellIds = {...bellIds}..remove(id);
      NotificationService.instance.cancelNotification(targetId);
    } else {
      bellIds = {...bellIds, id};
    }
    StorageService.instance.saveAlertIds(bellIds.toList());
    _scheduleHospitalAlerts();
    notifyListeners();
  }

  bool isBellOn(int targetId) => bellIds.contains(targetId.toString());

  void _scheduleHospitalAlerts() {
    if (!_s.hospAlerts && bellIds.isEmpty) return;
    for (final b in bounties) {
      if (b.statusState != 'Hospital') continue;
      final shouldAlert =
          _s.hospAlerts || bellIds.contains(b.targetId.toString());
      if (!shouldAlert) continue;
      NotificationService.instance.scheduleHospitalAlert(
        notifId: b.targetId,
        targetName: b.targetName,
        targetId: b.targetId,
        hospUntilSec: b.hospUntil,
        reward: b.reward,
        ff: b.ff,
        revivable: b.revivable,
      );
    }
  }

  void _scheduleTargetAlerts() {
    if (!_s.markedAlerts) return;
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    for (final t in markedTargets) {
      final s = targetStatuses[t.id];
      if (s == null) continue;
      if (s.state == 'Hospital' && s.until > nowSec) {
        NotificationService.instance.scheduleHospitalAlert(
          notifId: 900000 + t.id,
          targetName: t.name,
          targetId: t.id,
          hospUntilSec: s.until,
          reward: null,
          ff: null,
          revivable: s.revivable,
        );
      } else if ((s.state == 'Traveling' || s.state == 'Abroad') &&
          (s.landingTs ?? 0) > nowSec) {
        NotificationService.instance.scheduleTravelAlert(
          notifId: 800000 + t.id,
          targetName: t.name,
          targetId: t.id,
          landingTs: s.landingTs!,
        );
      }
    }
  }

  static double? _parseBs(String? s) {
    if (s == null || s.isEmpty) return null;
    final m = RegExp(r'^([\d.]+)\s*([kKmMbB]?)').firstMatch(s.trim());
    if (m == null) return null;
    final n = double.tryParse(m.group(1)!);
    if (n == null) return null;
    final unit = m.group(2)!.toLowerCase();
    return n *
        (unit == 'k'
            ? 1e3
            : unit == 'm'
                ? 1e6
                : unit == 'b'
                    ? 1e9
                    : 1.0);
  }
}

// Extension to surface statusState from profile inside the provider
extension on UserProfile {
  String? get statusState => status?['state'] as String?;
  String get plane => status?['plane_image_type'] as String? ?? 'airliner';
}
