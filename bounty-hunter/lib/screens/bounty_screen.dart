import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/bounty.dart';
import '../providers/hunter_provider.dart';
import '../providers/settings_provider.dart';
import 'targets_screen.dart';

class BountyScreen extends StatefulWidget {
  const BountyScreen({super.key});

  @override
  State<BountyScreen> createState() => _BountyScreenState();
}

class _BountyScreenState extends State<BountyScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _countdownTimer = Timer.periodic(
        const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tabs.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<HunterProvider, SettingsProvider>(
      builder: (context, hunter, settings, _) {
        final bountyCount = hunter.bounties.length;
        final targetCount = hunter.markedTargets.length;

        return Scaffold(
          backgroundColor: const Color(0xFF121212),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1A1A1A),
            title: const Text('Bounty Hunter',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18)),
            // title kept as "Bounty Hunter" — the feature name, not the app name
            bottom: TabBar(
              controller: _tabs,
              indicatorColor: const Color(0xFFEF5350),
              labelColor: const Color(0xFFEF5350),
              unselectedLabelColor: Colors.grey,
              tabs: [
                Tab(text: 'Hunt ($bountyCount)'),
                Tab(text: 'Targets ($targetCount)'),
              ],
            ),
            actions: [
              // Countdown + refresh
              if (hunter.refreshState == RefreshState.loading)
                const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.grey),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: TextButton(
                    onPressed: () => hunter.refresh(),
                    child: Text(
                      hunter.secondsUntilRefresh > 0
                          ? '${hunter.secondsUntilRefresh}s'
                          : 'Refresh',
                      style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
            ],
          ),
          body: TabBarView(
            controller: _tabs,
            children: [
              _HuntTab(hunter: hunter, settings: settings),
              const TargetsTab(),
            ],
          ),
        );
      },
    );
  }
}

enum _SortBy { reward, time, ff }

class _HuntTab extends StatefulWidget {
  final HunterProvider hunter;
  final SettingsProvider settings;

  const _HuntTab({required this.hunter, required this.settings});

  @override
  State<_HuntTab> createState() => _HuntTabState();
}

class _HuntTabState extends State<_HuntTab> {
  _SortBy _sort = _SortBy.reward;

  List<BountyEntry> _sorted(List<BountyEntry> src) {
    final list = List<BountyEntry>.from(src);
    switch (_sort) {
      case _SortBy.reward:
        list.sort((a, b) => b.reward.compareTo(a.reward));
      case _SortBy.time:
        list.sort((a, b) {
          final aH = a.statusState == 'Hospital';
          final bH = b.statusState == 'Hospital';
          if (aH && !bH) return -1;
          if (!aH && bH) return 1;
          if (aH && bH) return a.hospRemaining.compareTo(b.hospRemaining);
          return b.reward.compareTo(a.reward);
        });
      case _SortBy.ff:
        list.sort((a, b) {
          if (a.ff == null && b.ff == null) return 0;
          if (a.ff == null) return 1;
          if (b.ff == null) return -1;
          return a.ff!.compareTo(b.ff!);
        });
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final hunter = widget.hunter;
    final settings = widget.settings;

    if (hunter.refreshState == RefreshState.error && hunter.bounties.isEmpty) {
      return _ErrorView(
          message: hunter.lastError ?? 'Unknown error',
          onRetry: () => hunter.refresh());
    }

    if (hunter.refreshState == RefreshState.idle ||
        (hunter.refreshState == RefreshState.loading &&
            hunter.bounties.isEmpty)) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFFEF5350)),
            SizedBox(height: 16),
            Text('Fetching bounties…',
                style: TextStyle(color: Colors.grey, fontSize: 14)),
          ],
        ),
      );
    }

    final sorted = _sorted(hunter.bounties);

    return Column(
      children: [
        if (hunter.lastError != null)
          _ErrorBanner(message: hunter.lastError!),
        _FilterBar(settings: settings),
        _SortBar(current: _sort, onChanged: (s) => setState(() => _sort = s)),
        Expanded(
          child: sorted.isEmpty
              ? const _EmptyBounties()
              : ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: sorted.length,
                  itemBuilder: (ctx, i) => _BountyCard(
                        bounty: sorted[i],
                        hunter: hunter,
                      ),
                ),
        ),
      ],
    );
  }
}

