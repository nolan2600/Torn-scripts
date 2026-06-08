import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_settings.dart';
import '../providers/settings_provider.dart';
import '../providers/hunter_provider.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _tornKeyCtrl = TextEditingController();
  final _ffKeyCtrl = TextEditingController();
  bool _tornKeyVisible = false;
  bool _ffKeyVisible = false;
  String? _tornKeyStatus;
  String? _ffKeyStatus;
  bool _tornKeyOk = false;
  bool _ffKeyOk = false;
  bool _savingTorn = false;
  bool _savingFF = false;
  bool _notifGranted = false;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    _tornKeyCtrl.text = settings.tornKey;
    _ffKeyCtrl.text = settings.ffKey;
    _checkNotifPermission();
  }

  Future<void> _checkNotifPermission() async {
    final granted = await NotificationService.instance.isPermissionGranted();
    if (mounted) setState(() => _notifGranted = granted);
  }

  @override
  void dispose() {
    _tornKeyCtrl.dispose();
    _ffKeyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final hunter = context.read<HunterProvider>();
    final s = settings.settings;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Settings',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: Color(0xFF2A2A2A)),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── API Keys ──────────────────────────────────────
          _SectionHeader('API Keys'),
          _Card(
            children: [
              _FieldLabel('Torn API Key'),
              _KeyField(
                controller: _tornKeyCtrl,
                hint: '16 characters',
                visible: _tornKeyVisible,
                onToggleVisibility: () =>
                    setState(() => _tornKeyVisible = !_tornKeyVisible),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      label: _savingTorn ? 'Validating…' : 'Save Torn Key',
                      color: const Color(0xFF4FC3F7),
                      enabled: !_savingTorn,
                      onTap: () => _saveTornKey(settings, hunter),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (settings.hasKey)
                    _ActionButton(
                      label: 'Log out',
                      color: const Color(0xFFEF5350),
                      onTap: () => _clearTornKey(settings, hunter),
                    ),
                ],
              ),
              if (_tornKeyStatus != null) ...[
                const SizedBox(height: 6),
                Text(_tornKeyStatus!,
                    style: TextStyle(
                        color:
                            _tornKeyOk ? const Color(0xFF4CAF50) : const Color(0xFFEF5350),
                        fontSize: 12)),
              ],
              const SizedBox(height: 16),
              const Divider(color: Color(0xFF2A2A2A)),
              const SizedBox(height: 12),
              _FieldLabel('FFScouter Key'),
              const _Hint(
                  'Required for fair-fight and BS bracket filtering. Get one at ffscouter.com.'),
              const SizedBox(height: 6),
              _KeyField(
                controller: _ffKeyCtrl,
                hint: '16 characters',
                visible: _ffKeyVisible,
                onToggleVisibility: () =>
                    setState(() => _ffKeyVisible = !_ffKeyVisible),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      label: _savingFF ? 'Validating…' : 'Save FF Key',
                      color: const Color(0xFF4FC3F7),
                      enabled: !_savingFF,
                      onTap: () => _saveFFKey(settings),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _ActionButton(
                    label: 'Clear',
                    color: const Color(0xFF666666),
                    onTap: () => _clearFFKey(settings),
                  ),
                ],
              ),
              if (_ffKeyStatus != null) ...[
                const SizedBox(height: 6),
                Text(_ffKeyStatus!,
                    style: TextStyle(
                        color:
                            _ffKeyOk ? const Color(0xFF4CAF50) : const Color(0xFFEF5350),
                        fontSize: 12)),
              ],
            ],
          ),

          // ── Reward & Combat Filters ───────────────────────
          _SectionHeader('Reward & Combat Filters'),
          _Card(
            children: [
              _NumberField(
                label: 'Min reward (\$)',
                value: s.minPrice,
                min: 0,
                step: 100000,
                onChanged: (v) => _updateSettings(s.copyWith(minPrice: v.round())),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _NumberField(
                      label: 'FF min',
                      value: s.minFF,
                      min: 1,
                      max: 10,
                      step: 0.1,
                      decimals: 1,
                      onChanged: (v) => _updateSettings(s.copyWith(minFF: v)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _NumberField(
                      label: 'FF max',
                      value: s.maxFF,
                      min: 1,
                      max: 10,
                      step: 0.1,
                      decimals: 1,
                      onChanged: (v) => _updateSettings(s.copyWith(maxFF: v)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _NumberField(
                label: 'Hospital max (minutes)',
                hint: '0 = Okay only · 5 = targets about to exit',
                value: s.hospitalMaxMin.toDouble(),
                min: 0,
                max: 60,
                step: 1,
                onChanged: (v) =>
                    _updateSettings(s.copyWith(hospitalMaxMin: v.round())),
              ),
            ],
          ),

          // ── BS Bracket ────────────────────────────────────
          _SectionHeader('Battle Stats Bracket Filter'),
          _Card(
            children: [
              const _Hint(
                  'Requires FFScouter key. Leave all unchecked to show every level.'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: kBsRanges.map((r) {
                  final id = r['id'] as String;
                  final label = r['label'] as String;
                  final selected = s.bsRanges.contains(id);
                  return FilterChip(
                    label: Text(label,
                        style: TextStyle(
                            fontSize: 12,
                            color: selected
                                ? Colors.white
                                : Colors.grey[500])),
                    selected: selected,
                    selectedColor: const Color(0xFF3A1A1A),
                    backgroundColor: const Color(0xFF252525),
                    checkmarkColor: const Color(0xFFEF5350),
                    side: BorderSide(
                        color: selected
                            ? const Color(0xFFEF5350)
                            : const Color(0xFF3A3A3A)),
                    onSelected: (val) {
                      final newRanges = [...s.bsRanges];
                      val ? newRanges.add(id) : newRanges.remove(id);
                      _updateSettings(s.copyWith(bsRanges: newRanges));
                    },
                  );
                }).toList(),
              ),
            ],
          ),

          // ── Filters ───────────────────────────────────────
          _SectionHeader('Target Filters'),
          _Card(
            children: [
              _Toggle(
                label: 'Show only revivable hospital targets',
                value: s.revivableOnly,
                onChanged: (v) =>
                    _updateSettings(s.copyWith(revivableOnly: v)),
              ),
              const SizedBox(height: 8),
              _Toggle(
                label: 'Hide targets whose faction is in an active war ⚔️',
                value: s.hideWarTargets,
                onChanged: (v) =>
                    _updateSettings(s.copyWith(hideWarTargets: v)),
              ),
              const SizedBox(height: 8),
              _Toggle(
                label: 'Include targets with unknown FF score',
                value: s.includeUnknownFF,
                onChanged: (v) =>
                    _updateSettings(s.copyWith(includeUnknownFF: v)),
              ),
            ],
          ),

          // ── Refresh ───────────────────────────────────────
          _SectionHeader('Auto-Refresh'),
          _Card(
            children: [
              _DropdownField<int>(
                label: 'Refresh interval',
                value: s.refreshSec,
                items: const [
                  (30, 'Every 30 seconds'),
                  (60, 'Every 60 seconds'),
                  (120, 'Every 2 minutes'),
                  (300, 'Every 5 minutes'),
                  (0, 'Off (manual only)'),
                ],
                onChanged: (v) {
                  _updateSettings(s.copyWith(refreshSec: v));
                  hunter.stopPolling();
                  if (v > 0) hunter.startPolling();
                },
              ),
              const _Hint(
                  '60 seconds is safely under the Torn API rate limit.'),
            ],
          ),

          // ── Notifications ─────────────────────────────────
          _SectionHeader('Alerts & Notifications'),
          _Card(
            children: [
              _Toggle(
                label: 'Auto-alert all hospital targets (60s before exit)',
                value: s.hospAlerts,
                onChanged: (v) =>
                    _updateSettings(s.copyWith(hospAlerts: v)),
              ),
              const SizedBox(height: 8),
              _Toggle(
                label:
                    'Auto-alert all marked targets (60s before exit/landing)',
                value: s.markedAlerts,
                onChanged: (v) =>
                    _updateSettings(s.copyWith(markedAlerts: v)),
              ),
              const SizedBox(height: 14),
              const Divider(color: Color(0xFF2A2A2A)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _notifGranted
                          ? const Color(0xFF1E3A2A)
                          : const Color(0xFF3A1A1A),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _notifGranted ? 'Notifications: Granted ✓' : 'Notifications: Denied ✗',
                      style: TextStyle(
                          color: _notifGranted
                              ? const Color(0xFF4CAF50)
                              : const Color(0xFFEF5350),
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Spacer(),
                  if (!_notifGranted)
                    _ActionButton(
                      label: 'Request',
                      color: const Color(0xFF4FC3F7),
                      onTap: _requestNotifPermission,
                    ),
                ],
              ),
            ],
          ),

          // ── Danger zone ───────────────────────────────────
          _SectionHeader('Reset'),
          _Card(
            children: [
              const _Hint(
                  'Resets all filters to defaults (API keys are preserved).'),
              const SizedBox(height: 10),
              _ActionButton(
                label: 'Reset all filters to defaults',
                color: const Color(0xFF666666),
                onTap: () => _reset(settings),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              'Bounty Hunter v1.0 for Torn\nlannav + DieselBlade',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[700], fontSize: 11),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── Actions ────────────────────────────────────────────────

  void _updateSettings(AppSettings updated) {
    context.read<SettingsProvider>().update(updated);
  }

  Future<void> _saveTornKey(
      SettingsProvider settings, HunterProvider hunter) async {
    final key = _tornKeyCtrl.text.trim();
    if (!RegExp(r'^[A-Za-z0-9]{16}$').hasMatch(key)) {
      setState(() {
        _tornKeyStatus = 'Must be exactly 16 alphanumeric characters.';
        _tornKeyOk = false;
      });
      return;
    }
    setState(() {
      _savingTorn = true;
      _tornKeyStatus = 'Validating…';
    });
    final api = TornApiService(key);
    try {
      await api.validateKey();
      await settings.saveTornKey(key);
      hunter.onSettingsChanged();
      hunter.startPolling();
      setState(() {
        _tornKeyStatus = 'Key saved ✓';
        _tornKeyOk = true;
      });
    } catch (e) {
      setState(() {
        _tornKeyStatus = 'Torn rejected that key: $e';
        _tornKeyOk = false;
      });
    }
    setState(() => _savingTorn = false);
  }

  Future<void> _clearTornKey(
      SettingsProvider settings, HunterProvider hunter) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Log out', style: TextStyle(color: Colors.white)),
        content: const Text('Clear your Torn API key?',
            style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out',
                style: TextStyle(color: Color(0xFFEF5350))),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await settings.clearTornKey();
      hunter.stopPolling();
      _tornKeyCtrl.clear();
      setState(() {
        _tornKeyStatus = 'Key cleared.';
        _tornKeyOk = false;
      });
    }
  }

  Future<void> _saveFFKey(SettingsProvider settings) async {
    final key = _ffKeyCtrl.text.trim();
    if (key.isEmpty) {
      await settings.clearFFKey();
      setState(() {
        _ffKeyStatus = 'Cleared.';
        _ffKeyOk = false;
      });
      return;
    }
    setState(() {
      _savingFF = true;
      _ffKeyStatus = 'Validating with FFScouter…';
    });
    final result = await FFScouterService.validateKey(key);
    if (result.ok) {
      await settings.saveFFKey(key);
      setState(() {
        _ffKeyStatus = '${result.message} Saved ✓';
        _ffKeyOk = true;
      });
    } else {
      setState(() {
        _ffKeyStatus = result.message;
        _ffKeyOk = false;
      });
    }
    setState(() => _savingFF = false);
  }

  Future<void> _clearFFKey(SettingsProvider settings) async {
    await settings.clearFFKey();
    _ffKeyCtrl.clear();
    setState(() {
      _ffKeyStatus = 'Cleared.';
      _ffKeyOk = false;
    });
  }

  Future<void> _requestNotifPermission() async {
    final granted = await NotificationService.instance.requestPermission();
    setState(() => _notifGranted = granted);
  }

  Future<void> _reset(SettingsProvider settings) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Reset settings',
            style: TextStyle(color: Colors.white)),
        content: const Text(
            'Reset all filters to defaults? API keys will be preserved.',
            style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset',
                style: TextStyle(color: Color(0xFFEF5350))),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await settings.reset();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Filters reset to defaults.'),
            backgroundColor: Color(0xFF333333),
          ),
        );
      }
    }
  }
}

