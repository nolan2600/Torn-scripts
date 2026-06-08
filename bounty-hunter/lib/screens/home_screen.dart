import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../providers/hunter_provider.dart';
import 'bounty_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF2A2A2A),
              ),
              child: const Center(
                child: Text('🎯', style: TextStyle(fontSize: 18)),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Bounty Hunter',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.grey),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
        elevation: 0,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: Color(0xFF2A2A2A)),
        ),
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          if (!settings.loaded) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Key status banner when no key
              if (!settings.hasKey) ...[
                _KeyBanner(onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                )),
                const SizedBox(height: 16),
              ],
              // Section label
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'FEATURES',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              // Bounty Hunter card
              _FeatureCard(
                icon: '💰',
                title: 'Bounty Hunter',
                subtitle: 'Live bounty board with FF filtering, hospital timers and marked targets',
                accentColor: const Color(0xFFEF5350),
                badgeBuilder: settings.hasKey
                    ? (ctx) => Consumer<HunterProvider>(
                          builder: (_, hunter, __) {
                            final count = hunter.bounties.length;
                            if (count == 0) return const SizedBox.shrink();
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEF5350),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$count',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            );
                          },
                        )
                    : null,
                onTap: () {
                  if (!settings.hasKey) {
                    Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const SettingsScreen()));
                    return;
                  }
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const BountyScreen()));
                },
              ),
              const SizedBox(height: 12),
              // Coming soon cards
              _ComingSoonCard(
                icon: '📊',
                title: 'Market Watch',
                subtitle: 'Track item prices and bazaar deals',
              ),
              const SizedBox(height: 12),
              _ComingSoonCard(
                icon: '⚔️',
                title: 'War Room',
                subtitle: 'Faction war tracker and member stats',
              ),
              const SizedBox(height: 12),
              _ComingSoonCard(
                icon: '🔍',
                title: 'Player Search',
                subtitle: 'Deep stats lookup and activity tracking',
              ),
              const SizedBox(height: 24),
              // Footer
              Center(
                child: Text(
                  'Bounty Hunter v1.0 · lannav + DieselBlade',
                  style: TextStyle(color: Colors.grey[700], fontSize: 11),
                ),
              ),
              const SizedBox(height: 8),
            ],
          );
        },
      ),
    );
  }
}

class _KeyBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _KeyBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF2A1A1A),
          border: Border.all(color: const Color(0xFFEF5350), width: 1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.key, color: Color(0xFFEF5350), size: 20),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Add your Torn API key in Settings to start hunting',
                style: TextStyle(color: Color(0xFFDDDDDD), fontSize: 13),
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[600], size: 18),
          ],
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final String icon;
  final String title;
  final String subtitle;
  final Color accentColor;
  final VoidCallback onTap;
  final Widget Function(BuildContext)? badgeBuilder;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.onTap,
    this.badgeBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(12),
          border: Border(left: BorderSide(color: accentColor, width: 3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(51),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: accentColor.withAlpha(26),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(child: Text(icon, style: const TextStyle(fontSize: 24))),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                      if (badgeBuilder != null) ...[
                        const SizedBox(width: 8),
                        badgeBuilder!(context),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style:
                          const TextStyle(color: Color(0xFF888888), fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[600]),
          ],
        ),
      ),
    );
  }
}

class _ComingSoonCard extends StatelessWidget {
  final String icon;
  final String title;
  final String subtitle;

  const _ComingSoonCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF242424),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
                child: Text(icon,
                    style: TextStyle(
                        fontSize: 22,
                        color: Colors.grey[800]))),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: Color(0xFF555555),
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('SOON',
                          style: TextStyle(
                              color: Color(0xFF555555),
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: const TextStyle(
                        color: Color(0xFF3A3A3A), fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
