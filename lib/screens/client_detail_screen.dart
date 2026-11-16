/// Full details for one client, with the v0.2 write actions:
/// renew, extend quota x1.35, reset traffic, enable/disable, delete.
///
/// In demo mode the actions apply to the sample data and say so;
/// in live mode they call the panel API (update actions first GET the
/// client record so the UUID is preserved).
library;

import 'package:flutter/material.dart';

import '../models/panel_models.dart';
import '../services/panel_provider.dart';
import '../utils/format.dart';

class ClientDetailScreen extends StatefulWidget {
  const ClientDetailScreen({
    required this.client,
    required this.provider,
    super.key,
  });

  final ClientInfo client;
  final PanelProvider provider;

  @override
  State<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends State<ClientDetailScreen> {
  bool _busy = false;

  ClientInfo get _client {
    // Re-read from the provider so the screen reflects the latest
    // data after an action (the list object is replaced on refresh).
    final fresh = widget.provider.data?.clients
        .where((c) => c.email == widget.client.email)
        .firstOrNull;
    return fresh ?? widget.client;
  }

  Future<void> _run(
    String label,
    Future<(bool, String)> Function() action, {
    bool popOnSuccess = false,
  }) async {
    setState(() => _busy = true);
    final (ok, msg) = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    if (ok && popOnSuccess) Navigator.of(context).pop();
  }

  Future<void> _renew() async {
    final months = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Renew for'),
        children: [
          for (final m in [1, 2, 3, 6])
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(m),
              child: Text('$m month${m > 1 ? 's' : ''}'),
            ),
        ],
      ),
    );
    if (months == null || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renew client?'),
        content: Text(
          'New remark dates start today, +$months month${months > 1 ? 's' : ''}. '
          'Expiry moves to the new end date (+1 day on the panel) '
          'and traffic is reset to zero.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Renew'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(
      'Renew',
      () => widget.provider.renewClient(_client, months),
    );
  }

  Future<void> _extendQuota() async {
    final c = _client;
    if (c.isUnlimited) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unlimited quota — nothing to extend.')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Extend quota x1.35?'),
        content: Text(
          'Quota ${c.quotaGb.toStringAsFixed(1)} GB → '
          '${(c.quotaGb * 1.35).round()} GB (the standing rule for '
          'clients at 80% or more).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Extend'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run('Extend quota', () => widget.provider.extendQuota(_client));
  }

  Future<void> _resetTraffic() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset traffic?'),
        content: const Text(
          'Upload/download counters go back to zero and the client '
          'is re-enabled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run('Reset traffic', () => widget.provider.resetTraffic(_client));
  }

  Future<void> _toggleEnabled() async {
    final c = _client;
    await _run(
      c.enabled ? 'Disable' : 'Enable',
      () => widget.provider.setClientEnabled(c, !c.enabled),
    );
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete client?'),
        content: Text(
          'This removes ${_client.email} from the panel, including '
          'its traffic history. The subscription link stops working. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(
      'Delete',
      () => widget.provider.deleteClient(_client),
      popOnSuccess: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _client;
    final pct = c.usedPct;
    return Scaffold(
      appBar: AppBar(title: Text(c.email)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _Row(label: 'Name / remark', value: c.email),
                  _Row(label: 'Inbound', value: c.inbound),
                  _Row(
                    label: 'Status',
                    value: c.enabled ? 'Enabled' : 'Disabled',
                    valueColor:
                        c.enabled ? Colors.tealAccent : Colors.grey,
                  ),
                  _Row(label: 'Uploaded', value: formatGb(c.upBytes)),
                  _Row(label: 'Downloaded', value: formatGb(c.downBytes)),
                  _Row(label: 'Used total', value: formatGb(c.usedBytes)),
                  _Row(
                    label: 'Quota',
                    value: c.isUnlimited
                        ? 'Unlimited'
                        : formatGb(c.quotaBytes),
                  ),
                  if (pct != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Used'),
                        Text(
                          '${(pct * 100).toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: pct >= 0.95
                                ? Colors.redAccent
                                : pct >= 0.8
                                    ? Colors.amber
                                    : Colors.tealAccent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: pct.clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation(
                        pct >= 0.95
                            ? Colors.redAccent
                            : pct >= 0.8
                                ? Colors.amber
                                : Colors.tealAccent,
                      ),
                    ),
                  ],
                  _Row(
                    label: 'Expiry',
                    value: c.expiry == null
                        ? 'No expiry'
                        : formatDate(c.expiry!),
                  ),
                  _Row(
                    label: 'Days left',
                    value: daysLeftText(c.expiry),
                    valueColor: c.isExpired
                        ? Colors.redAccent
                        : c.isExpiringSoon
                            ? Colors.amber
                            : null,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Actions',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _busy ? null : _renew,
                        icon: const Icon(Icons.autorenew),
                        label: const Text('Renew'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _busy || c.isUnlimited ? null : _extendQuota,
                        icon: const Icon(Icons.trending_up),
                        label: const Text('Quota x1.35'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _busy ? null : _resetTraffic,
                        icon: const Icon(Icons.restart_alt),
                        label: const Text('Reset traffic'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _busy ? null : _toggleEnabled,
                        icon: Icon(
                          c.enabled ? Icons.person_off : Icons.person,
                        ),
                        label: Text(c.enabled ? 'Disable' : 'Enable'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _busy ? null : _delete,
                        icon: const Icon(Icons.delete),
                        label: const Text('Delete'),
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              Colors.red.withValues(alpha: 0.2),
                        ),
                      ),
                    ],
                  ),
                  if (_busy) ...[
                    const SizedBox(height: 12),
                    const Center(child: CircularProgressIndicator()),
                  ],
                  if (widget.provider.showingDemo) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Demo mode: actions change the sample data only '
                      'and are labelled simulated.',
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: valueColor,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
