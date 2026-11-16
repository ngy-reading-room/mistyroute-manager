/// Read-only client for the 3x-ui panel API.
///
/// Verified read path (same call the daily check uses):
///   GET {base}panel/api/inbounds/list
///   Header: `Authorization: Bearer <token>`
///   Response envelope: {success, msg, obj}
///
/// Live status (verified against the MHSanaei/3x-ui source,
/// web/service/server.go `Status` struct):
///   GET {base}panel/api/server/status
///   obj.netIO.up / obj.netIO.down are live bytes/sec.
///
/// Write path (v0.2 — verified against the MHSanaei/3x-ui source,
/// commit 85e2ded, module v3: web/controller/client.go +
/// web/service/client.go + internal/database/model):
///   GET    {base}panel/api/clients/get/:email
///     -> obj `{client: <ClientRecord>, inboundIds: [...]}`
///   POST   {base}panel/api/clients/add
///     body `{"client": <model.Client>, "inboundIds": [id]}`
///   POST   {base}panel/api/clients/update/:email
///     body `<model.Client>` — MUST carry the existing UUID as `id`,
///     or the panel generates a new one and the client's link breaks.
///     totalGB is whole GB (int64).
///   POST   {base}panel/api/clients/del/:email?keepTraffic=1
///   POST   {base}panel/api/clients/resetTraffic/:email
///   All write calls return the same {success, msg, obj} envelope.
///   Auth is the same Bearer API token everywhere — no username,
///   password or 2FA fields exist in this app, ever.
///
/// NOTE on web: the panel does not advertise CORS headers, so a browser
/// fetch from the Pages host may be blocked by the browser even when the
/// panel is up. The Android app has no CORS restriction. A failed live
/// fetch surfaces its error instead of silently showing stale data.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/client_record.dart';
import '../models/panel_models.dart';

class PanelApiException implements Exception {
  PanelApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

class PanelApiService {
  PanelApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Normalise the user-entered base URL: trim, ensure a scheme and a
  /// trailing slash. Throws [PanelApiException] on an unusable value.
  static String normalizeBaseUrl(String raw) {
    var base = raw.trim();
    if (base.isEmpty) throw PanelApiException('Panel URL is empty.');
    if (!base.startsWith('http://') && !base.startsWith('https://')) {
      base = 'https://$base';
    }
    if (!base.endsWith('/')) base += '/';
    final uri = Uri.tryParse(base);
    if (uri == null || uri.host.isEmpty) {
      throw PanelApiException('Panel URL looks invalid: $raw');
    }
    return base;
  }

  /// GET inbounds/list — the dashboard's main data source.
  Future<PanelData> fetchInbounds({
    required String baseUrl,
    required String token,
  }) async {
    final base = normalizeBaseUrl(baseUrl);
    if (token.trim().isEmpty) {
      throw PanelApiException('API token is empty.');
    }
    final uri = Uri.parse('${base}panel/api/inbounds/list');
    late http.Response res;
    try {
      res = await _client.get(
        uri,
        headers: {
          'Authorization': 'Bearer ${token.trim()}',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 20));
    } on Exception catch (e) {
      throw PanelApiException('Could not reach the panel: $e');
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw PanelApiException(
        'Panel refused the request (${res.statusCode}). '
        'Check the API token (and that the tunnel is up).',
      );
    }
    if (res.statusCode != 200) {
      throw PanelApiException(
        'Panel answered HTTP ${res.statusCode}. Is the tunnel up?',
      );
    }
    Map<String, dynamic> envelope;
    try {
      envelope = jsonDecode(res.body) as Map<String, dynamic>;
    } on Exception {
      throw PanelApiException('Panel answered, but not with JSON.');
    }
    if (envelope['success'] != true) {
      throw PanelApiException(
        'Panel reported an error: ${envelope['msg'] ?? 'unknown'}',
      );
    }
    return PanelData.fromInboundsJson(envelope);
  }

