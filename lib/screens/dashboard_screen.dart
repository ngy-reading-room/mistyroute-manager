/// Dashboard / Bandwidth monitor.
///
/// Sections (top to bottom): inbound totals, live server status,
/// flags (tap to filter), and the client list sorted by usage desc.
library;

import 'package:flutter/material.dart';

import '../models/panel_models.dart';
import '../services/billing.dart';
import '../services/client_actions.dart';
import '../services/panel_provider.dart';
import '../utils/format.dart';
import 'add_client_screen.dart';
import 'client_detail_screen.dart';

enum ClientFilter { all, over80, expiring, disabled }

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({required this.provider, super.key});

  final PanelProvider provider;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  ClientFilter _filter = ClientFilter.all;
  String _search = '';

  /// Group filter: null = all groups, '' = ungrouped only,
  /// otherwise the group label (MNA, MayZin, Friends, FOC, …).
  String? _group;

  bool _fixingNames = false;

  /// One tap: auto-fix every fixable name in the selected group
  /// (or all groups), then show what changed and what was skipped.
  Future<void> _fixNames() async {
    setState(() => _fixingNames = true);
    final results = await widget.provider.fixNamesInGroup(_group);
    if (!mounted) return;
    setState(() => _fixingNames = false);
    await showDialog<void>(
      context: context,
      builder: (context) => _FixNamesResultDialog(results: results),
    );
  }

  Color _usageColor(ClientInfo c) {
    final p = c.usedPct;
    if (p == null) return Colors.grey;
    if (p >= 0.95) return Colors.redAccent;
    if (p >= 0.8) return Colors.amber;
    return Colors.tealAccent;
  }

  List<ClientInfo> _filtered(List<ClientInfo> clients) {
    final sorted = List<ClientInfo>.from(clients)
      ..sort((a, b) => b.usedBytes.compareTo(a.usedBytes));
    final q = _search.trim().toLowerCase();
    var list = q.isEmpty
        ? sorted
        : sorted
            .where((c) => c.email.toLowerCase().contains(q))
            .toList();
    // Group filter combines with search + the flag filter below.
    // A stale selection (group with no clients left) falls back
    // to all groups instead of showing an empty list.
    if (_group != null) {
      final grouped = list.where((c) => c.group == _group).toList();
      if (grouped.isNotEmpty) list = grouped;
    }
    return switch (_filter) {
      ClientFilter.all => list,
      ClientFilter.over80 => list.where((c) => c.isOver80).toList(),
      ClientFilter.expiring =>
        list.where((c) => c.isExpiringSoon).toList(),
      ClientFilter.disabled => list.where((c) => !c.enabled).toList(),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AddClientScreen(provider: widget.provider),
            ),
          );
        },
        icon: const Icon(Icons.person_add),
        label: const Text('Add client'),
      ),
      body: ListenableBuilder(
        listenable: widget.provider,
        builder: (context, _) {
          final p = widget.provider;
          final data = p.data;
          return RefreshIndicator(
            onRefresh: p.refresh,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _ModeBanner(provider: p)),
                if (p.isLoading)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  )
                else if (p.error != null)
                  SliverToBoxAdapter(child: _ErrorCard(message: p.error!))
                else if (data != null) ...[
                  SliverToBoxAdapter(
                    child: _InboundTotalsCard(inbounds: data.inbounds),
                  ),
                  SliverToBoxAdapter(
                    child: _ServerStatusCard(
                      status: data.serverStatus,
                      isLive: !p.showingDemo,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _BillingCard(provider: p),
                  ),
                  SliverToBoxAdapter(
                    child: _FlagsRow(
                      data: data,
                      filter: _filter,
                      onFilter: (f) => setState(() => _filter = f),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Search client name…',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _search.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () =>
                                      setState(() => _search = ''),
                                ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        onChanged: (v) => setState(() => _search = v),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _GroupRow(
                      data: data,
                      selected: _group,
                      onSelect: (g) => setState(() => _group = g),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _FixNamesRow(
                      group: _group,
                      busy: _fixingNames,
                      onFix: _fixNames,
                    ),
                  ),
                  _ClientSliverList(
                    clients: _filtered(data.clients),
                    usageColor: _usageColor,
                    provider: widget.provider,
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ModeBanner extends StatelessWidget {
  const _ModeBanner({required this.provider});

  final PanelProvider provider;

  @override
  Widget build(BuildContext context) {
    final isDemo = provider.showingDemo;
    final count = provider.data?.clients.length ?? 0;
    final updated = provider.lastUpdated;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      Chip(
                        label: Text(isDemo ? 'DEMO DATA' : 'LIVE'),
                        backgroundColor: isDemo
                            ? Colors.amber.withValues(alpha: 0.25)
                            : Colors.teal.withValues(alpha: 0.25),
                      ),
                      Chip(label: Text('$count clients')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isDemo
                        ? 'Sample data — no panel connected. '
                            'Add the panel URL + API token in Settings '
                            'to see live data.'
                        : 'Live data from the panel.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (updated != null)
                    Text(
                      'Updated ${_timeOfDay(updated)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            IconButton(
              onPressed: provider.isLoading ? null : provider.refresh,
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
            ),
          ],
        ),
      ),
    );
  }

  String _timeOfDay(DateTime d) {
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      color: Colors.red.withValues(alpha: 0.15),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Could not load live data.\n$message\n'
                'Check the panel URL + token in Settings, '
                'or switch demo data back on.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InboundTotalsCard extends StatelessWidget {
  const _InboundTotalsCard({required this.inbounds});

  final List<InboundInfo> inbounds;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bandwidth — inbound totals',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            for (final inbound in inbounds)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                // The inbound name gets its own line: on a narrow phone
                // the three total chips take ~300px, leaving the name
                // ~1 character wide in a Row, so it rendered
                // letter-by-letter vertically (seen in the v0.2.0
                // screenshots). Chips wrap below the name instead.
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      inbound.remark,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _TotalChip(
                          label: '↑ ${formatGb(inbound.upBytes)}',
                        ),
                        _TotalChip(
                          label: '↓ ${formatGb(inbound.downBytes)}',
                        ),
                        _TotalChip(
                          label:
                              'Σ ${formatGb(inbound.upBytes + inbound.downBytes)}',
                          bold: true,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TotalChip extends StatelessWidget {
  const _TotalChip({required this.label, this.bold = false});

  final String label;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}

class _ServerStatusCard extends StatelessWidget {
  const _ServerStatusCard({required this.status, required this.isLive});

  final ServerStatus? status;
  final bool isLive;

  @override
  Widget build(BuildContext context) {
    final s = status;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Live server status',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 8),
                if (s != null)
                  Chip(
                    label: Text(
                      s.xrayState == 'running' ? 'Xray running' : 'Xray: ${s.xrayState}',
                    ),
                    backgroundColor: s.xrayState == 'running'
                        ? Colors.teal.withValues(alpha: 0.25)
                        : Colors.red.withValues(alpha: 0.25),
                  )
                else
                  const Chip(label: Text('Unavailable')),
              ],
            ),
            const SizedBox(height: 12),
            if (s == null)
              Text(
                isLive
                    ? 'server/status did not answer — the client list '
                        'above is still live; only this card is missing.'
                    : 'Sample status values (demo mode).',
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: _Stat(
                      label: 'Net up',
                      value: formatSpeed(s.netUpBytesPerSec),
                    ),
                  ),
                  Expanded(
                    child: _Stat(
                      label: 'Net down',
                      value: formatSpeed(s.netDownBytesPerSec),
                    ),
                  ),
                  Expanded(
                    child: _Stat(
                      label: 'CPU',
                      value: '${s.cpu.toStringAsFixed(1)}%',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _Stat(
                      label: 'Memory',
                      value:
                          '${formatGb(s.memCurrent)} / ${formatGb(s.memTotal)}',
                    ),
                  ),
                  Expanded(
                    child: _Stat(
                      label: 'Uptime',
                      value: formatUptime(s.uptimeSeconds),
                    ),
                  ),
                  Expanded(
                    child: _Stat(
                      label: 'Xray',
                      value: s.xrayVersion.isEmpty ? '—' : s.xrayVersion,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

class _FlagsRow extends StatelessWidget {
  const _FlagsRow({
    required this.data,
    required this.filter,
    required this.onFilter,
  });

  final PanelData data;
  final ClientFilter filter;
  final ValueChanged<ClientFilter> onFilter;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _FlagChip(
            label: 'All (${data.clients.length})',
            selected: filter == ClientFilter.all,
            onTap: () => onFilter(ClientFilter.all),
          ),
          _FlagChip(
            label: '≥80% quota (${data.over80.length})',
            selected: filter == ClientFilter.over80,
            onTap: () => onFilter(ClientFilter.over80),
            warn: data.over80.isNotEmpty,
          ),
          _FlagChip(
            label: 'Expiring ≤7d (${data.expiringSoon.length})',
            selected: filter == ClientFilter.expiring,
            onTap: () => onFilter(ClientFilter.expiring),
            warn: data.expiringSoon.isNotEmpty,
          ),
          _FlagChip(
            label: 'Disabled (${data.disabled.length})',
            selected: filter == ClientFilter.disabled,
            onTap: () => onFilter(ClientFilter.disabled),
          ),
        ],
      ),
    );
  }
}

class _FlagChip extends StatelessWidget {
  const _FlagChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.warn = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: warn
          ? Colors.amber.withValues(alpha: 0.3)
          : Theme.of(context).colorScheme.primaryContainer,
    );
  }
}

/// Group filter chips: "All groups" plus one chip per group that
/// actually has clients (with counts), plus "Ungrouped" only when
/// ungrouped clients exist. Groups come from the panel records —
/// live data fills them in after the list loads; demo data carries
/// the same groups so the filter is testable without the panel.
class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.data,
    required this.selected,
    required this.onSelect,
  });

  final PanelData data;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final counts = data.groupCounts;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _FlagChip(
            label: 'All groups (${data.clients.length})',
            selected: selected == null,
            onTap: () => onSelect(null),
          ),
          for (final entry in counts.entries)
            _FlagChip(
              label: '${entry.key} (${entry.value})',
              selected: selected == entry.key,
              onTap: () => onSelect(entry.key),
            ),
          if (data.ungroupedCount > 0)
            _FlagChip(
              label: 'Ungrouped (${data.ungroupedCount})',
              selected: selected == '',
              onTap: () => onSelect(''),
            ),
        ],
      ),
    );
  }
}

