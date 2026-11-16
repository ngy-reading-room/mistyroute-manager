/// Add a new client.
///
/// Follows the panel conventions: remark/email =
/// `{Name}_{start D.M.YY}-{end D.M.YY}`, subId = the stable name,
/// VLESS flow `xtls-rprx-vision`, panel generates the UUID.
/// Quota is whole GB (the panel's totalGB is int64); 0 = unlimited.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/panel_provider.dart';

class AddClientScreen extends StatefulWidget {
  const AddClientScreen({required this.provider, super.key});

  final PanelProvider provider;

  @override
  State<AddClientScreen> createState() => _AddClientScreenState();
}

class _AddClientScreenState extends State<AddClientScreen> {
  final _nameController = TextEditingController();
  final _quotaController = TextEditingController(text: '50');
  final _limitIpController = TextEditingController(text: '1');
  int _months = 3;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _quotaController.dispose();
    _limitIpController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final quota = int.tryParse(_quotaController.text.trim());
    final limitIp = int.tryParse(_limitIpController.text.trim());
    final inbound = widget.provider.vlessInbound;
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name (e.g. KoYeMin).');
      return;
    }
    if (quota == null || quota < 0) {
      setState(() => _error = 'Quota must be a whole number of GB (0 = unlimited).');
      return;
    }
    if (limitIp == null || limitIp < 0) {
      setState(() => _error = 'IP limit must be a whole number (0 = no limit).');
      return;
    }
    if (inbound == null) {
      setState(() => _error = 'No inbound found — load the dashboard first.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final (ok, msg) = await widget.provider.addClient(
      name: name,
      quotaGb: quota,
      months: _months,
      limitIp: limitIp,
      inboundId: inbound.id,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
    if (ok) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final inbound = widget.provider.vlessInbound;
    return Scaffold(
      appBar: AppBar(title: const Text('Add client')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'KoYeMin',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _quotaController,
            decoration: const InputDecoration(
              labelText: 'Quota (GB)',
              hintText: '50 — 0 means unlimited',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _months,
            decoration: const InputDecoration(
              labelText: 'Valid for',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 0, child: Text('No expiry')),
              DropdownMenuItem(value: 1, child: Text('1 month')),
              DropdownMenuItem(value: 2, child: Text('2 months')),
              DropdownMenuItem(value: 3, child: Text('3 months')),
              DropdownMenuItem(value: 6, child: Text('6 months')),
              DropdownMenuItem(value: 12, child: Text('12 months')),
            ],
            onChanged: (v) => setState(() => _months = v ?? 3),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _limitIpController,
            decoration: const InputDecoration(
              labelText: 'IP limit',
              hintText: '1 — 0 means no limit',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          const SizedBox(height: 12),
          Text(
            'Inbound: ${inbound == null ? '—' : '${inbound.remark} (${inbound.protocol})'}\n'
            'Remark becomes Name_start–end dates; the subscription ID '
            'is the name, so the link never changes.',
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Add client'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          ],
        ],
      ),
    );
  }
}