  /// GET server/status — best-effort. Returns null on any failure so the
  /// dashboard still works when this endpoint is unavailable.
  Future<ServerStatus?> fetchServerStatus({
    required String baseUrl,
    required String token,
  }) async {
    try {
      final base = normalizeBaseUrl(baseUrl);
      final uri = Uri.parse('${base}panel/api/server/status');
      final res = await _client.get(
        uri,
        headers: {
          'Authorization': 'Bearer ${token.trim()}',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final envelope = jsonDecode(res.body) as Map<String, dynamic>;
      if (envelope['success'] != true) return null;
      final obj = envelope['obj'] as Map<String, dynamic>?;
      if (obj == null) return null;
      return ServerStatus.fromJson(obj);
    } on Exception {
      return null;
    }
  }

  // ---- Write path (v0.2) ----

  Map<String, String> _authHeaders(String token) => {
        'Authorization': 'Bearer ${token.trim()}',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };

  void _requireToken(String token) {
    if (token.trim().isEmpty) {
      throw PanelApiException('API token is empty.');
    }
  }

  /// POST helper: sends a JSON body (or none), checks HTTP status and
  /// the {success, msg, obj} envelope. Returns the decoded envelope.
  Future<Map<String, dynamic>> _postJson({
    required String baseUrl,
    required String token,
    required String path,
    Map<String, dynamic>? body,
  }) async {
    final base = normalizeBaseUrl(baseUrl);
    _requireToken(token);
    final uri = Uri.parse('$base$path');
    late http.Response res;
    try {
      res = await _client
          .post(
            uri,
            headers: _authHeaders(token),
            body: body == null ? null : jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));
    } on Exception catch (e) {
      throw PanelApiException('Could not reach the panel: $e');
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw PanelApiException(
        'Panel refused the request (${res.statusCode}). '
        'Check the API token (and that the tunnel is up).',
      );
    }
    if (res.statusCode != 200) {
      throw PanelApiException(
        'Panel answered HTTP ${res.statusCode}. Is the tunnel up?',
      );
    }
    Map<String, dynamic> envelope;
    try {
      envelope = jsonDecode(res.body) as Map<String, dynamic>;
    } on Exception {
      throw PanelApiException('Panel answered, but not with JSON.');
    }
    if (envelope['success'] != true) {
      throw PanelApiException(
        'Panel reported an error: ${envelope['msg'] ?? 'unknown'}',
      );
    }
    return envelope;
  }

  /// GET the full client record (UUID, subId, flow, quota, ...).
  /// Every update starts here so the UUID is preserved.
  Future<ClientRecord> fetchClientRecord({
    required String baseUrl,
    required String token,
    required String email,
  }) async {
    final base = normalizeBaseUrl(baseUrl);
    _requireToken(token);
    final uri = Uri.parse(
      '${base}panel/api/clients/get/${Uri.encodeComponent(email)}',
    );
    late http.Response res;
    try {
      res = await _client.get(
        uri,
        headers: {
          'Authorization': 'Bearer ${token.trim()}',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 20));
    } on Exception catch (e) {
      throw PanelApiException('Could not reach the panel: $e');
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw PanelApiException(
        'Panel refused the request (${res.statusCode}). '
        'Check the API token (and that the tunnel is up).',
      );
    }
    if (res.statusCode != 200) {
      throw PanelApiException(
        'Panel answered HTTP ${res.statusCode}. Is the tunnel up?',
      );
    }
    Map<String, dynamic> envelope;
    try {
      envelope = jsonDecode(res.body) as Map<String, dynamic>;
    } on Exception {
      throw PanelApiException('Panel answered, but not with JSON.');
    }
    if (envelope['success'] != true) {
      throw PanelApiException(
        'Panel reported an error: ${envelope['msg'] ?? 'unknown'}',
      );
    }
    return ClientRecord.fromGetEnvelope(envelope);
  }

  /// POST /panel/api/clients/add — body is the
  /// `{"client": ..., "inboundIds": [...]}` map from
  /// `buildCreatePayload` (see client_actions.dart).
  Future<void> addClient({
    required String baseUrl,
    required String token,
    required Map<String, dynamic> payload,
  }) async {
    await _postJson(
      baseUrl: baseUrl,
      token: token,
      path: 'panel/api/clients/add',
      body: payload,
    );
  }

  /// POST /panel/api/clients/update/:email — body is the raw
  /// model.Client JSON from `ClientRecord.toClientJson()`.
  /// `email` is the CURRENT email (the URL key); the body's email may
  /// differ (rename on renewal).
  Future<void> updateClient({
    required String baseUrl,
    required String token,
    required String email,
    required Map<String, dynamic> clientJson,
  }) async {
    await _postJson(
      baseUrl: baseUrl,
      token: token,
      path: 'panel/api/clients/update/${Uri.encodeComponent(email)}',
      body: clientJson,
    );
  }

  /// POST /panel/api/clients/del/:email — `keepTraffic` keeps the
  /// traffic rows (default false: traffic + IP rows are deleted too).
  Future<void> deleteClient({
    required String baseUrl,
    required String token,
    required String email,
    bool keepTraffic = false,
  }) async {
    await _postJson(
      baseUrl: baseUrl,
      token: token,
      path: 'panel/api/clients/del/${Uri.encodeComponent(email)}'
          '?keepTraffic=${keepTraffic ? 1 : 0}',
    );
  }

  /// POST /panel/api/clients/resetTraffic/:email — zeroes up/down
  /// and re-enables the client.
  Future<void> resetClientTraffic({
    required String baseUrl,
    required String token,
    required String email,
  }) async {
    await _postJson(
      baseUrl: baseUrl,
      token: token,
      path: 'panel/api/clients/resetTraffic/${Uri.encodeComponent(email)}',
    );
  }
}
