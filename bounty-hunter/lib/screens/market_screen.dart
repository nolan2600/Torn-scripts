import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/market_models.dart';
import '../providers/market_provider.dart';

String _fmt(int n) {
  if (n >= 1000000000) return '\$${(n / 1e9).toStringAsFixed(2)}B';
  if (n >= 1000000) return '\$${(n / 1e6).toStringAsFixed(2)}M';
  if (n >= 1000) return '\$${(n / 1e3).toStringAsFixed(1)}K';
  return '\$$n';
}

String _timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

// ── Screen ─────────────────────────────────────────────────

class MarketScreen extends StatefulWidget {
  const MarketScreen({super.key});

  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final market = context.read<MarketProvider>();
      market.ensureItemsCache().then((_) {
        if (mounted) market.refreshWatchlist();
      });
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Market Watch',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
        ),
        elevation: 0,
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'WATCHLIST'),
            Tab(text: 'FLIP CALC'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _WatchlistTab(),
          _FlipTab(),
        ],
      ),
    );
  }
}

// ── Watchlist Tab ──────────────────────────────────────────

class _WatchlistTab extends StatefulWidget {
  const _WatchlistTab();

  @override
  State<_WatchlistTab> createState() => _WatchlistTabState();
}

class _WatchlistTabState extends State<_WatchlistTab> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MarketProvider>(
      builder: (_, market, __) {
        final searching = _query.isNotEmpty;
        final results = searching ? market.searchItems(_query) : <TornItem>[];

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search items to add to watchlist...',
                  hintStyle: const TextStyle(color: Color(0xFF666666)),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF666666)),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Color(0xFF666666)),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: const Color(0xFF1E1E1E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF4CAF50)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
            ),

            if (market.cacheLoading)
              const LinearProgressIndicator(
                backgroundColor: Color(0xFF1E1E1E),
                color: Color(0xFF4CAF50),
                minHeight: 2,
              ),

            if (!market.cacheLoading && market.cacheError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(
                  'Could not load items: ${market.cacheError}',
                  style: const TextStyle(color: Colors.orange, fontSize: 12),
                ),
              ),

            Expanded(
              child: searching
                  ? _SearchResults(
                      results: results,
                      market: market,
                      onAdd: (item) {
                        market.addToWatchlist(item);
                        _searchCtrl.clear();
                        setState(() => _query = '');
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('${item.name} added to watchlist'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                    )
                  : _WatchlistView(market: market),
            ),
          ],
        );
      },
    );
  }
}

class _SearchResults extends StatelessWidget {
  final List<TornItem> results;
  final MarketProvider market;
  final void Function(TornItem) onAdd;