class _SortBar extends StatelessWidget {
  final _SortBy current;
  final void Function(_SortBy) onChanged;
  const _SortBar({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF161616),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Text('Sort:',
              style: TextStyle(color: Colors.grey[600], fontSize: 11)),
          const SizedBox(width: 8),
          _SortChip(
            label: '💰 Reward',
            active: current == _SortBy.reward,
            onTap: () => onChanged(_SortBy.reward),
          ),
          const SizedBox(width: 6),
          _SortChip(
            label: '⏱ Time',
            active: current == _SortBy.time,
            onTap: () => onChanged(_SortBy.time),
          ),
          const SizedBox(width: 6),
          _SortChip(
            label: '⚔ FF',
            active: current == _SortBy.ff,
            onTap: () => onChanged(_SortBy.ff),
          ),
        ],
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _SortChip(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF3A1A1A) : const Color(0xFF222222),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color:
                active ? const Color(0xFFEF5350) : const Color(0xFF333333),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight:
                active ? FontWeight.w700 : FontWeight.normal,
            color:
                active ? const Color(0xFFEF5350) : Colors.grey[500],
          ),
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final SettingsProvider settings;
  const _FilterBar({required this.settings});

  @override
  Widget build(BuildContext context) {
    final s = settings.settings;
    return Container(
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          _Chip(label: '\$${_fmtShort(s.minPrice)}+'),
          const SizedBox(width: 6),
          _Chip(label: 'FF ${s.minFF.toStringAsFixed(1)}–${s.maxFF.toStringAsFixed(1)}'),
          const SizedBox(width: 6),
          _Chip(
              label: s.hospitalMaxMin == 0
                  ? 'Okay only'
                  : '≤${s.hospitalMaxMin}m hosp'),
          const Spacer(),
          if (!settings.hasFFKey)
            const _Chip(label: 'No FF key', isWarning: true),
        ],
      ),
    );
  }

  static String _fmtShort(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}K';
    return n.toString();
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool isWarning;
  const _Chip({required this.label, this.isWarning = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isWarning
            ? const Color(0xFF3A2800)
            : const Color(0xFF252525),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: isWarning
                ? const Color(0xFF996600)
                : const Color(0xFF3A3A3A)),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 11,
            color: isWarning ? const Color(0xFFFFB74D) : Colors.grey[400]),
      ),
    );
  }
}

extension on SettingsProvider {
  bool get hasFFKey => ffKey.isNotEmpty;
}

class _BountyCard extends StatefulWidget {
  final BountyEntry bounty;
  final HunterProvider hunter;

  const _BountyCard({required this.bounty, required this.hunter});

  @override
  State<_BountyCard> createState() => _BountyCardState();
}

