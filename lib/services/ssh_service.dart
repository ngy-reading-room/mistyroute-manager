/// SSH to the VPS (mobile only) for the tunnel one-tap actions.
///
/// The app generates its OWN Ed25519 keypair on first use (pinenacl),
/// stores the private key PEM in secure storage (flutter_secure_storage
/// — Android Keystore / encrypted storage), and shows the public key +
/// SHA256 fingerprint so the user can install it on the VPS with the
/// forced-command dispatch script (see scripts/mistyroute-ctl).
///
/// The VPS side allows ONLY three commands through that forced command:
/// `url`, `restart`, `status`. The app therefore sends exactly those
/// words as the remote command — no shell, no arguments, nothing else.
///
/// Browsers cannot open raw TCP sockets, so every SSH feature is
/// mobile-only: on web the Setup screen says so instead of offering
/// dead buttons. `SSHSocket.connect` is `dart:io`-only.
///
/// Host keys: trust-on-first-use. The VPS host fingerprint is stored
/// in secure storage on the first connection and verified on every
/// later one; a changed host key aborts with an error.
///
/// Verified against dartssh2 4.1.0 (resolved from pub):
/// - `SSHClient(socket, username:, identities:, onVerifyHostKey:)`,
///   `await client.authenticated`, `client.runWithResult(cmd)` ->
///   `SSHRunResult {stdout, stderr, exitCode}`.
/// - dartssh2 has NO key generation: the pair is built with pinenacl's
///   `SigningKey.generate()` and wrapped in
///   `OpenSSHEd25519KeyPair(public32, secret64, comment)`.
/// - Public line: `ssh-ed25519 <base64(hostKey.encode())> <comment>`;
///   fingerprint: `SHA256:` + base64(sha256(hostKey.encode())) with
///   the `=` padding stripped (the OpenSSH format).
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pinenacl/ed25519.dart' as ed25519;

class SshException implements Exception {
  SshException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The VPS the app SSHes to. No secrets here — only the public
/// host/user and the panel sub-path (which is also in the sub URL).
class SshTarget {
  static const host = '168.144.250.99';
  static const port = 22;
  static const username = 'root';

  /// The panel lives under this sub-path on the tunnel host.
  static const subPath = '/MjfgiJflHcfijX4TYv/';
}

enum SshAction { connect, tunnelUrl, tunnelRestart, tunnelStatus }

/// The exact remote command sent for each action. With the forced
/// command in authorized_keys the VPS dispatch script reads these
/// words from $SSH_ORIGINAL_COMMAND and runs only its allow-listed
/// handler — nothing else can execute.
String sshRemoteCommand(SshAction action) => switch (action) {
      SshAction.connect => '',
      SshAction.tunnelUrl => 'url',
      SshAction.tunnelRestart => 'restart',
      SshAction.tunnelStatus => 'status',
    };

String sshActionLabel(SshAction action) => switch (action) {
      SshAction.connect => 'SSH Connect',
      SshAction.tunnelUrl => 'Check Tunnel Link',
      SshAction.tunnelRestart => 'Tunnel Restart',
      SshAction.tunnelStatus => 'Tunnel Status',
    };

/// What the app's keypair looks like on screen.
class SshKeyInfo {
  const SshKeyInfo({
    required this.publicKeyLine,
    required this.fingerprint,
    required this.hasStoredKey,
  });

  /// `ssh-ed25519 AAAA... mistyroute-manager` — the line for
  /// authorized_keys (shown with the forced-command prefix in Setup).
  final String publicKeyLine;

  /// `SHA256:....` — compare with the VPS after install.
  final String fingerprint;

  /// True once a keypair exists in secure storage.
  final bool hasStoredKey;
}

class SshService {
  SshService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _kPrivateKeyPem = 'mistyroute_ssh_private_key_pem';
  static const _kHostFingerprint = 'mistyroute_ssh_host_fingerprint';
  static const _kComment = 'mistyroute-manager';

  final FlutterSecureStorage _storage;

  bool get isSupported => !kIsWeb;

  /// The OpenSSH public-key line for a keypair.
  static String publicLineFor(SSHKeyPair pair) {
    final blob = pair.toPublicKey().encode();
    return '${pair.name} ${base64Encode(blob)} $_kComment';
  }

  /// The OpenSSH SHA256 fingerprint for a keypair.
  static String fingerprintFor(SSHKeyPair pair) {
    final blob = pair.toPublicKey().encode();
    final digest = sha256.convert(blob).bytes;
    final b64 = base64Encode(digest).replaceAll('=', '');
    return 'SHA256:$b64';
  }

