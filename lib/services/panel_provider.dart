/// Holds the dashboard state: settings, loaded panel data, and whether
/// what is shown is live data from the panel or labelled demo data.
library;

import 'package:flutter/foundation.dart';

import '../models/panel_models.dart';
import 'client_actions.dart';
import 'demo_data.dart';
import 'panel_api.dart';
import 'settings_service.dart';

enum DataMode { demo, live }

class PanelProvider extends ChangeNotifier {
  PanelProvider({PanelApiService? api, SettingsService? settings})
      : _api = api ?? PanelApiService(),
        _settingsService = settings ?? SettingsService();

  final PanelApiService _api;
  final SettingsService _settingsService;

  PanelSettings settings = const PanelSettings();
  PanelData? data;
  DataMode mode = DataMode.demo;
  bool isLoading = false;
  String? error;
  DateTime? lastUpdated;

  Future<void> init() async {
    settings = await _settingsService.load();
    await refresh();
  }

  bool get showingDemo => mode == DataMode.demo;

  /// Loads demo data or fetches live data, depending on settings.
  Future<void> refresh() async {
    if (settings.useDemoData || !settings.hasLiveCredentials) {
      mode = DataMode.demo;
      error = null;
      isLoading = false;
      data = buildDemoData();
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
      mode = DataMode.live;
      lastUpdated = DateTime.now();
    } on PanelApiException catch (e) {
      error = e.message;
      data = null;
    } on Exception catch (e) {
      error = 'Unexpected error: $e';
      data = null;
    } finally {
      isLoading = false;
      notifyListeners();
    }
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
}
