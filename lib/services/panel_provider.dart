/// Holds the dashboard state: settings, loaded panel data, and whether
/// what is shown is live data from the panel or labelled demo data.
library;

import 'package:flutter/foundation.dart';

import '../models/panel_models.dart';
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
}