class _BountyCardState extends State<_BountyCard> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.bounty.statusState == 'Hospital') {
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
    final b = widget.bounty;
    final isHosp = b.statusState == 'Hospital';
    final bell = widget.hunter.isBellOn(b.targetId);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(
            color: isHosp
                ? const Color(0xFFFF8C00)
                : const Color(0xFF4CAF50),
            width: 3,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: name + reward
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          b.targetName,
                          style: const TextStyle(
                              color: Color(0xFF4FC3F7),
                              fontWeight: FontWeight.bold,
                              fontSize: 15),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text('L${b.targetLevel}',
                          style: const TextStyle(
                              color: Color(0xFF666666), fontSize: 11)),
                      if (b.bountyCount > 1) ...[
                        const SizedBox(width: 6),
                        _CountBadge(b.bountyCount),
                      ],
                      if (b.inFactionWar) ...[
                        const SizedBox(width: 6),
                        const _WarBadge(),
                      ],
                    ],
                  ),
                ),
                Text(
                  _fmtMoney(b.reward),
                  style: const TextStyle(
                      color: Color(0xFF4CAF50),
                      fontWeight: FontWeight.bold,
                      fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Row 2: chips
            Row(
              children: [
                _InfoChip(
                    label: 'FF ${b.ff == null ? '?' : b.ff!.toStringAsFixed(2)}'),
                if (b.bsEstimate != null) ...[
                  const SizedBox(width: 6),
                  _InfoChip(label: 'BS ${b.bsEstimate}'),
                ],
                const SizedBox(width: 6),
                _StatusChip(b: b),
                if (isHosp) ...[
                  const SizedBox(width: 6),
                  _ReviveChip(revivable: b.revivable),
                ],
                const Spacer(),
                // Bell (hospital only)
                if (isHosp)
                  GestureDetector(
                    onTap: () => widget.hunter.toggleBell(b.targetId),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: bell
                            ? const Color(0xFF2A1E0A)
                            : const Color(0xFF252525),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: bell
                                ? const Color(0xFFFFB74D)
                                : const Color(0xFF3A3A3A)),
                      ),
                      child: Center(
                          child: Text(bell ? '🔔' : '🔕',
                              style: const TextStyle(fontSize: 14))),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // Row 3: attack button
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
                onPressed: () => _openProfile(context, b.targetId),
                child: const Text('View Profile / Attack →',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openProfile(BuildContext context, int id) async {
    final uri =
        Uri.parse('https://www.torn.com/profiles.php?XID=$id');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not open Torn PDA / browser.'),
          backgroundColor: Color(0xFF333333),
        ));
      }
    }
  }

  static String _fmtMoney(int n) {
    if (n >= 1000000000) return '\$${(n / 1e9).toStringAsFixed(2)}B';
    if (n >= 1000000) return '\$${(n / 1e6).toStringAsFixed(2)}M';
    if (n >= 1000) return '\$${(n / 1e3).toStringAsFixed(1)}K';
    return '\$$n';
  }
}

class _StatusChip extends StatelessWidget {
  final BountyEntry b;
  const _StatusChip({required this.b});

  @override
  Widget build(BuildContext context) {
    final isHosp = b.statusState == 'Hospital';
    if (!isHosp) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF1E3A2A),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Text('Okay',
            style: TextStyle(color: Color(0xFF4CAF50), fontSize: 11)),
      );
    }
    final rem = b.hospRemaining;
    final label = _hospLabel(rem);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF3A2A1E),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text('🏥 $label',
          style: const TextStyle(color: Color(0xFFFFB74D), fontSize: 11)),
    );
  }

  static String _hospLabel(int rem) {
    if (rem <= 0) return 'out';
    final h = rem ~/ 3600;
    final m = (rem % 3600) ~/ 60;
    final s = rem % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s.toString().padLeft(2, '0')}s';
    return '${s}s';
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  const _InfoChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF252525),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF3A3A3A)),
      ),
      child: Text(label,
          style: const TextStyle(color: Color(0xFFBBBBBB), fontSize: 11)),
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

class _CountBadge extends StatelessWidget {
  final int count;
  const _CountBadge(this.count);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xFF3A2A4A),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('×$count',
          style: const TextStyle(
              color: Color(0xFFC49CFF),
              fontSize: 10,
              fontWeight: FontWeight.bold)),
    );
  }
}

class _WarBadge extends StatelessWidget {
  const _WarBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2A3A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2A4A6A)),
      ),
      child: const Text('⚔️',
          style: TextStyle(fontSize: 10)),
    );
  }
}

class _EmptyBounties extends StatelessWidget {
  const _EmptyBounties();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('😴', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            const Text('No bounties match your filters',
                style: TextStyle(
                    color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Try lowering the minimum reward, widening FF range, or increasing the hospital time window in Settings.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFEF5350), size: 48),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF5350)),
              onPressed: onRetry,
              child: const Text('Retry', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: const Color(0xFF2A1414),
      child: Row(
        children: [
          const Icon(Icons.warning_amber,
              color: Color(0xFFEF5350), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: const TextStyle(
                    color: Color(0xFFEF5350), fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
