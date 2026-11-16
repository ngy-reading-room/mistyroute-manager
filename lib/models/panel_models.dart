/// Data models mirroring the 3x-ui panel API responses.
///
/// Inbounds list shape (verified against the panel's read path — see
/// vpn-api-collect.py and the 3x-ui API docs):
///   GET {base}panel/api/inbounds/list  ->  {success, msg, obj: [...]}
///   inbound: {id, protocol, remark, up, down, clientStats: [...]}
///   clientStat: {email, up, down, total, expiryTime, enable}
///     - total: quota in bytes; 0 = unlimited
///     - expiryTime: epoch millis; 0 = no expiry
///
/// Server status shape (verified against the MHSanaei/3x-ui source,
/// web/service/server.go `Status` struct, and the v3 deepwiki doc):
///   GET {base}panel/api/server/status  ->  {success, msg, obj: {...}}
///   obj: {cpu, cpuCores, mem: {current, total}, xray: {state, version},
///         uptime, netIO: {up, down}, ...}
///   netIO up/down are bytes/sec (live speed).
library;

/// One VPN client (one entry of an inbound's clientStats array).
///
/// `group` is the panel's logical grouping label (MNA, MayZin,
/// Friends, FOC, …). It does NOT come from inbounds/list —
/// clientStats has no group field — it is filled in from the full
/// client record (`GET panel/api/clients/get/:email`, where the
/// v3 model.Client / ClientRecord both carry `group`). Until that
/// enrichment runs, group is '' (ungrouped).
class ClientInfo {
  const ClientInfo({
    required this.email,
    required this.inbound,
    required this.enabled,
    required this.upBytes,
    required this.downBytes,
    required this.quotaBytes,
    required this.expiryTimeMs,
    this.group = '',
  });

  factory ClientInfo.fromJson(Map<String, dynamic> json, String inbound) {
    return ClientInfo(
      email: (json['email'] as String?) ?? 'Unknown',
      inbound: inbound,
      enabled: (json['enable'] as bool?) ?? true,
      upBytes: (json['up'] as num?)?.toInt() ?? 0,
      downBytes: (json['down'] as num?)?.toInt() ?? 0,
      quotaBytes: (json['total'] as num?)?.toInt() ?? 0,
      expiryTimeMs: (json['expiryTime'] as num?)?.toInt() ?? 0,
      group: (json['group'] as String?) ?? '',
    );
  }

  /// Display name — in this panel the `email` field holds the remark
  /// (e.g. "MaSandar-1_15.11.26-15.2.27"), not a real email address.
  final String email;
  final String inbound;
  final bool enabled;
  final int upBytes;
  final int downBytes;

  /// Quota in bytes; 0 means unlimited.
  final int quotaBytes;

  /// Expiry as epoch millis; 0 means no expiry.
  final int expiryTimeMs;

  /// Panel group label ('' = no group / not loaded yet).
  final String group;

  ClientInfo copyWith({
    String? email,
    bool? enabled,
    int? upBytes,
    int? downBytes,
    int? quotaBytes,
    int? expiryTimeMs,
    String? group,
  }) {
    return ClientInfo(
      email: email ?? this.email,
      inbound: inbound,
      enabled: enabled ?? this.enabled,
      upBytes: upBytes ?? this.upBytes,
      downBytes: downBytes ?? this.downBytes,
      quotaBytes: quotaBytes ?? this.quotaBytes,
      expiryTimeMs: expiryTimeMs ?? this.expiryTimeMs,
      group: group ?? this.group,
    );
  }

  int get usedBytes => upBytes + downBytes;

  double get usedGb => usedBytes / (1024 * 1024 * 1024);
  double get upGb => upBytes / (1024 * 1024 * 1024);
  double get downGb => downBytes / (1024 * 1024 * 1024);
  double get quotaGb => quotaBytes / (1024 * 1024 * 1024);

  bool get isUnlimited => quotaBytes == 0;

  /// 0.0–1.0+ ; null when unlimited.
  double? get usedPct => isUnlimited ? null : usedBytes / quotaBytes;

  DateTime? get expiry => expiryTimeMs > 0
      ? DateTime.fromMillisecondsSinceEpoch(expiryTimeMs)
      : null;

  int? get daysToExpiry {
    final e = expiry;
    if (e == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final exp = DateTime(e.year, e.month, e.day);
    return exp.difference(today).inDays;
  }

  bool get isExpired => (daysToExpiry ?? 1) < 0;

  bool get isExpiringSoon {
    final d = daysToExpiry;
    return d != null && d >= 0 && d <= 7;
  }

  bool get isOver80 {
    final p = usedPct;
    return p != null && p >= 0.8;
  }
}

/// One inbound (VLESS, etc.) with its traffic totals.
///
/// `id` and `protocol` come from the same inbounds/list response and
/// are what the v0.2 write actions need: add-client targets the
/// inbound id, and the protocol decides the client credential shape
/// (VLESS -> UUID + xtls-rprx-vision flow).
class InboundInfo {
  const InboundInfo({
    required this.id,
    required this.protocol,
    required this.remark,
    required this.upBytes,
    required this.downBytes,
  });