class _ClientSliverList extends StatelessWidget {
  const _ClientSliverList({
    required this.clients,
    required this.usageColor,
    required this.provider,
  });

  final List<ClientInfo> clients;
  final Color Function(ClientInfo) usageColor;
  final PanelProvider provider;

  @override
  Widget build(BuildContext context) {
    if (clients.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: Text('No clients match this filter.')),
        ),
      );
    }
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final c = clients[index];
          final pct = c.usedPct;
          // Custom layout, NOT a ListTile: ListTile with
          // isThreeLine: true fixes the tile height to three lines,
          // but this row's subtitle (usage line + progress bar +
          // expiry line, with long names wrapping to two lines)
          // is taller than that, so the subtitle painted
          // double/overlapping "Used" lines on the phone
          // (seen in the v0.2.0 screenshots for MAMS / MaSandar-1).
          // A plain Column in a Card has no fixed height to fight.
          return Card(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ClientDetailScreen(
                      client: c,
                      provider: provider,
                    ),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      backgroundColor: c.enabled
                          ? Colors.teal.withValues(alpha: 0.3)
                          : Colors.grey.withValues(alpha: 0.3),
                      child: Icon(
                        c.enabled ? Icons.person : Icons.person_off,
                        color: c.enabled ? Colors.tealAccent : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.email,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '↑ ${formatGb(c.upBytes)}  ↓ ${formatGb(c.downBytes)}'
                            '  ·  Used ${formatGb(c.usedBytes)}'
                            ' / ${c.isUnlimited ? 'Unlimited' : formatGb(c.quotaBytes)}',
                          ),
                          const SizedBox(height: 6),
                          if (pct != null)
                            LinearProgressIndicator(
                              value: pct.clamp(0.0, 1.0),
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              valueColor:
                                  AlwaysStoppedAnimation(usageColor(c)),
                            )
                          else
                            const Text('Unlimited quota'),
                          const SizedBox(height: 4),
                          Text(
                            c.expiry == null
                                ? 'No expiry'
                                : '${formatDate(c.expiry!)} · ${daysLeftText(c.expiry)}',
                            style: TextStyle(color: _expiryTextColor(c)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (pct == null)
                      const Text('—')
                    else
                      Text(
                        '${(pct * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: usageColor(c),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
        childCount: clients.length,
      ),
    );
  }

  Color _expiryTextColor(ClientInfo c) {
    if (c.isExpired) return Colors.redAccent;
    if (c.isExpiringSoon) return Colors.amber;
    return Colors.white70;
  }
}