  const _SearchResults({
    required this.results,
    required this.market,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return const Center(
        child: Text('No items found', style: TextStyle(color: Color(0xFF666666))),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final item = results[i];
        final watched = market.isWatched(item.id);
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(10),
          ),
          child: ListTile(
            dense: true,
            title: Text(
              item.name,
              style: TextStyle(
                color: watched ? const Color(0xFF4CAF50) : Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            subtitle: item.type.isNotEmpty
                ? Text(item.type,
                    style: const TextStyle(color: Color(0xFF888888), fontSize: 11))
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.marketValue > 0)
                  Text(
                    _fmt(item.marketValue),
                    style: const TextStyle(color: Color(0xFF888888), fontSize: 12),
                  ),
                const SizedBox(width: 8),
                watched
                    ? const Icon(Icons.check_circle,
                        color: Color(0xFF4CAF50), size: 22)
                    : GestureDetector(
                        onTap: () => onAdd(item),
                        child: const Icon(Icons.add_circle_outline,
                            color: Color(0xFF4CAF50), size: 22),
                      ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _WatchlistView extends StatelessWidget {
  final MarketProvider market;

  const _WatchlistView({required this.market});

  @override
  Widget build(BuildContext context) {
    if (market.watchedItems.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storefront_outlined, color: Color(0xFF333333), size: 64),
            SizedBox(height: 12),
            Text('No items watched',
                style: TextStyle(color: Color(0xFF555555), fontSize: 16)),
            SizedBox(height: 4),
            Text('Search above to add items to track',
                style: TextStyle(color: Color(0xFF444444), fontSize: 12)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: const Color(0xFF4CAF50),
      backgroundColor: const Color(0xFF1E1E1E),
      onRefresh: market.refreshWatchlist,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: market.watchedItems.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final item = market.watchedItems[i];
          return _WatchedItemCard(
            item: item,
            live: market.liveData[item.id],
            history: market.priceHistory[item.id] ?? [],
            isRefreshing: market.marketRefreshing,
            market: market,
          );
        },
      ),
    );
  }
}

class _WatchedItemCard extends StatelessWidget {
  final WatchedItem item;
  final LiveItemData? live;
  final List<PricePoint> history;
  final bool isRefreshing;
  final MarketProvider market;

  const _WatchedItemCard({
    required this.item,
    required this.live,
    required this.history,
    required this.isRefreshing,
    required this.market,
  });

  @override
  Widget build(BuildContext context) {
    final cheapest = live?.cheapestPrice ?? 0;
    final mv = item.marketValue;
    final pctVsMv =
        mv > 0 && cheapest > 0 ? ((cheapest - mv) / mv * 100) : null;

    return Dismissible(
      key: Key('watched_${item.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.shade900,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) {
        market.removeFromWatchlist(item.id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${item.name} removed'),
            duration: const Duration(seconds: 2),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(12),
          border: const Border(
            left: BorderSide(color: Color(0xFF4CAF50), width: 3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      _TypeBadge(type: item.type),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => _showAlertDialog(context),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: item.alertThreshold != null
                          ? const Color(0xFF4CAF50).withAlpha(30)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      item.alertThreshold != null
                          ? Icons.notifications_active
                          : Icons.notifications_none,
                      color: item.alertThreshold != null
                          ? const Color(0xFF4CAF50)
                          : const Color(0xFF666666),
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (isRefreshing && live == null)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF4CAF50),
                    ),
                  )
                else if (cheapest > 0) ...[
                  Text(
                    _fmt(cheapest),
                    style: const TextStyle(
                      color: Color(0xFF4CAF50),
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (pctVsMv != null) _PctBadge(pct: pctVsMv),
                ] else
                  const Text('—',
                      style: TextStyle(color: Color(0xFF666666), fontSize: 16)),
                const Spacer(),
                if (history.length >= 2) _Sparkline(history: history),
              ],
            ),
            if (live != null) ...[
              const SizedBox(height: 4),
              Text(
                'Updated ${_timeAgo(live!.fetchedAt)}',
                style: const TextStyle(color: Color(0xFF444444), fontSize: 10),
              ),
            ],
            if (item.alertThreshold != null)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Row(
                  children: [
                    const Icon(Icons.alarm, color: Color(0xFF4CAF50), size: 12),
                    const SizedBox(width: 4),
                    Text(
                      'Alert ≤ ${_fmt(item.alertThreshold!)}',
                      style: const TextStyle(
                          color: Color(0xFF4CAF50), fontSize: 11),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showAlertDialog(BuildContext context) {
    final ctrl = TextEditingController(
      text: item.alertThreshold?.toString() ?? '',
    );
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text('Price alert — ${item.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Notify when cheapest listing drops to or below:',
              style: TextStyle(color: Color(0xFF888888), fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Price in \$',
                hintStyle: TextStyle(color: Color(0xFF666666)),
                prefixText: '\$ ',
                prefixStyle: TextStyle(color: Color(0xFF4CAF50)),
              ),
            ),
          ],
        ),
        actions: [
          if (item.alertThreshold != null)
            TextButton(
              onPressed: () {
                market.setAlertThreshold(item.id, null);
                Navigator.pop(context);
              },
              child: const Text('Clear', style: TextStyle(color: Color(0xFFEF5350))),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final v = int.tryParse(ctrl.text);
              if (v != null && v > 0) market.setAlertThreshold(item.id, v);
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

// ── Shared widgets ─────────────────────────────────────────

class _TypeBadge extends StatelessWidget {
  final String type;
  const _TypeBadge({required this.type});

  static Color _color(String t) {
    switch (t.toLowerCase()) {
      case 'drug':
        return Colors.purple;
      case 'weapon':
        return Colors.orange;
      case 'armor':
        return Colors.blue;
      case 'supply pack':
        return Colors.teal;
      case 'booster':
        return Colors.pink;
      case 'temporary':
        return Colors.cyan;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (type.isEmpty) return const SizedBox.shrink();
    final c = _color(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withAlpha(40),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.withAlpha(80), width: 0.5),
      ),
      child: Text(
        type.toUpperCase(),
        style: TextStyle(
          color: c,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _PctBadge extends StatelessWidget {
  final double pct;
  const _PctBadge({required this.pct});

  @override
  Widget build(BuildContext context) {
    final isNeg = pct < 0;
    final color =
        isNeg ? const Color(0xFF4CAF50) : const Color(0xFFEF5350);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '${isNeg ? '' : '+'}${pct.toStringAsFixed(1)}%',
        style: TextStyle(
            color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _Sparkline extends StatelessWidget {
  final List<PricePoint> history;
  const _Sparkline({required this.history});

  @override
  Widget build(BuildContext context) {
    final pts = history.length > 7
        ? history.sublist(history.length - 7)
        : history;
    final prices = pts.map((p) => p.price).toList();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(prices.length, (i) {
        final Color c;
        if (i == 0) {
          c = Colors.grey;
        } else if (prices[i] < prices[i - 1]) {
          c = const Color(0xFF4CAF50);
        } else if (prices[i] > prices[i - 1]) {
          c = const Color(0xFFEF5350);
        } else {
          c = Colors.grey;
        }
        return Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        );
      }),
    );
  }
}

// ── Flip Calc Tab ──────────────────────────────────────────

class _FlipTab extends StatefulWidget {
  const _FlipTab();

  @override
  State<_FlipTab> createState() => _FlipTabState();
}

class _FlipTabState extends State<_FlipTab> {
  final _searchCtrl = TextEditingController();
  final _buyPriceCtrl = TextEditingController();
  String _query = '';
  bool _searching = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _buyPriceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MarketProvider>(
      builder: (_, market, __) {
        final item = market.flipItem;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Item search field
              TextField(
                controller: _searchCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: item == null
                      ? 'Search item to flip...'
                      : 'Change item...',
                  hintStyle: const TextStyle(color: Color(0xFF666666)),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF666666)),
                  suffixIcon: item != null
                      ? IconButton(
                          icon: const Icon(Icons.close,
                              color: Color(0xFF666666)),
                          onPressed: () {
                            market.clearFlipItem();
                            _searchCtrl.clear();
                            _buyPriceCtrl.clear();
                            setState(() {
                              _query = '';
                              _searching = false;
                            });
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: const Color(0xFF1E1E1E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        const BorderSide(color: Color(0xFFEF5350)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onChanged: (v) => setState(() {
                  _query = v.trim();
                  _searching = v.isNotEmpty;
                }),
                onTap: () {
                  if (_query.isEmpty) setState(() => _searching = false);
                },
              ),

              // Inline search results
              if (_searching && _query.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 280),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF2A2A2A)),
                  ),
                  child: _buildSearchDropdown(context, market),
                ),
              ],

              // Flip calculator once item selected
              if (item != null && !_searching) ...[
                const SizedBox(height: 16),
                _FlipCalcCard(
                  item: item,
                  live: market.flipLiveData,
                  loading: market.flipLoading,
                  buyPriceCtrl: _buyPriceCtrl,
                  onRefresh: market.refreshFlipPrice,
                ),
              ],

              // Empty state
              if (item == null && !_searching) ...[
                const SizedBox(height: 56),
                const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.calculate_outlined,
                          color: Color(0xFF333333), size: 64),
                      SizedBox(height: 12),
                      Text('Search for an item above',
                          style: TextStyle(
                              color: Color(0xFF555555), fontSize: 16)),
                      SizedBox(height: 4),
                      Text(
                        'Enter your buy price to calculate flip profit',
                        style: TextStyle(
                            color: Color(0xFF444444), fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchDropdown(BuildContext context, MarketProvider market) {
    final results = market.searchItems(_query);
    if (results.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No items found',
            style: TextStyle(color: Color(0xFF666666)),
            textAlign: TextAlign.center),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemCount: math.min(results.length, 20),
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: Color(0xFF2A2A2A)),
      itemBuilder: (_, i) {
        final r = results[i];
        return ListTile(
          dense: true,
          title: Text(r.name,
              style:
                  const TextStyle(color: Colors.white, fontSize: 14)),
          subtitle: r.type.isNotEmpty
              ? Text(r.type,
                  style: const TextStyle(
                      color: Color(0xFF888888), fontSize: 11))
              : null,
          trailing: r.marketValue > 0
              ? Text(_fmt(r.marketValue),
                  style: const TextStyle(
                      color: Color(0xFF888888), fontSize: 12))
              : null,
          onTap: () {
            _searchCtrl.clear();
            _buyPriceCtrl.clear();
            setState(() {
              _query = '';
              _searching = false;
            });
            FocusScope.of(context).unfocus();
            market.loadFlipItem(r);
          },
        );
      },
    );
  }
}

class _FlipCalcCard extends StatefulWidget {
  final TornItem item;
  final LiveItemData? live;
  final bool loading;
  final TextEditingController buyPriceCtrl;
  final VoidCallback onRefresh;

  const _FlipCalcCard({
    required this.item,
    required this.live,
    required this.loading,
    required this.buyPriceCtrl,
    required this.onRefresh,
  });

  @override
  State<_FlipCalcCard> createState() => _FlipCalcCardState();
}

class _FlipCalcCardState extends State<_FlipCalcCard> {
  int? _buyPrice;

  @override
  void initState() {
    super.initState();
    widget.buyPriceCtrl.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.buyPriceCtrl.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    setState(() {
      _buyPrice = int.tryParse(widget.buyPriceCtrl.text);
    });
  }

  @override
  Widget build(BuildContext context) {
    final sellPrice = widget.live?.cheapestPrice ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Item header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(12),
            border: const Border(
              left: BorderSide(color: Color(0xFFEF5350), width: 3),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.item.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _TypeBadge(type: widget.item.type),
                        if (widget.item.marketValue > 0) ...[
                          const SizedBox(width: 8),
                          Text(
                            'MV ${_fmt(widget.item.marketValue)}',
                            style: const TextStyle(
                                color: Color(0xFF888888), fontSize: 11),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Current market price
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.storefront_outlined,
                  color: Color(0xFF888888), size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CHEAPEST LISTING',
                      style: TextStyle(
                        color: Color(0xFF888888),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    widget.loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFFEF5350),
                            ),
                          )
                        : Text(
                            sellPrice > 0 ? _fmt(sellPrice) : '—',
                            style: TextStyle(
                              color: sellPrice > 0
                                  ? Colors.white
                                  : const Color(0xFF666666),
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                    if (widget.live != null &&
                        widget.live!.listings.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '2nd: ${_fmt(widget.live!.listings[1].price)}  '
                          '(${widget.live!.listings.length} listings)',
                          style: const TextStyle(
                              color: Color(0xFF666666), fontSize: 11),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: Color(0xFF888888)),
                tooltip: 'Refresh price',
                onPressed: widget.loading ? null : widget.onRefresh,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Buy price input
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'YOUR BUY PRICE',
                style: TextStyle(
                  color: Color(0xFF888888),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: widget.buyPriceCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(
                    color: Colors.white, fontSize: 20),
                decoration: const InputDecoration(
                  hintText: '0',
                  hintStyle: TextStyle(color: Color(0xFF444444)),
                  prefixText: '\$ ',
                  prefixStyle: TextStyle(
                      color: Color(0xFFEF5350), fontSize: 20),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        if (_buyPrice != null && _buyPrice! > 0 && sellPrice > 0)
          _ProfitCard(buyPrice: _buyPrice!, sellPrice: sellPrice),
      ],
    );
  }
}

class _ProfitCard extends StatelessWidget {
  final int buyPrice;
  final int sellPrice;

  const _ProfitCard({required this.buyPrice, required this.sellPrice});

  @override
  Widget build(BuildContext context) {
    final profit = sellPrice - buyPrice;
    final roi = buyPrice > 0 ? (profit / buyPrice * 100) : 0.0;
    final isProfit = profit > 0;
    final color =
        isProfit ? const Color(0xFF4CAF50) : const Color(0xFFEF5350);

    int unitsFor(int target) {
      if (profit <= 0) return 0;
      return (target / profit).ceil();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isProfit ? Icons.trending_up : Icons.trending_down,
                color: color,
                size: 18,
              ),
              const SizedBox(width: 6),
              const Text(
                'PROFIT ANALYSIS',
                style: TextStyle(
                  color: Color(0xFF888888),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ProfitRow(
            label: 'Profit / unit',
            value: '${isProfit ? '+' : ''}${_fmt(profit)}',
            valueColor: color,
            large: true,
          ),
          const SizedBox(height: 6),
          _ProfitRow(
            label: 'ROI',
            value: '${roi >= 0 ? '+' : ''}${roi.toStringAsFixed(1)}%',
            valueColor: color,
          ),
          if (isProfit) ...[
            const Divider(color: Color(0xFF2A2A2A), height: 20),
            _ProfitRow(
              label: 'Units for \$1M',
              value: '${unitsFor(1000000)}×',
              valueColor: const Color(0xFF888888),
            ),
            const SizedBox(height: 4),
            _ProfitRow(
              label: 'Units for \$10M',
              value: '${unitsFor(10000000)}×',
              valueColor: const Color(0xFF888888),
            ),
            const SizedBox(height: 4),
            _ProfitRow(
              label: 'Units for \$100M',
              value: '${unitsFor(100000000)}×',
              valueColor: const Color(0xFF888888),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfitRow extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final bool large;

  const _ProfitRow({
    required this.label,
    required this.value,
    required this.valueColor,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
              color: const Color(0xFF888888),
              fontSize: large ? 14 : 13),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: large ? 18 : 14,
            fontWeight: large ? FontWeight.bold : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