  final int id;
  final String protocol;
  final String remark;
  final int upBytes;
  final int downBytes;
}

/// Live server status (best-effort; null when the call fails).
class ServerStatus {
  const ServerStatus({
    required this.cpu,
    required this.memCurrent,
    required this.memTotal,
    required this.xrayState,
    required this.xrayVersion,
    required this.uptimeSeconds,
    required this.netUpBytesPerSec,
    required this.netDownBytesPerSec,
  });

  /// Tolerant parse: only the fields the dashboard shows are read;
  /// everything else is ignored so a newer/older panel shape still works.
  factory ServerStatus.fromJson(Map<String, dynamic> json) {
    final mem = json['mem'] as Map<String, dynamic>? ?? {};
    final xray = json['xray'] as Map<String, dynamic>? ?? {};
    final netIO = json['netIO'] as Map<String, dynamic>? ?? {};
    return ServerStatus(
      cpu: (json['cpu'] as num?)?.toDouble() ?? 0,
      memCurrent: (mem['current'] as num?)?.toInt() ?? 0,
      memTotal: (mem['total'] as num?)?.toInt() ?? 0,
      xrayState: (xray['state'] as String?) ?? 'unknown',
      xrayVersion: (xray['version'] as String?) ?? '',
      uptimeSeconds: (json['uptime'] as num?)?.toInt() ?? 0,
      netUpBytesPerSec: (netIO['up'] as num?)?.toInt() ?? 0,
      netDownBytesPerSec: (netIO['down'] as num?)?.toInt() ?? 0,
    );
  }

  final double cpu;
  final int memCurrent;
  final int memTotal;
  final String xrayState;
  final String xrayVersion;
  final int uptimeSeconds;
  final int netUpBytesPerSec;
  final int netDownBytesPerSec;

  double get memPct => memTotal > 0 ? memCurrent / memTotal : 0;
}

/// Everything the dashboard needs: inbounds + flat client list + status.
class PanelData {
  const PanelData({
    required this.inbounds,
    required this.clients,
    this.serverStatus,
  });

  /// Parse the {success, msg, obj} envelope of inbounds/list.
  factory PanelData.fromInboundsJson(Map<String, dynamic> envelope) {
    final inbounds = <InboundInfo>[];
    final clients = <ClientInfo>[];
    final obj = envelope['obj'] as List<dynamic>? ?? [];
    for (final raw in obj) {
      final inbound = raw as Map<String, dynamic>;
      final remark = (inbound['remark'] as String?) ?? 'Inbound';
      inbounds.add(InboundInfo(
        id: (inbound['id'] as num?)?.toInt() ?? 0,
        protocol: (inbound['protocol'] as String?) ?? '',
        remark: remark,
        upBytes: (inbound['up'] as num?)?.toInt() ?? 0,
        downBytes: (inbound['down'] as num?)?.toInt() ?? 0,
      ));
      final stats = inbound['clientStats'] as List<dynamic>? ?? [];
      for (final cs in stats) {
        clients.add(ClientInfo.fromJson(cs as Map<String, dynamic>, remark));
      }
    }
    return PanelData(inbounds: inbounds, clients: clients);
  }

  final List<InboundInfo> inbounds;
  final List<ClientInfo> clients;
  final ServerStatus? serverStatus;

  PanelData copyWith({List<ClientInfo>? clients, ServerStatus? serverStatus}) =>
      PanelData(
        inbounds: inbounds,
        clients: clients ?? this.clients,
        serverStatus: serverStatus ?? this.serverStatus,
      );

  /// Group -> client count, non-empty groups only, sorted by name.
  /// Only groups actually present get a filter chip.
  Map<String, int> get groupCounts {
    final counts = <String, int>{};
    for (final c in clients) {
      if (c.group.isEmpty) continue;
      counts[c.group] = (counts[c.group] ?? 0) + 1;
    }
    return Map.fromEntries(
      counts.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  /// Clients with no group ('' — e.g. the owner's own key).
  int get ungroupedCount => clients.where((c) => c.group.isEmpty).length;

  List<ClientInfo> get byUsageDesc {
    final sorted = List<ClientInfo>.from(clients);
    sorted.sort((a, b) => b.usedBytes.compareTo(a.usedBytes));
    return sorted;
  }

  List<ClientInfo> get over80 => clients.where((c) => c.isOver80).toList();
  List<ClientInfo> get expiringSoon =>
      clients.where((c) => c.isExpiringSoon).toList();
  List<ClientInfo> get disabled => clients.where((c) => !c.enabled).toList();
}
