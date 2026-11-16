/// Dashboard / Bandwidth monitor.
///
/// Sections (top to bottom): inbound totals, live server status,
/// flags (tap to filter), and the client list sorted by usage desc.
library;

import 'package:flutter/material.dart';

import '../models/panel_models.dart';
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
    return switch (_filter) {
      ClientFilter.all => sorted,
      ClientFilter.over80 => sorted.where((c) => c.isOver80).toList(),
      ClientFilter.expiring => sorted.where((c) => c.isExpiringSoon).toList(),
      ClientFilter.disabled => sorted.where((c) => !c.enabled).toList(),
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
                    child: _FlagsRow(
                      data: data,
                      filter: _filter,
                      onFilter: (f) => setState(() => _filter = f),
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
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        inbound.remark,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    _TotalChip(
                      label: '↑ ${formatGb(inbound.upBytes)}',
                    ),
                    const SizedBox(width: 8),
                    _TotalChip(
                      label: '↓ ${formatGb(inbound.downBytes)}',
                    ),
                    const SizedBox(width: 8),
                    _TotalChip(
                      label:
                          'Σ ${formatGb(inbound.upBytes + inbound.downBytes)}',
                      bold: true,
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
                Text(
                  'Live server status',
                  style: Theme.of(context).textTheme.titleMedium,
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
          return Card(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: c.enabled
                    ? Colors.teal.withValues(alpha: 0.3)
                    : Colors.grey.withValues(alpha: 0.3),
                child: Icon(
                  c.enabled ? Icons.person : Icons.person_off,
                  color: c.enabled ? Colors.tealAccent : Colors.grey,
                ),
              ),
              title: Text(
                c.email,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '↑ ${formatGb(c.upBytes)}  ↓ ${formatGb(c.downBytes)}'
                    '  ·  Used ${formatGb(c.usedBytes)}'
                    ' / ${c.isUnlimited ? 'Unlimited' : formatGb(c.quotaBytes)}',
                  ),
                  const SizedBox(height: 6),
                  if (pct != null)
                    LinearProgressIndicator(
                      value: pct.clamp(0.0, 1.0),
                      backgroundColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation(usageColor(c)),
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
              trailing: pct == null
                  ? const Text('—')
                  : Text(
                      '${(pct * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: usageColor(c),
                      ),
                    ),
              isThreeLine: true,
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
