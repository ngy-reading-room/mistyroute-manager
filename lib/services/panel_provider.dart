/// Holds the dashboard state: settings, loaded panel data, and whether
/// what is shown is live data from the panel or labelled demo data.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/client_record.dart';
import '../models/panel_models.dart';
import 'billing.dart';
import 'client_actions.dart';
import 'demo_data.dart';
import 'panel_api.dart';
import 'settings_service.dart';
import 'sheets_sync_service.dart';

enum DataMode { demo, live }

class PanelProvider extends ChangeNotifier {
  PanelProvider({
    PanelApiService? api,
    SettingsService? settings,
    SheetsSyncService? sheets,
  })  : _api = api ?? PanelApiService(),
        _settingsService = settings ?? SettingsService(),
        _sheets = sheets ?? SheetsSyncService();

  final PanelApiService _api;
  final SettingsService _settingsService;
  final SheetsSyncService _sheets;

  PanelSettings settings = const PanelSettings();
  PanelData? data;
  DataMode mode = DataMode.demo;
  bool isLoading = false;
  String? error;
  DateTime? lastUpdated;

  /// Billing estimate from the panel/VPS data (no DO token needed).
  /// Null until the first refresh.
  BillingEstimate? billing;

  /// DO account balance (month-to-date, USD string) when a DO token
  /// is saved and the check succeeded; null otherwise.
  String? doBalance;

  Future<void> init() async {
    settings = await _settingsService.load();
    await refresh();
  }

  bool get showingDemo => mode == DataMode.demo;

  /// Billing estimate from a PanelData snapshot: the inbound "down"
  /// total is traffic the server sent to clients = DO outbound.
  void _computeBilling(PanelData d) {
    final outbound = d.inbounds.fold<int>(0, (s, i) => s + i.downBytes);
    billing = computeBilling(outboundBytes: outbound);
  }

