/// A single 3x-ui client record, as returned by
/// `GET {base}panel/api/clients/get/:email`.
///
/// Verified against the MHSanaei/3x-ui source (commit 85e2ded, module v3):
/// - controller `ClientController.get` returns the record plus its
///   `inboundIds`.
/// - `model.ClientRecord` JSON keys: `id` (DB record id — NOT the UUID),
///   `email`, `subId`, `uuid`, `password`, `auth`, `flow`, `security`,
///   `limitIp`, `totalGB`, `expiryTime`, `enable`, `tgId`, `group`,
///   `comment`, `reset`.
///   (`group` is the logical grouping label — verified in the v3
///   model on pkg.go.dev: `Client.Group string json:"group,omitempty"`
///   and `ClientRecord.Group string json:"group"`.)
/// - `model.Client` (the update/create body) uses `id` for the UUID and
///   `totalGB` for the quota.
///
/// Two facts that shape every write in this app:
/// 1. `Update` (`web/service/client.go`) calls `fillProtocolDefaults`,
///    which generates a NEW UUID when the body's `id` is empty. So an
///    update MUST carry the existing UUID or the client's subscription
///    link breaks. That is why every update first GETs the record.
/// 2. `totalGB` is `int64` (whole GB) in the official v3 model. A
///    fractional value (e.g. 91.1) would fail Go's JSON unmarshal and
///    reject the whole request. Quotas are therefore always sent as
///    whole GB. (The live panel's clientStats `total` can still show a
///    fractional GB — that byte value lives in the traffic table, not
///    in the record.)
library;

class ClientRecord {
  const ClientRecord({
    required this.id,
    required this.email,
    required this.subId,
    required this.uuid,
    required this.password,
    required this.auth,
    required this.flow,
    required this.security,
    required this.limitIp,
    required this.totalGb,
    required this.expiryTimeMs,
    required this.enable,
    required this.tgId,
    required this.comment,
    required this.reset,
    this.group = '',
    this.reverse,
    this.createdAtMs = 0,
    this.updatedAtMs = 0,
  });

  /// Tolerant parse: the GET envelope is `{success, msg, obj}` and
  /// `obj` is `{client: {...}, inboundIds: [...]}`; if `obj` already
  /// looks like a client, it is used directly.
  factory ClientRecord.fromGetEnvelope(Map<String, dynamic> envelope) {
    final obj = envelope['obj'];
    Map<String, dynamic> raw;
    if (obj is Map<String, dynamic> && obj['client'] is Map) {
      raw = obj['client'] as Map<String, dynamic>;
    } else if (obj is Map<String, dynamic>) {
      raw = obj;
    } else {
      raw = const {};
    }
    return ClientRecord.fromJson(raw);
  }

  factory ClientRecord.fromJson(Map<String, dynamic> json) {
    return ClientRecord(
      id: (json['id'] as num?)?.toInt() ?? 0,
      email: (json['email'] as String?) ?? '',
      subId: (json['subId'] as String?) ?? '',
      uuid: (json['uuid'] as String?) ?? '',
      password: (json['password'] as String?) ?? '',
      auth: (json['auth'] as String?) ?? '',
      flow: (json['flow'] as String?) ?? '',
      security: (json['security'] as String?) ?? '',
      limitIp: (json['limitIp'] as num?)?.toInt() ?? 0,
      totalGb: (json['totalGB'] as num?)?.toInt() ?? 0,
      expiryTimeMs: (json['expiryTime'] as num?)?.toInt() ?? 0,
      enable: (json['enable'] as bool?) ?? true,
      tgId: (json['tgId'] as num?)?.toInt() ?? 0,
      comment: (json['comment'] as String?) ?? '',
      reset: (json['reset'] as num?)?.toInt() ?? 0,
      group: (json['group'] as String?) ?? '',
      reverse: json['reverse'] as Map<String, dynamic>?,
      createdAtMs: (json['created_at'] as num?)?.toInt() ?? 0,
      updatedAtMs: (json['updated_at'] as num?)?.toInt() ?? 0,
    );
  }

  /// DB record id. Only used for logging; the API addresses clients
  /// by email, and the UUID below is what the update body needs.
  final int id;
  final String email;
  final String subId;

  /// The VLESS UUID. Sent as `id` in the model.Client update body.
  final String uuid;
  final String password;
  final String auth;
  final String flow;
  final String security;
  final int limitIp;

  /// Quota in whole GB; 0 = unlimited.
  final int totalGb;

  /// Expiry as epoch millis; 0 = no expiry.
  final int expiryTimeMs;
  final bool enable;
  final int tgId;
  final String comment;
  final int reset;

  /// Logical grouping label (MNA, MayZin, Friends, FOC, …).
  /// Carried through on every update so a renewal / quota change
  /// never wipes the client's group.
  final String group;

  /// VLESS reverse-proxy settings, carried through untouched when the
  /// record has them (unused for this panel's clients).
  final Map<String, dynamic>? reverse;

  /// Panel record timestamps (epoch ms, 0 = not present). Used by
  /// Fix names (v0.2.2) to derive a start date for dateless
  /// remarks; never sent back to the panel.
  final int createdAtMs;
  final int updatedAtMs;

  /// The `model.Client` JSON body for `POST /clients/update/:email`.
  ///
  /// Starts from the record's own fields (so nothing the app did not
  /// intend to change is zeroed) and applies only the given overrides.
  /// The UUID is always sent as `id` — never leave it empty, or the
  /// panel generates a new UUID and the client's link breaks.
  /// The group is always sent too, for the same reason: an update
  /// without it would clear the client's group on the panel.
  Map<String, dynamic> toClientJson({
    String? email,
    int? totalGb,
    int? expiryTimeMs,
    bool? enable,
    String? comment,
    String? group,
  }) {
    final body = <String, dynamic>{
      'id': uuid,
      'email': email ?? this.email,
      'limitIp': limitIp,
      'totalGB': totalGb ?? this.totalGb,
      'expiryTime': expiryTimeMs ?? this.expiryTimeMs,
      'enable': enable ?? this.enable,
      'tgId': tgId,
      'subId': subId,
      'group': group ?? this.group,
      'comment': comment ?? this.comment,
      'reset': reset,
    };
    if (flow.isNotEmpty) body['flow'] = flow;
    if (password.isNotEmpty) body['password'] = password;
    if (auth.isNotEmpty) body['auth'] = auth;
    if (security.isNotEmpty) body['security'] = security;
    if (reverse != null) body['reverse'] = reverse;
    return body;
  }
}