/// Billing estimate card: two figures side by side — (1) the total
/// DO cost in USD and (2) the final amount AYA Credit will actually
/// charge in MMK — plus the breakdown (base MMK, +3% fee).
///
/// The estimate is computed from VPS/panel data (outbound vs the
/// 1 TB/month allowance + droplet), NOT the DO API, so it works
/// without a DO token. Labelled an estimate: panel counters are
/// cumulative since the last traffic reset.
class _BillingCard extends StatelessWidget {
  const _BillingCard({required this.provider});

  final PanelProvider provider;

  @override
  Widget build(BuildContext context) {
    final b = provider.billing;
    if (b == null) return const SizedBox.shrink();
    final aya = b.ayaMtd;
    final projected = b.ayaProjected;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Billing — estimate from VPS data',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Outbound ${b.outboundGib.toStringAsFixed(1)} GiB of '
              '${b.allowanceGib.toStringAsFixed(0)} GiB included '
              '(day ${b.dayOfMonth}/${b.daysInMonth}).',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Total DO cost'),
                      Text(
                        formatUsd(b.totalUsdMtd),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        'droplet ${formatUsd(b.dropletUsdMtd)}'
                        ' + overage ${formatUsd(b.overageUsd)}',
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Final AYA charge (estimate)'),
                      Text(
                        formatMmk2(aya.finalMmk),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        'base ${formatMmk2(aya.baseMmk)}'
                        ' + 3% fee ${formatMmk2(aya.feeMmk)}',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Projected month-end: ${formatUsd(b.projectedTotalUsd)}'
              ' / ${formatMmk2(projected.finalMmk)} AYA '
              '(${formatMmk2(projected.baseMmk)} + 3% '
              '${formatMmk2(projected.feeMmk)}).',
            ),
            if (provider.doBalance != null)
              Text('DO balance (month-to-date): \$${provider.doBalance}'),
            const SizedBox(height: 4),
            const Text(
              'Estimate from VPS data — panel counters are cumulative '
              'since the last traffic reset. MMK at the AYA card rate '
              '(base 4,466.67 + 3% fee = 4,600.67 MMK/USD).',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

/// One-tap name fixing, scoped to the selected group chip
/// (or all groups when "All groups" is selected).
class _FixNamesRow extends StatelessWidget {
  const _FixNamesRow({
    required this.group,
    required this.busy,
    required this.onFix,
  });

  final String? group;
  final bool busy;
  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) {
    final scope = group == null
        ? 'all groups'
        : group!.isEmpty
            ? 'ungrouped'
            : group!;
    // Column, not a Row: the button label is long, and a Row would
    // squeeze the note text to ~0 width on a narrow phone (it wrapped
    // into a ~1180px-tall column and pushed the client list
    // off-screen in the 360px test).
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilledButton.tonalIcon(
            onPressed: busy ? null : onFix,
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_fix_high),
            label: Text('Fix names ($scope)'),
          ),
          const SizedBox(height: 4),
          const Text(
            'Normalises remarks to Name_D.M.YY-D.M.YY from existing '
            'dates only.',
            style: TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

/// Results summary after a one-tap fix run: what changed
/// (old -> new) and what was skipped with reasons.
class _FixNamesResultDialog extends StatelessWidget {
  const _FixNamesResultDialog({required this.results});

  final List<NameCorrection> results;

  @override
  Widget build(BuildContext context) {
    final fixed = results.whereType<NameFixed>().toList();
    final skipped = results.whereType<NameSkipped>().toList();
    final already = results.whereType<NameAlreadyCorrect>().length;
    return AlertDialog(
      title: const Text('Fix names — results'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${fixed.length} fixed · $already already correct · '
              '${skipped.length} skipped',
            ),
            if (fixed.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Fixed:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              for (final f in fixed)
                Text('${f.email}  →  ${f.correctedEmail}'),
            ],
            if (skipped.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Skipped:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              for (final s in skipped)
                Text('${s.email}\n  ${s.reason}'),
            ],
            if (fixed.isEmpty && skipped.isEmpty) ...[
              const SizedBox(height: 12),
              const Text('Nothing to fix — every name is already correct.'),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