  /// Loads demo data or fetches live data, depending on settings.
  Future<void> refresh() async {
    if (settings.useDemoData || !settings.hasLiveCredentials) {
      mode = DataMode.demo;
      error = null;
      isLoading = false;
      data = buildDemoData();
      _computeBilling(data!);
      lastUpdated = DateTime.now();
      notifyListeners();
      return;
    }
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      var live = await _api.fetchInbounds(
        baseUrl: settings.panelUrl,
        token: settings.apiToken,
      );
      final status = await _api.fetchServerStatus(
        baseUrl: settings.panelUrl,
        token: settings.apiToken,
      );
      live = live.copyWith(serverStatus: status);
      data = live;
      _computeBilling(live);
      mode = DataMode.live;
      lastUpdated = DateTime.now();
      isLoading = false;
      notifyListeners();
      // Groups are not in inbounds/list — fill them in from the
      // per-client records in the background, so the list shows
      // immediately and the group chips appear once loaded.
      // The same records also carry the subId and the
      // created/updated timestamps Fix names and Sheets sync need.
      unawaited(_enrichClientDetails(live));
    } on PanelApiException catch (e) {
      error = e.message;
      data = null;
      isLoading = false;
      notifyListeners();
    } on Exception catch (e) {
      error = 'Unexpected error: $e';
      data = null;
      isLoading = false;
      notifyListeners();
    }
  }

  int _refreshGen = 0;

  /// Fetch each client's group, subId and record timestamps
  /// (`GET clients/get/:email`) in parallel and attach them to the
  /// dashboard data. Best-effort: a failed lookup leaves that
  /// client ungrouped ('') with no subId/timestamps. A newer
  /// refresh supersedes an in-flight enrichment.
  Future<void> _enrichClientDetails(PanelData live) async {
    final gen = ++_refreshGen;
    final enriched = await Future.wait(
      live.clients.map((c) async {
        try {
          final record = await _api.fetchClientRecord(
            baseUrl: _baseUrl,
            token: _token,
            email: c.email,
          );
          return c.copyWith(
            group: record.group,
            subId: record.subId,
            createdAtMs: record.createdAtMs,
            updatedAtMs: record.updatedAtMs,
          );
        } on Exception {
          return c;
        }
      }),
    );
    if (gen != _refreshGen) return;
    data = live.copyWith(clients: enriched);
    notifyListeners();
  }

  /// The updated_at values shared by more than one loaded client
  /// (the panel's bulk stamp) — Fix names must never trust them
  /// as a start date. Values of 0 (not loaded) never count.
  Set<int> _sharedUpdatedAtValues() =>
      bulkUpdatedAtValues(data?.clients.map((c) => c.updatedAtMs) ?? []);

  /// Fetch per-client records for the clients whose subId is still
  /// unknown (needed by Sheets sync for the subscription URL).
  /// Best-effort: failures leave the subId empty and the sync
  /// keeps the sheet's existing URL for that row.
  Future<void> _ensureSubIds() async {
    final live = data;
    if (live == null || showingDemo) return;
    final missing = live.clients.where((c) => c.subId.isEmpty).toList();
    if (missing.isEmpty) return;
    final enriched = await Future.wait(
      live.clients.map((c) async {
        if (c.subId.isNotEmpty) return c;
        try {
          final record = await _api.fetchClientRecord(
            baseUrl: _baseUrl,
            token: _token,
            email: c.email,
          );
          return c.copyWith(
            group: c.group.isEmpty ? record.group : c.group,
            subId: record.subId,
            createdAtMs: record.createdAtMs,
            updatedAtMs: record.updatedAtMs,
          );
        } on Exception {
          return c;
        }
      }),
    );
    data = live.copyWith(clients: enriched);
    notifyListeners();
  }

  /// Sync the loaded clients to the `vlesslist` spreadsheet
  /// (see SheetsSyncService). Demo mode is refused outright:
  /// syncing sample clients would overwrite the real sheet.
  /// Returns (ok, message) for the Settings screen to show.
  Future<(bool, String)> syncSheets({
    required String accessToken,
    required String spreadsheetId,
  }) async {
    if (showingDemo) {
      return (
        false,
        'Demo data is on — turn it off in Settings first, so the '
            'real sheet is never overwritten with sample clients.',
      );
    }
    final clients = data?.clients ?? [];
    if (clients.isEmpty) {
      return (false, 'No clients to sync — load the dashboard first.');
    }
    await _ensureSubIds();
    return _sheets.sync(
      accessToken: accessToken,
      spreadsheetId: spreadsheetId,
      clients: data?.clients ?? clients,
    );
  }

  Future<void> saveSettings(PanelSettings next) async {
    settings = next;
    await _settingsService.save(next);
    await refresh();
  }

  Future<void> setDemoMode(bool useDemo) async {
    await saveSettings(settings.copyWith(useDemoData: useDemo));
  }

  Future<void> clearCredentials() async {
    await _settingsService.clearCredentials();
    settings = settings.copyWith(panelUrl: '', apiToken: '');
    await _settingsService.save(settings);
    await refresh();
  }

  /// Optional, secondary only: fetch the DO account balance with
  /// the saved DO token. Returns a message for the Settings button;
  /// a failure leaves the panel-data estimate untouched.
  Future<String> checkDoBalance() async {
    final token = settings.doApiToken.trim();
    if (token.isEmpty) {
      return 'No DO token saved — the Billing estimate above needs none.';
    }
    final balance = await fetchDoBalance(token: token);
    if (balance == null) {
      return 'Could not reach DigitalOcean — check the token or try later. '
          'The Billing estimate is unaffected.';
    }
    doBalance = balance;
    notifyListeners();
    return 'DO month-to-date balance: \$$balance';
  }

  /// Tries a live fetch without changing the displayed data.
  /// Returns (ok, message) for the Settings "Test connection" button.
  Future<(bool, String)> testConnection(String url, String token) async {
    try {
      final live = await _api.fetchInbounds(baseUrl: url, token: token);
      return (
        true,
        'Connected: ${live.clients.length} clients in '
            '${live.inbounds.length} inbound(s).'
      );
    } on PanelApiException catch (e) {
      return (false, e.message);
    } on Exception catch (e) {
      return (false, 'Unexpected error: $e');
    }
  }

  // ---- Write actions (v0.2) ----
  //
  // Live mode: call the panel API (update actions first GET the client
  // record so the UUID is preserved), then refresh the dashboard.
  // Demo mode: apply the same change to the in-memory sample data so
  // the action can be previewed; the message says "(simulated)".
  // Every method returns (ok, message) for the UI to show.

  String get _baseUrl => settings.panelUrl;
  String get _token => settings.apiToken;

  /// Rebuild the current data with a modified client list (demo-mode
  /// simulation). Inbound totals are recomputed from the clients.
  void _simulate(List<ClientInfo> clients) {
    final current = data;
    if (current == null) return;
    final inbounds = current.inbounds.map((ib) {
      var up = 0;
      var down = 0;
      for (final c in clients) {
        if (c.inbound == ib.remark) {
          up += c.upBytes;
          down += c.downBytes;
        }
      }
      return InboundInfo(
        id: ib.id,
        protocol: ib.protocol,
        remark: ib.remark,
        upBytes: up,
        downBytes: down,
      );
    }).toList();
    data = PanelData(
      inbounds: inbounds,
      clients: clients,
      serverStatus: current.serverStatus,
    );
    lastUpdated = DateTime.now();
    notifyListeners();
  }

  List<ClientInfo> _replaced(ClientInfo old, ClientInfo next) {
    final clients = List<ClientInfo>.from(data?.clients ?? []);
    final i = clients.indexWhere((c) => c.email == old.email);
    if (i >= 0) clients[i] = next;
    return clients;
  }

  Future<(bool, String)> addClient({
    required String name,
    required int quotaGb,
    required int months,
    required int limitIp,
    required int inboundId,
    String group = '',
  }) async {
    final inbound = data?.inbounds.firstWhere(
      (ib) => ib.id == inboundId,
      orElse: () => data!.inbounds.first,
    );
    // Exact end date comes from the renewal math (calendar months).
    final plan = months <= 0 ? null : planRenewal(name, months);
    final expiry = plan?.expiryTimeMs ?? 0;
    if (showingDemo) {
      final client = ClientInfo(
        email: plan?.newEmail ?? name,
        inbound: inbound?.remark ?? 'VLESS Reality',
        enabled: true,
        upBytes: 0,
        downBytes: 0,
        quotaBytes: quotaGb <= 0 ? 0 : quotaGb * 1024 * 1024 * 1024,
        expiryTimeMs: expiry,
        group: group,
      );
      _simulate([...?data?.clients, client]);
      return (true, 'Added ${client.email} (simulated).');
    }
    try {
      final payload = buildCreatePayload(
        name: name,
        quotaGb: quotaGb,
        expiryTimeMs: expiry,
        inboundId: inboundId,
        limitIp: limitIp,
        group: group,
      );
      await _api.addClient(baseUrl: _baseUrl, token: _token, payload: payload);
      await refresh();
      return (true, 'Added ${payload['client']['email']}.');
    } on PanelApiException catch (e) {
      return (false, e.message);
    } on Exception catch (e) {
      return (false, 'Unexpected error: $e');
    }
  }

  /// Renew: new remark dates + new expiry, then reset traffic.
  Future<(bool, String)> renewClient(ClientInfo client, int months) async {
    final plan = planRenewal(client.email, months);
    if (showingDemo) {
      _simulate(_replaced(
        client,
        client.copyWith(
          email: plan.newEmail,
          expiryTimeMs: plan.expiryTimeMs,
          upBytes: 0,
          downBytes: 0,
          enabled: true,
        ),
      ));
      return (true, 'Renewed to ${plan.newEmail} (simulated).');
    }
    try {
      final record = await _api.fetchClientRecord(
        baseUrl: _baseUrl,
        token: _token,
        email: client.email,
      );
      await _api.updateClient(
        baseUrl: _baseUrl,
        token: _token,
        email: client.email,
        clientJson: record.toClientJson(
          email: plan.newEmail,
          expiryTimeMs: plan.expiryTimeMs,
        ),
      );
      try {
        await _api.resetClientTraffic(
          baseUrl: _baseUrl,
          token: _token,
          email: plan.newEmail,
        );
      } on PanelApiException catch (e) {
        await refresh();
        return (
          true,
          'Renewed to ${plan.newEmail}, but traffic reset failed: '
              '${e.message} — reset it from the client screen.',
        );
      }
      await refresh();
      return (true, 'Renewed to ${plan.newEmail}. Traffic reset.');
    } on PanelApiException catch (e) {
      return (false, e.message);
    } on Exception catch (e) {
      return (false, 'Unexpected error: $e');
    }
  }

  /// Quota x1.35 (the standing rule). Unlimited clients are refused.
  Future<(bool, String)> extendQuota(ClientInfo client) async {
    if (client.isUnlimited) {
      return (false, 'Unlimited quota — nothing to extend.');
    }
    final newGb = extendQuotaGb(client.quotaGb);
    if (showingDemo) {
      _simulate(_replaced(
        client,
        client.copyWith(quotaBytes: newGb * 1024 * 1024 * 1024),
      ));
      return (
        true,
        'Quota ${client.quotaGb.toStringAsFixed(1)} GB → $newGb GB '
            '(simulated).',
      );
    }
    try {
      final record = await _api.fetchClientRecord(
        baseUrl: _baseUrl,
        token: _token,
        email: client.email,
      );
      await _api.updateClient(
        baseUrl: _baseUrl,
        token: _token,
        email: client.email,
        clientJson: record.toClientJson(totalGb: newGb),
      );
      await refresh();
      return (
        true,
        'Quota ${client.quotaGb.toStringAsFixed(1)} GB → $newGb GB.',
      );
    } on PanelApiException catch (e) {
      return (false, e.message);
    } on Exception catch (e) {
      return (false, 'Unexpected error: $e');
    }
  }

  Future<(bool, String)> resetTraffic(ClientInfo client) async {
    if (showingDemo) {
      _simulate(_replaced(
        client,
        client.copyWith(upBytes: 0, downBytes: 0, enabled: true),
      ));
      return (true, 'Traffic reset for ${client.email} (simulated).');
    }
    try {
      await _api.resetClientTraffic(
        baseUrl: _baseUrl,
        token: _token,
        email: client.email,
      );
      await refresh();
      return (true, 'Traffic reset for ${client.email}.');
    } on PanelApiException catch (e) {
      return (false, e.message);
    } on Exception catch (e) {
      return (false, 'Unexpected error: $e');
    }
  }

  Future<(bool, String)> setClientEnabled(
    ClientInfo client,
    bool enable,
  ) async {
    if (showingDemo) {
      _simulate(_replaced(client, client.copyWith(enabled: enable)));
      return (
        true,
        '${client.email} ${enable ? 'enabled' : 'disabled'} (simulated).',
      );
    }
    try {
      final record = await _api.fetchClientRecord(
        baseUrl: _baseUrl,
        token: _token,
        email: client.email,
      );
      await _api.updateClient(
        baseUrl: _baseUrl,
        token: _token,
        email: client.email,
        clientJson: record.toClientJson(enable: enable),
      );
      await refresh();
      return (
        true,
        '${client.email} ${enable ? 'enabled' : 'disabled'}.',
      );
    } on PanelApiException catch (e) {
      return (false, e.message);
    } on Exception catch (e) {
      return (false, 'Unexpected error: $e');
    }
  }

  Future<(bool, String)> deleteClient(ClientInfo client) async {
    if (showingDemo) {
      final clients = List<ClientInfo>.from(data?.clients ?? [])
        ..removeWhere((c) => c.email == client.email);
      _simulate(clients);
      return (true, 'Deleted ${client.email} (simulated).');
    }
    try {
      await _api.deleteClient(
        baseUrl: _baseUrl,
        token: _token,
        email: client.email,
      );
      await refresh();
      return (true, 'Deleted ${client.email}.');
    } on PanelApiException catch (e) {
      return (false, e.message);
    } on Exception catch (e) {
      return (false, 'Unexpected error: $e');
    }
  }

  /// The VLESS inbound for new clients (first vless inbound, else the
  /// first inbound, else null when there is no data yet).
  InboundInfo? get vlessInbound {
    final inbounds = data?.inbounds ?? [];
    if (inbounds.isEmpty) return null;
    for (final ib in inbounds) {
      if (ib.protocol.toLowerCase() == 'vless') return ib;
    }
    return inbounds.first;
  }

  // ---- Fix names (v0.2.1, dateless remarks added in v0.2.2) ----
  //
  // One tap, no preview: each fixable remark is corrected from
  // existing data only (see planNameCorrection), subId and UUID are
  // untouched (updates go through the fetched record), and the
  // result lists what changed and what was skipped with reasons.
  // The plan uses the client's record timestamps (filled in by the
  // background enrichment); when they are not loaded yet, the
  // record is fetched once and the plan is re-derived from it
  // before the update, so a fix is never skipped just because the
  // enrichment had not finished.

  /// Fix one client's name. Returns the correction outcome.
  Future<NameCorrection> fixClientName(ClientInfo client) async {
    final outcome = await _applyNameFix(client);
    if (outcome is NameFixed && !showingDemo) await refresh();
    return outcome;
  }

  /// Fix all fixable names in one group (`null` = all groups,
  /// `''` = ungrouped only). Skipped clients cost no API call.
  /// Returns every outcome so the UI can show the summary.
  Future<List<NameCorrection>> fixNamesInGroup(String? group) async {
    final clients = List<ClientInfo>.from(data?.clients ?? []);
    final scoped = group == null
        ? clients
        : clients.where((c) => c.group == group).toList();
    final results = <NameCorrection>[];
    var anyFixed = false;
    for (final client in scoped) {
      final outcome = await _applyNameFix(client);
      if (outcome is NameFixed) anyFixed = true;
      results.add(outcome);
    }
    if (anyFixed && !showingDemo) await refresh();
    return results;
  }

  /// Plan a fix from the given record timestamps.
  NameCorrection _planFor(
    ClientInfo client,
    int updatedAtMs,
    int createdAtMs,
  ) =>
      planNameCorrection(
        client.email,
        client.expiryTimeMs,
        updatedAtMs: updatedAtMs,
        createdAtMs: createdAtMs,
        sharedUpdatedAtMs: _sharedUpdatedAtValues(),
      );

  /// Apply one planned fix (no refresh — the caller refreshes once).
  ///
  /// For a remark with no start of its own, the start date comes
  /// from the record timestamps — so when they are not loaded yet
  /// (enrichment still running), the record is fetched first and
  /// the plan is derived from it. Planning from the 1-month
  /// fallback without checking the record first could pick the
  /// wrong start (MaSandar's trusted Nov 15 vs the Jan 15
  /// fallback). Pair remarks need no record: their dates are in
  /// the remark itself.
  Future<NameCorrection> _applyNameFix(ClientInfo client) async {
    ClientRecord? record;
    var plan = _planFor(client, client.updatedAtMs, client.createdAtMs);
    final needsRecord = !showingDemo &&
        parseRemark(client.email).start == null &&
        client.updatedAtMs == 0 &&
        client.createdAtMs == 0;
    if (needsRecord) {
      try {
        record = await _api.fetchClientRecord(
          baseUrl: _baseUrl,
          token: _token,
          email: client.email,
        );
        plan = _planFor(client, record.updatedAtMs, record.createdAtMs);
      } on Exception {
        // Keep the first plan; the panel is unreachable.
      }
    }
    if (plan is! NameFixed) return plan;
    if (showingDemo) {
      _simulate(_replaced(
        client,
        client.copyWith(email: plan.correctedEmail),
      ));
      return plan;
    }
    try {
      record ??= await _api.fetchClientRecord(
        baseUrl: _baseUrl,
        token: _token,
        email: client.email,
      );
      await _api.updateClient(
        baseUrl: _baseUrl,
        token: _token,
        email: client.email,
        clientJson: record.toClientJson(email: plan.correctedEmail),
      );
      return plan;
    } on PanelApiException catch (e) {
      return NameSkipped(client.email, 'panel error: ${e.message}');
    } on Exception catch (e) {
      return NameSkipped(client.email, 'unexpected error: $e');
    }
  }
}
