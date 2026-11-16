/// Clearly-labelled SAMPLE data for the demo mode.
///
/// Same shapes as the real panel API (inbounds/list envelope), but every
/// client is fictional ("Demo User NN") — no real client names, quotas or
/// traffic are in here, so this file is safe to ship in a public repo.
///
/// Coverage (24 clients): 3 over 80% quota, 3 expiring within 7 days,
/// 1 already expired, 2 disabled, 2 unlimited, the rest healthy.
/// Groups: MNA 8, MayZin 10, Friends 4, FOC 1, ungrouped 1.
library;

import '../models/panel_models.dart';

int _gb(double gb) => (gb * 1024 * 1024 * 1024).round();

ClientInfo _c({
  required String name,
  required double upGb,
  required double downGb,
  required double quotaGb, // 0 = unlimited
  required int daysToExpiry, // huge number = effectively no expiry
  bool enabled = true,
  String group = '',
  int? createdAtMs,
  int? updatedAtMs,
}) {
  final expiryMs = daysToExpiry > 9000
      ? 0
      : DateTime.now()
          .add(Duration(days: daysToExpiry))
          .millisecondsSinceEpoch;
  final now = DateTime.now();
  return ClientInfo(
    email: name,
    inbound: 'VLESS Reality',
    enabled: enabled,
    upBytes: _gb(upGb),
    downBytes: _gb(downGb),
    quotaBytes: _gb(quotaGb),
    expiryTimeMs: expiryMs,
    group: group,
    subId: name,
    // Record timestamps mirror the real panel (v0.2.2): by
    // default created 45 days ago, last edited 7 days ago
    // (unique per client). Overrides below exercise the other
    // Fix-names paths — a shared bulk stamp and a never-edited
    // record — so demo mode previews all of them.
    createdAtMs: createdAtMs ??
        now.subtract(const Duration(days: 45)).millisecondsSinceEpoch,
    updatedAtMs: updatedAtMs ??
        now.subtract(const Duration(days: 7)).millisecondsSinceEpoch,
  );
}

/// One shared updated_at value (the demo equivalent of the panel's
/// Nov 3 bulk stamp): two clients share it, so Fix names must
/// never trust it as a start date.
final _bulkStampMs = DateTime.now()
    .subtract(const Duration(days: 14))
    .millisecondsSinceEpoch;

