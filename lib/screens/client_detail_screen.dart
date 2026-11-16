/// Full details for one client. Read-only in v0.1 — write actions
/// (renew, quota, delete) are v0.2.
library;

import 'package:flutter/material.dart';

import '../models/panel_models.dart';
import '../utils/format.dart';

class ClientDetailScreen extends StatelessWidget {
  const ClientDetailScreen({required this.client, super.key});

  final ClientInfo client;

  @override
  Widget build(BuildContext context) {
    final c = client;
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
            color: Colors.amber.withValues(alpha: 0.12),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Read-only demo (v0.1). Actions — renew, extend quota, '
                'reset traffic, enable/disable, delete — arrive in v0.2.',
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
