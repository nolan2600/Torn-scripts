import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/marked_target.dart';
import '../providers/hunter_provider.dart';

// ── Targets tab (used inside BountyScreen TabBarView) ──────
class TargetsTab extends StatelessWidget {
  const TargetsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<HunterProvider>(
      builder: (context, hunter, _) {
        final targets = hunter.markedTargets;
        if (targets.isEmpty) {
          return const _EmptyTargets();
        }
        return Column(
          children: [
            // Refresh bar
            Container(
              color: const Color(0xFF1A1A1A),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  Text('${targets.length} marked target${targets.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                          color: Color(0xFF888888), fontSize: 12)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => hunter.refreshTargets(),
                    child: const Text('Refresh',
                        style: TextStyle(
                            color: Color(0xFF4FC3F7), fontSize: 12)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: targets.length,
                itemBuilder: (ctx, i) => _TargetCard(
                  target: targets[i],
                  status: hunter.targetStatuses[targets[i].id],
                  hunter: hunter,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TargetCard extends StatefulWidget {
  final MarkedTarget target;
  final TargetStatus? status;
  final HunterProvider hunter;

  const _TargetCard({
    required this.target,
    required this.status,
    required this.hunter,
  });

  @override
  State<_TargetCard> createState() => _TargetCardState();
}

class _TargetCardState extends State<_TargetCard> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final s = widget.status;
    if (s != null &&
        (s.state == 'Hospital' || s.state == 'Traveling' || s.state == 'Abroad')) {
      _timer = Timer.periodic(
          const Duration(seconds: 1), (_) => setState(() {}));
    }
  }

  @override
  void didUpdateWidget(_TargetCard old) {
    super.didUpdateWidget(old);
    _timer?.cancel();
    final s = widget.status;
    if (s != null &&
        (s.state == 'Hospital' || s.state == 'Traveling' || s.state == 'Abroad')) {
      _timer = Timer.periodic(
          const Duration(seconds: 1), (_) => setState(() {}));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.target;
    final s = widget.status;
    final bellActive = widget.hunter.targetStatuses.containsKey(t.id) &&
        widget.hunter.isBellOn(t.id);
    final canAlert = s != null &&
        (s.state == 'Hospital' || s.state == 'Traveling' || s.state == 'Abroad');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(
            color: _accentColor(s?.state),
            width: 3,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: name + bell + remove
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          t.name,
                          style: const TextStyle(
                              color: Color(0xFF4FC3F7),
                              fontWeight: FontWeight.bold,
                              fontSize: 15),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text('L${t.level}',
                          style: const TextStyle(
                              color: Color(0xFF666666), fontSize: 11)),
                      if (s?.inFactionWar == true) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A2A3A),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: const Color(0xFF2A4A6A)),
                          ),
                          child: const Text('⚔️ War',
                              style: TextStyle(
                                  color: Color(0xFF64B5F6), fontSize: 10)),
                        ),
                      ],
                    ],
                  ),
                ),
                if (canAlert)
                  GestureDetector(
                    onTap: () => widget.hunter.toggleBell(t.id),
                    child: Container(
                      width: 30,
                      height: 30,
                      margin: const EdgeInsets.only(left: 8),
                      decoration: BoxDecoration(
                        color: bellActive
                            ? const Color(0xFF2A1E0A)
                            : const Color(0xFF252525),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: bellActive
                                ? const Color(0xFFFFB74D)
                                : const Color(0xFF3A3A3A)),
                      ),
                      child: Center(
                          child: Text(bellActive ? '🔔' : '🔕',
                              style: const TextStyle(fontSize: 13))),
                    ),
                  ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _confirmRemove(context, t),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF252525),
                      borderRadius: BorderRadius.circular(6),
                      border:
                          Border.all(color: const Color(0xFF3A3A3A)),
                    ),
                    child: const Text('✕',
                        style: TextStyle(
                            color: Color(0xFF888888), fontSize: 12)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Row 2: status + revive
            Row(
              children: [
                _StatusWidget(s: s),
                if (s?.state == 'Hospital') ...[
                  const SizedBox(width: 8),
                  _ReviveChip(revivable: s?.revivable),
                ],
              ],
            ),
            const SizedBox(height: 8),
            // Attack button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF5350),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(7)),
                  elevation: 0,
                ),
                onPressed: () => _openProfile(context, t.id),
                child: const Text('View Profile / Attack →',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _accentColor(String? state) {
    switch (state) {
      case 'Hospital':
        return const Color(0xFFFF8C00);
      case 'Traveling':
      case 'Abroad':
        return const Color(0xFF4FC3F7);
      case 'Okay':
        return const Color(0xFF4CAF50);
      default:
        return const Color(0xFF444444);
    }
  }

  Future<void> _confirmRemove(BuildContext context, MarkedTarget t) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Remove target',
            style: TextStyle(color: Colors.white)),
        content: Text('Remove ${t.name} from marked targets?',
            style: const TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove',
                style: TextStyle(color: Color(0xFFEF5350))),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      widget.hunter.removeTarget(t.id);
    }
  }

  Future<void> _openProfile(BuildContext context, int id) async {
    final uri = Uri.parse('https://www.torn.com/profiles.php?XID=$id');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _StatusWidget extends StatelessWidget {
  final TargetStatus? s;
  const _StatusWidget({required this.s});

  @override
  Widget build(BuildContext context) {
    if (s == null || s!.state == null) {
      return const _StatusChipW(label: 'Loading…', bg: Color(0xFF252525), fg: Color(0xFF666666));
    }
    final state = s!.state!;
    if (state == 'Okay') {
      return const _StatusChipW(
          label: '✓ Okay', bg: Color(0xFF1E3A2A), fg: Color(0xFF4CAF50));
    }
    if (state == 'Hospital') {
      final label = '🏥 ${_hospLabel(s!.remaining)}';
      return _StatusChipW(
          label: label, bg: const Color(0xFF3A2A1E), fg: const Color(0xFFFFB74D));
    }
    if (state == 'Traveling' || state == 'Abroad') {
      final dir = _travelLabel(s!.description, s!.landingTs);
      return _StatusChipW(
          label: dir,
          bg: const Color(0xFF1A2A3A),
          fg: const Color(0xFF4FC3F7));
    }
    if (state == 'Jail') {
      return const _StatusChipW(
          label: '🔒 Jailed', bg: Color(0xFF252525), fg: Color(0xFFAAAAAA));
    }
    return _StatusChipW(label: state, bg: const Color(0xFF252525), fg: Colors.grey);
  }

  static String _hospLabel(int rem) {
    if (rem <= 0) return 'out now';
    final h = rem ~/ 3600;
    final m = (rem % 3600) ~/ 60;
    final s = rem % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s.toString().padLeft(2, '0')}s';
    return '${s}s';
  }

  static String _travelLabel(String desc, int? landingTs) {
    final dest = _destShort(desc);
    if (landingTs == null) return '✈️ $dest';
    final rem = landingTs - DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (rem <= 0) return '✈️ $dest';
    final h = rem ~/ 3600;
    final m = (rem % 3600) ~/ 60;
    final s = rem % 60;
    final timeStr = h > 0 ? '${h}h ${m}m' : (m > 0 ? '${m}m ${s.toString().padLeft(2, '0')}s' : '${s}s');

    if (RegExp(r'returning to torn', caseSensitive: false).hasMatch(desc)) {
      return '✈️ ← $dest $timeStr';
    }
    return '✈️ → $dest $timeStr';
  }

  static String _destShort(String desc) {
    const map = {
      'Mexico': 'MEX', 'Cayman Islands': 'CAY', 'Canada': 'CAN',
      'Hawaii': 'HAW', 'United Kingdom': 'UK', 'Argentina': 'ARG',
      'Switzerland': 'SWI', 'Japan': 'JPN', 'China': 'CHI',
      'United Arab Emirates': 'UAE', 'South Africa': 'SA',
    };
    for (final e in map.entries) {
      if (desc.contains(e.key)) return e.value;
    }
    return 'Abroad';
  }
}

class _StatusChipW extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  const _StatusChipW({required this.label, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 12)),
    );
  }
}

class _ReviveChip extends StatelessWidget {
  final bool? revivable;
  const _ReviveChip({required this.revivable});

  @override
  Widget build(BuildContext context) {
    final emoji = revivable == true
        ? '💚'
        : revivable == false
            ? '❌'
            : '⚠️';
    return Text(emoji, style: const TextStyle(fontSize: 15));
  }
}

class _EmptyTargets extends StatelessWidget {
  const _EmptyTargets();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎯', style: TextStyle(fontSize: 52)),
            const SizedBox(height: 16),
            const Text('No marked targets',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Open a player\'s Torn profile and use the "Mark Target" option to track them here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
