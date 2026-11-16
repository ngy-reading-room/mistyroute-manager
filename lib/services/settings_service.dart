/// Panel connection settings, persisted on-device only.
///
/// On web this lands in the browser's local storage (via
/// shared_preferences); on Android it stays in the app's private storage.
/// The panel URL and API token are NEVER baked into the app — the user
/// types them in Settings, and they are sent only to the panel URL entered.
library;

import 'package:shared_preferences/shared_preferences.dart';

class PanelSettings {
  const PanelSettings({
    this.panelUrl = '',
    this.apiToken = '',
    this.useDemoData = true,
  });

  final String panelUrl;
  final String apiToken;

  /// Default true: the demo opens with clearly-labelled sample data, and
  /// live mode only starts once a URL + token are saved and the toggle
  /// is switched off.
  final bool useDemoData;

  bool get hasLiveCredentials =>
      panelUrl.trim().isNotEmpty && apiToken.trim().isNotEmpty;

  PanelSettings copyWith({
    String? panelUrl,
    String? apiToken,
    bool? useDemoData,
  }) =>
      PanelSettings(
        panelUrl: panelUrl ?? this.panelUrl,
        apiToken: apiToken ?? this.apiToken,
        useDemoData: useDemoData ?? this.useDemoData,
      );
}

class SettingsService {
  static const _kPanelUrl = 'mistyroute_panel_url';
  static const _kApiToken = 'mistyroute_api_token';
  static const _kUseDemo = 'mistyroute_use_demo_data';

  Future<PanelSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return PanelSettings(
      panelUrl: prefs.getString(_kPanelUrl) ?? '',
      apiToken: prefs.getString(_kApiToken) ?? '',
      useDemoData: prefs.getBool(_kUseDemo) ?? true,
    );
  }

  Future<void> save(PanelSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPanelUrl, settings.panelUrl);
    await prefs.setString(_kApiToken, settings.apiToken);
    await prefs.setBool(_kUseDemo, settings.useDemoData);
  }

  Future<void> clearCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPanelUrl);
    await prefs.remove(_kApiToken);
  }
}
