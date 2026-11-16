/// First-run Setup: the SSH one-tap actions for the tunnel.
///
/// Mobile only — browsers cannot open raw TCP sockets, so on web this
/// screen explains that and points at the Android app instead.
///
/// On mobile it shows the app's own SSH public key + fingerprint
/// (generated on first use, private key in secure storage), the exact
/// authorized_keys line to install on the VPS, and four one-tap
/// buttons: SSH Connect, Check Tunnel Link, Tunnel Restart,
/// Tunnel Status. Order matters: restart first, then Check Tunnel
/// Link (the tunnel hostname changes on restart).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/panel_provider.dart';
import '../services/ssh_service.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({required this.provider, super.key});

  final PanelProvider provider;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _ssh = SshService();
  SshKeyInfo? _keyInfo;
  String? _keyError;
  bool _loadingKey = true;

  SshAction? _running;
  String? _result;
  bool _resultIsError = false;
  String? _foundPanelUrl;

  @override
  void initState() {
    super.initState();
    _loadKey();
  }

  Future<void> _loadKey() async {
    if (!_ssh.isSupported) {
      setState(() => _loadingKey = false);
      return;
    }
    try {
      final info = await _ssh.keyInfo();
      if (!mounted) return;
      setState(() {
        _keyInfo = info;
        _loadingKey = false;
      });
    } on Exception catch (e) {
      // Includes the "not available on this platform" case and any
      // secure-storage failure: show it instead of crashing.
      if (!mounted) return;
      setState(() {
        _keyError = e.toString();
        _loadingKey = false;
      });
    }
  }

  Future<void> _run(SshAction action) async {
    setState(() {
      _running = action;
      _result = null;
      _foundPanelUrl = null;
    });
    try {
      final out = await _ssh.runAction(action);
      if (!mounted) return;
      setState(() {
        _running = null;
        _result = out;
        _resultIsError = false;
        if (action == SshAction.tunnelUrl) _foundPanelUrl = out.trim();
      });
    } on SshException catch (e) {
      if (!mounted) return;
      setState(() {
        _running = null;
        _result = e.message;
        _resultIsError = true;
      });
    }
  }

  Future<void> _savePanelUrl() async {
    final url = _foundPanelUrl;
    if (url == null) return;
    await widget.provider.saveSettings(
      widget.provider.settings.copyWith(panelUrl: url),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Panel URL saved to Settings.')),
    );
    setState(() => _foundPanelUrl = null);
  }

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_ssh.isSupported) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'SSH setup is not available on web.\n\n'
                'Browsers cannot open raw TCP sockets, so the tunnel '
                'actions (SSH Connect, Check Tunnel Link, Tunnel '
                'Restart, Tunnel Status) only work in the Android app. '
                'Install the v0.2 APK on the phone and open this Setup '
                'tab there.',
              ),
            ),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _KeyCard(
          keyInfo: _keyInfo,
          keyError: _keyError,
          loading: _loadingKey,
          onCopyLine: (line) => _copy(line, 'Public key line'),
          onCopyAuthorizedKeys: (line) =>
              _copy(line, 'authorized_keys line'),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tunnel actions',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'One tap each — no typing. If the tunnel was '
                  'restarted, the hostname may change: tap Tunnel '
                  'Restart first, then Check Tunnel Link.',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final action in SshAction.values)
                      FilledButton.tonalIcon(
                        onPressed: _running != null
                            ? null
                            : () => _run(action),
                        icon: _running == action
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(_iconFor(action)),
                        label: Text(sshActionLabel(action)),
                      ),
                  ],
                ),
                if (_result != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (_resultIsError ? Colors.red : Colors.teal)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(_result!),
                  ),
                ],
                if (_foundPanelUrl != null) ...[
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _savePanelUrl,
                    child: const Text('Save this as the panel URL'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Current saved URL: '
                    '${widget.provider.settings.panelUrl.isEmpty ? '(none yet)' : widget.provider.settings.panelUrl}',
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'How the VPS side works\n\n'
              'The key above can only run three commands on the VPS '
              '(url / restart / status) through the mistyroute-ctl '
              'dispatch script — no shell access. Install it once on '
              'the VPS (see scripts/mistyroute-ctl in the project), '
              'then the buttons above just work.\n\n'
              'If the app is reinstalled, it generates a new keypair '
              'and the authorized_keys line on the VPS must be replaced.',
            ),
          ),
        ),
      ],
    );
  }

  IconData _iconFor(SshAction action) => switch (action) {
        SshAction.connect => Icons.terminal,
        SshAction.tunnelUrl => Icons.link,
        SshAction.tunnelRestart => Icons.restart_alt,
        SshAction.tunnelStatus => Icons.monitor_heart,
      };
}

class _KeyCard extends StatelessWidget {
  const _KeyCard({
    required this.keyInfo,
    required this.keyError,
    required this.loading,
    required this.onCopyLine,
    required this.onCopyAuthorizedKeys,
  });

  final SshKeyInfo? keyInfo;
  final String? keyError;
  final bool loading;
  final ValueChanged<String> onCopyLine;
  final ValueChanged<String> onCopyAuthorizedKeys;

  @override
  Widget build(BuildContext context) {
    final info = keyInfo;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'App SSH key',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (loading)
              const Center(child: CircularProgressIndicator())
            else if (keyError != null)
              Text(keyError!, style: const TextStyle(color: Colors.redAccent))
            else if (info != null) ...[
              Text(
                'Private key: stored only on this phone (secure '
                'storage), never leaves the device.',
              ),
              const SizedBox(height: 8),
              Text('Fingerprint: ${info.fingerprint}'),
              const SizedBox(height: 8),
              const Text('Public key (install this on the VPS):'),
              const SizedBox(height: 4),
              SelectableText(
                info.publicKeyLine,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => onCopyLine(info.publicKeyLine),
                    child: const Text('Copy public key'),
                  ),
                  OutlinedButton(
                    onPressed: () => onCopyAuthorizedKeys(
                      'command="/root/mistyroute-ctl",no-port-forwarding,'
                      'no-X11-forwarding,no-agent-forwarding,no-pty '
                      '${info.publicKeyLine}',
                    ),
                    child: const Text('Copy authorized_keys line'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'On the VPS (once, as root): copy scripts/mistyroute-ctl '
                'to /root/mistyroute-ctl, then append the '
                'authorized_keys line above to '
                '/root/.ssh/authorized_keys.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}