// ── Shared widgets ─────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: Colors.grey[600],
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.3,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFFBBBBBB),
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  final String text;
  const _Hint(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: TextStyle(color: Colors.grey[600], fontSize: 11.5));
  }
}

class _KeyField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool visible;
  final VoidCallback onToggleVisibility;

  const _KeyField({
    required this.controller,
    required this.hint,
    required this.visible,
    required this.onToggleVisibility,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: !visible,
      maxLength: 16,
      decoration: InputDecoration(
        hintText: hint,
        counterText: '',
        suffixIcon: IconButton(
          icon: Icon(visible ? Icons.visibility_off : Icons.visibility,
              color: Colors.grey, size: 18),
          onPressed: onToggleVisibility,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        filled: true,
        fillColor: const Color(0xFF252525),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF444444))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF444444))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF4FC3F7))),
      ),
      style: const TextStyle(color: Colors.white, fontSize: 14,
          fontFamily: 'monospace'),
    );
  }
}

class _NumberField extends StatefulWidget {
  final String label;
  final String? hint;
  final double value;
  final double min;
  final double? max;
  final double step;
  final int decimals;
  final void Function(double) onChanged;

  const _NumberField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
    this.min = 0,
    this.max,
    this.step = 1,
    this.decimals = 0,
  });

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late TextEditingController _ctrl;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _fmt(widget.value));
  }

  @override
  void didUpdateWidget(_NumberField old) {
    super.didUpdateWidget(old);
    if (!_editing) {
      _ctrl.text = _fmt(widget.value);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _fmt(double v) =>
      widget.decimals > 0 ? v.toStringAsFixed(widget.decimals) : v.toInt().toString();

  void _commit(String s) {
    final v = double.tryParse(s);
    if (v == null) return;
    final clamped = v.clamp(widget.min, widget.max ?? double.infinity);
    widget.onChanged(clamped);
    _ctrl.text = _fmt(clamped);
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(widget.label),
        if (widget.hint != null) ...[
          _Hint(widget.hint!),
          const SizedBox(height: 4),
        ],
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onTap: () => setState(() => _editing = true),
                onSubmitted: _commit,
                onEditingComplete: () => _commit(_ctrl.text),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  filled: true,
                  fillColor: const Color(0xFF252525),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: Color(0xFF444444))),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: Color(0xFF444444))),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: Color(0xFF4FC3F7))),
                ),
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
            const SizedBox(width: 8),
            _StepBtn(
              icon: Icons.remove,
              onTap: () {
                final next =
                    (widget.value - widget.step).clamp(widget.min, widget.max ?? double.infinity);
                widget.onChanged(next);
              },
            ),
            const SizedBox(width: 4),
            _StepBtn(
              icon: Icons.add,
              onTap: () {
                final next = widget.value + widget.step;
                final clamped =
                    widget.max != null ? next.clamp(widget.min, widget.max!) : next;
                widget.onChanged(clamped);
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _StepBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 38,
        decoration: BoxDecoration(
          color: const Color(0xFF333333),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF444444)),
        ),
        child: Icon(icon, color: Colors.grey, size: 18),
      ),
    );
  }
}

class _DropdownField<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<(T, String)> items;
  final void Function(T) onChanged;

  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF252525),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF444444)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              dropdownColor: const Color(0xFF252525),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              items: items
                  .map((e) => DropdownMenuItem(
                        value: e.$1,
                        child: Text(e.$2),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  final String label;
  final bool value;
  final void Function(bool) onChanged;

  const _Toggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 13)),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: const Color(0xFFEF5350),
          trackColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? const Color(0xFF8B2222)
                  : const Color(0xFF333333)),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool enabled;

  const _ActionButton({
    required this.label,
    required this.color,
    this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: enabled ? color.withAlpha(26) : const Color(0xFF252525),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
              color: enabled ? color : const Color(0xFF3A3A3A)),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: enabled ? color : Colors.grey,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