  /// Build an Ed25519 pair from a fresh random seed.
  /// pinenacl's SigningKey secret is seed(32) || public(32) = 64 bytes,
  /// which is exactly the OpenSSH private-key layout.
  static SSHKeyPair generateKeypair() {
    final signing = ed25519.SigningKey.generate();
    final secret = signing.asTypedList;
    final public = Uint8List.fromList(secret.sublist(32));
    return OpenSSHEd25519KeyPair(public, secret, _kComment);
  }

  Future<SSHKeyPair> _loadOrCreateKeypair() async {
    final pem = await _storage.read(key: _kPrivateKeyPem);
    if (pem != null && pem.isNotEmpty) {
      final pairs = SSHKeyPair.fromPem(pem);
      if (pairs.isNotEmpty) return pairs.first;
    }
    final pair = generateKeypair();
    await _storage.write(key: _kPrivateKeyPem, value: pair.toPem());
    return pair;
  }

  /// The keypair info for the Setup screen. Generates the pair on
  /// first call (mobile only).
  Future<SshKeyInfo> keyInfo() async {
    if (!isSupported) {
      throw SshException(
        'SSH is not available on web — browsers cannot open raw TCP '
        'sockets. Use the Android app.',
      );
    }
    final hadStored = await _storage.read(key: _kPrivateKeyPem) != null;
    final pair = await _loadOrCreateKeypair();
    return SshKeyInfo(
      publicKeyLine: publicLineFor(pair),
      fingerprint: fingerprintFor(pair),
      hasStoredKey: hadStored,
    );
  }

  /// Run one action. Returns the command's stdout (trimmed).
  /// `connect` only authenticates and returns a confirmation line.
  Future<String> runAction(SshAction action) async {
    if (!isSupported) {
      throw SshException(
        'SSH is not available on web — browsers cannot open raw TCP '
        'sockets. Use the Android app.',
      );
    }
    final pair = await _loadOrCreateKeypair();
    final socket = await SSHSocket.connect(
      SshTarget.host,
      SshTarget.port,
    ).timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw SshException(
        'Timed out connecting to ${SshTarget.host}:22. '
        'Is the VPS reachable from this network?',
      ),
    );
    final client = SSHClient(
      socket,
      username: SshTarget.username,
      identities: [pair],
      onVerifyHostKey: (type, fingerprint) async {
        final seen = utf8.decode(fingerprint);
        final stored = await _storage.read(key: _kHostFingerprint);
        if (stored == null) {
          await _storage.write(key: _kHostFingerprint, value: seen);
          return true;
        }
        return stored == seen;
      },
    );
    try {
      await client.authenticated.timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw SshException(
          'SSH authentication timed out. Is this app key installed '
          'on the VPS (authorized_keys + mistyroute-ctl)?',
        ),
      );
      if (action == SshAction.connect) {
        return 'Connected to ${SshTarget.username}@${SshTarget.host} '
            'as ${pair.name} key ${fingerprintFor(pair)}.';
      }
      final result = await client
          .runWithResult(sshRemoteCommand(action))
          .timeout(const Duration(seconds: 30));
      final out = utf8.decode(result.stdout).trim();
      final err = utf8.decode(result.stderr).trim();
      if (result.exitCode != 0) {
        throw SshException(
          '${sshActionLabel(action)} failed (exit ${result.exitCode}): '
          '${err.isNotEmpty ? err : out}',
        );
      }
      if (action == SshAction.tunnelUrl) {
        final url = _extractPanelUrl(out);
        if (url == null) {
          throw SshException(
            'Tunnel link not found in the VPS log. Output was: $out',
          );
        }
        return url;
      }
      return out.isEmpty ? '(no output)' : out;
    } on SshException {
      rethrow;
    } on Exception catch (e) {
      throw SshException('${sshActionLabel(action)} failed: $e');
    } finally {
      client.close();
    }
  }

  /// The dispatch script prints the full panel URL; pull the
  /// https://...trycloudflare.com/MjfgiJflHcfijX4TYv/ line out of it.
  static String? _extractPanelUrl(String output) {
    for (final line in output.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('https://') &&
          trimmed.contains('trycloudflare.com') &&
          trimmed.contains(SshTarget.subPath)) {
        return trimmed;
      }
    }
    return null;
  }
}
