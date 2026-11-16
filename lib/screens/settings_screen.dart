/// Settings: panel URL + API token (on-device only), demo-data toggle,
/// Google Sheets sync, and a connection test.
///
/// SECURITY: the URL and token are stored only in this browser's local
/// storage (SharedPreferences on web) / the app's private storage on
/// Android. They are sent only to the panel URL entered here, and never
/// baked into the app, its repo, or any build.
library;

import 'package:flutter/material.dart';

import '../services/panel_provider.dart';
import '../services/sheets_sync_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({required this.provider, super.key});

  final PanelProvider provider;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _urlController;
  late final TextEditingController _tokenController;
  late final TextEditingController _sheetsIdController;
  bool _obscureToken = true;
  bool _saving = false;
  bool _testing = false;
  String? _message;
  bool _messageIsError = false;

  final _sheets = SheetsSyncService();
  final _googleSignInService = GoogleSignInService();
  String? _googleAccessToken;
  bool _signingIn = false;
  bool _syncing = false;
  String? _sheetsMessage;
  bool _sheetsMessageIsError = false;
  String? _sheetsSetupSteps;

  @override
  void initState() {
    super.initState();
    _urlController =
        TextEditingController(text: widget.provider.settings.panelUrl);
    _tokenController =
        TextEditingController(text: widget.provider.settings.apiToken);
    _sheetsIdController = TextEditingController(
      text: widget.provider.settings.sheetsSpreadsheetId,
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    _sheetsIdController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _message = null;
    });
    final next = widget.provider.settings.copyWith(
      panelUrl: _urlController.text.trim(),
      apiToken: _tokenController.text.trim(),
      sheetsSpreadsheetId: _sheetsIdController.text.trim(),
    );
    await widget.provider.saveSettings(next);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _message = next.useDemoData
          ? 'Saved. Demo data is on, so the dashboard still shows samples.'
          : next.hasLiveCredentials
              ? 'Saved. Loading live data…'
              : 'Saved. Enter both a panel URL and a token for live data.';
      _messageIsError = false;
    });
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _message = null;
    });
    final (ok, msg) = await widget.provider.testConnection(
      _urlController.text.trim(),
      _tokenController.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _testing = false;
      _message = msg;
      _messageIsError = !ok;
    });
  }

  Future<void> _clear() async {
    await widget.provider.clearCredentials();
    if (!mounted) return;
    setState(() {
      _urlController.clear();
      _tokenController.clear();
      _message = 'Panel URL and token cleared from this device.';
      _messageIsError = false;
    });
  }

  Future<void> _googleSignIn() async {
    setState(() {
      _signingIn = true;
      _sheetsMessage = null;
      _sheetsSetupSteps = null;
    });
    try {
      final token = await _googleSignInService.signInAndGetAccessToken();
      if (!mounted) return;
      setState(() {
        _signingIn = false;
        _googleAccessToken = token;
        _sheetsMessage = 'Signed in to Google. Ready to sync.';
        _sheetsMessageIsError = false;
      });
    } on SheetsSetupNeeded catch (e) {
      if (!mounted) return;
      setState(() {
        _signingIn = false;
        _sheetsMessage = 'Google sign-in is not set up yet.';
        _sheetsMessageIsError = true;
        _sheetsSetupSteps = e.steps;
      });
    }
  }

  Future<void> _syncSheets() async {
    final clients = widget.provider.data?.clients ?? [];
    if (clients.isEmpty) {
      setState(() {
        _sheetsMessage = 'No clients to sync — load the dashboard first.';
        _sheetsMessageIsError = true;
      });
      return;
    }
    var token = _googleAccessToken;
    if (token == null) {
      await _googleSignIn();
      token = _googleAccessToken;
      if (token == null || !mounted) return;
    }
    setState(() {
      _syncing = true;
      _sheetsMessage = null;
    });
    final (ok, msg) = await _sheets.sync(
      accessToken: token,
      spreadsheetId: _sheetsIdController.text.trim(),
      clients: clients,
    );
    if (!mounted) return;
    setState(() {
      _syncing = false;
      _sheetsMessage = msg;
      _sheetsMessageIsError = !ok;
      if (!ok && msg.contains('401')) _googleAccessToken = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.provider,
      builder: (context, _) {
        final settings = widget.provider.settings;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Panel connection',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _urlController,
                      decoration: const InputDecoration(
                        labelText: 'Panel URL',
                        hintText: 'https://your-panel-url/',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _tokenController,
                      decoration: InputDecoration(
                        labelText: 'API token',
                        hintText: 'Panel Settings → Security → API Token',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureToken
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () => setState(
                            () => _obscureToken = !_obscureToken,
                          ),
                        ),
                      ),
                      obscureText: _obscureToken,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Stored only on this device (browser local storage '
                      'on web). Sent only to the panel URL above. Never '
                      'included in the app or its repository.',
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: _saving ? null : _save,
                            child: _saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Save'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _testing ? null : _test,
                            child: _testing
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Test connection'),
                          ),
                        ),
                      ],
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _message!,
                        style: TextStyle(
                          color: _messageIsError
                              ? Colors.redAccent
                              : Colors.tealAccent,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: SwitchListTile(
                title: const Text('Use demo data'),
                subtitle: const Text(
                  'On: clearly-labelled sample clients. Off: live data '
                  'from the panel (needs a URL + token above).',
                ),
                value: settings.useDemoData,
                onChanged: (v) async {
                  await widget.provider.setDemoMode(v);
                  if (!mounted) return;
                  setState(() {
                    _message = v
                        ? 'Demo data on.'
                        : 'Demo data off — loading live data…';
                    _messageIsError = false;
                  });
                },
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Google Sheets sync',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Writes the client table (panel data) into the '
                      '`vlesslist` tab of your spreadsheet — dates as '
                      'ISO yyyy-MM-dd, so Sheets can never misread them.',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _sheetsIdController,
                      decoration: const InputDecoration(
                        labelText: 'Spreadsheet ID',
                        hintText: 'Paste the sheet URL or just its ID',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed:
                                _signingIn ? null : _googleSignIn,
                            child: _signingIn
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    _googleAccessToken == null
                                        ? 'Sign in with Google'
                                        : 'Signed in ✓ — tap to re-sign in',
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: _syncing ? null : _syncSheets,
                            child: _syncing
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Sync now'),
                          ),
                        ),
                      ],
                    ),
                    if (_sheetsMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _sheetsMessage!,
                        style: TextStyle(
                          color: _sheetsMessageIsError
                              ? Colors.redAccent
                              : Colors.tealAccent,
                        ),
                      ),
                    ],
                    if (_sheetsSetupSteps != null) ...[
                      const SizedBox(height: 12),
                      SelectableText(_sheetsSetupSteps!),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Danger zone',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _clear,
                      child: const Text('Clear saved panel credentials'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Center(
              child: Text(
                'MistyRoute Manager v0.2.0 — write actions, SSH setup, '
                'Sheets sync.\n'
                'Live data needs the Android app (web cannot reach the '
                'panel: no CORS headers).',
                textAlign: TextAlign.center,
              ),
            ),
          ],
        );
      },
    );
  }
}
