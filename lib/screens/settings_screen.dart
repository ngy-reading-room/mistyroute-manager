/// Settings: panel URL + API token (on-device only), demo-data toggle,
/// and a connection test.
///
/// SECURITY: the URL and token are stored only in this browser's local
/// storage (SharedPreferences on web) / the app's private storage on
/// Android. They are sent only to the panel URL entered here, and never
/// baked into the app, its repo, or any build.
library;

import 'package:flutter/material.dart';

import '../services/panel_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({required this.provider, super.key});

  final PanelProvider provider;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _urlController;
  late final TextEditingController _tokenController;
  bool _obscureToken = true;
  bool _saving = false;
  bool _testing = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    _urlController =
        TextEditingController(text: widget.provider.settings.panelUrl);
    _tokenController =
        TextEditingController(text: widget.provider.settings.apiToken);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
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
                'MistyRoute Manager v0.1.0 — read-only demo.\n'
                'Write actions, Sheets sync and the APK arrive later.',
                textAlign: TextAlign.center,
              ),
            ),
          ],
        );
      },
    );
  }
}
