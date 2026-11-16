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
    this.sheetsSpreadsheetId = '',
    this.doApiToken = '',
  });

  final String panelUrl;
  final String apiToken;

  /// Default true: the demo opens with clearly-labelled sample data, and
  /// live mode only starts once a URL + token are saved and the toggle
  /// is switched off.
  final bool useDemoData;

  /// Google Sheets spreadsheet ID (or full sheet URL) for the
  /// panel -> `vlesslist` sync. Empty = not configured.
  final String sheetsSpreadsheetId;

  /// DigitalOcean API token, OPTIONAL and secondary only: the
  /// Billing estimate works without it (panel/VPS data). When set,
  /// the app can also show the DO account balance. Stored on-device
  /// only, never in code.
  final String doApiToken;

  bool get hasLiveCredentials =>
      panelUrl.trim().isNotEmpty && apiToken.trim().isNotEmpty;

  PanelSettings copyWith({
    String? panelUrl,
    String? apiToken,
    bool? useDemoData,
    String? sheetsSpreadsheetId,
    String? doApiToken,
  }) =>
      PanelSettings(
        panelUrl: panelUrl ?? this.panelUrl,
        apiToken: apiToken ?? this.apiToken,
        useDemoData: useDemoData ?? this.useDemoData,
        sheetsSpreadsheetId: sheetsSpreadsheetId ?? this.sheetsSpreadsheetId,
        doApiToken: doApiToken ?? this.doApiToken,
      );
}

class SettingsService {
  static const _kPanelUrl = 'mistyroute_panel_url';
  static const _kApiToken = 'mistyroute_api_token';
  static const _kUseDemo = 'mistyroute_use_demo_data';
  static const _kSheetsId = 'mistyroute_sheets_spreadsheet_id';
  static const _kDoApiToken = 'mistyroute_do_api_token';

  Future<PanelSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return PanelSettings(
      panelUrl: prefs.getString(_kPanelUrl) ?? '',
      apiToken: prefs.getString(_kApiToken) ?? '',
      useDemoData: prefs.getBool(_kUseDemo) ?? true,
      sheetsSpreadsheetId: prefs.getString(_kSheetsId) ?? '',
      doApiToken: prefs.getString(_kDoApiToken) ?? '',
    );
  }

  Future<void> save(PanelSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPanelUrl, settings.panelUrl);
    await prefs.setString(_kApiToken, settings.apiToken);
    await prefs.setBool(_kUseDemo, settings.useDemoData);
    await prefs.setString(_kSheetsId, settings.sheetsSpreadsheetId);
    await prefs.setString(_kDoApiToken, settings.doApiToken);
  }

  Future<void> clearCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPanelUrl);
    await prefs.remove(_kApiToken);
  }
}