PanelData buildDemoData() {
  final clients = <ClientInfo>[
    // Over 80% quota (3).
    // 01: trusted last edit 5 days ago -> Fix names starts there.
    _c(name: 'Demo User 01', upGb: 12.4, downGb: 46.0, quotaGb: 60, daysToExpiry: 24, group: 'MNA',
        updatedAtMs: DateTime.now().subtract(const Duration(days: 5)).millisecondsSinceEpoch),
    // 02 + 03 share the bulk stamp -> Fix names falls back to
    // end minus 1 month for both.
    _c(name: 'Demo User 02', upGb: 9.1, downGb: 79.3, quotaGb: 100, daysToExpiry: 41, group: 'MayZin',
        updatedAtMs: _bulkStampMs),
    _c(name: 'Demo User 03', upGb: 4.2, downGb: 50.9, quotaGb: 67.5, daysToExpiry: 9, group: 'MayZin',
        updatedAtMs: _bulkStampMs),
    // Expiring within 7 days (3).
    // 04: never edited since creation -> Fix names starts on the
    // creation date.
    _c(name: 'Demo User 04', upGb: 3.0, downGb: 11.5, quotaGb: 50, daysToExpiry: 2, group: 'MNA',
        createdAtMs: DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch,
        updatedAtMs: DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch),
    _c(name: 'Demo User 05', upGb: 6.8, downGb: 22.1, quotaGb: 60, daysToExpiry: 5, group: 'Friends'),
    _c(name: 'Demo User 06', upGb: 1.1, downGb: 5.4, quotaGb: 100, daysToExpiry: 7, group: 'MayZin'),
    // Already expired (1).
    _c(name: 'Demo User 07', upGb: 2.2, downGb: 8.8, quotaGb: 50, daysToExpiry: -3, group: 'MNA'),
    // Disabled (2).
    _c(name: 'Demo User 08', upGb: 0.4, downGb: 1.2, quotaGb: 50, daysToExpiry: 30, group: 'MayZin', enabled: false),
    _c(name: 'Demo User 09', upGb: 0.0, downGb: 0.0, quotaGb: 100, daysToExpiry: 60, group: 'Friends', enabled: false),
    // Unlimited quota (2).
    _c(name: 'Demo User 10', upGb: 18.3, downGb: 96.7, quotaGb: 0, daysToExpiry: 90, group: ''),
    _c(name: 'Demo User 11', upGb: 7.7, downGb: 31.2, quotaGb: 0, daysToExpiry: 9999, group: 'FOC'),
    // Healthy remainder (13).
    _c(name: 'Demo User 12', upGb: 5.5, downGb: 18.9, quotaGb: 100, daysToExpiry: 55, group: 'MayZin'),
    _c(name: 'Demo User 13', upGb: 2.9, downGb: 9.6, quotaGb: 50, daysToExpiry: 18, group: 'MNA'),
    _c(name: 'Demo User 14', upGb: 8.0, downGb: 27.4, quotaGb: 60, daysToExpiry: 33, group: 'MayZin'),
    _c(name: 'Demo User 15', upGb: 1.6, downGb: 4.3, quotaGb: 50, daysToExpiry: 12, group: 'Friends'),
    _c(name: 'Demo User 16', upGb: 11.2, downGb: 38.8, quotaGb: 100, daysToExpiry: 70, group: 'MayZin'),
    _c(name: 'Demo User 17', upGb: 0.9, downGb: 2.1, quotaGb: 50, daysToExpiry: 44, group: 'MNA'),
    _c(name: 'Demo User 18', upGb: 6.1, downGb: 19.7, quotaGb: 60, daysToExpiry: 26, group: 'MayZin'),
    _c(name: 'Demo User 19', upGb: 3.7, downGb: 12.8, quotaGb: 100, daysToExpiry: 81, group: 'MNA'),
    _c(name: 'Demo User 20', upGb: 0.3, downGb: 0.8, quotaGb: 50, daysToExpiry: 15, group: 'MayZin'),
    _c(name: 'Demo User 21', upGb: 9.9, downGb: 33.1, quotaGb: 100, daysToExpiry: 63, group: 'MNA'),
    _c(name: 'Demo User 22', upGb: 4.4, downGb: 15.9, quotaGb: 60, daysToExpiry: 38, group: 'Friends'),
    _c(name: 'Demo User 23', upGb: 2.0, downGb: 7.3, quotaGb: 50, daysToExpiry: 21, group: 'MayZin'),
    _c(name: 'Demo User 24', upGb: 13.5, downGb: 44.2, quotaGb: 100, daysToExpiry: 48, group: 'MNA'),
  ];

  var up = 0;
  var down = 0;
  for (final c in clients) {
    up += c.upBytes;
    down += c.downBytes;
  }
  return PanelData(
    inbounds: [
      InboundInfo(id: 1, protocol: 'vless', remark: 'VLESS Reality', upBytes: up, downBytes: down),
    ],
    clients: clients,
    serverStatus: const ServerStatus(
      cpu: 12.5,
      memCurrent: 1288490188, // 1.2 GB
      memTotal: 2147483648, // 2 GB
      xrayState: 'running',
      xrayVersion: '26.10.21',
      uptimeSeconds: 432000, // 5 days
      netUpBytesPerSec: 1258291, // 1.2 MB/s
      netDownBytesPerSec: 8808038, // 8.4 MB/s
    ),
  );
}
