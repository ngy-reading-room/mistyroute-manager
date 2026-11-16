// Unit tests for the SSH command building and keypair generation.
// No server involved: key generation is pure Dart (pinenacl) and the
// PEM round-trip proves the generated pair is a valid OpenSSH key.
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mistyroutemanager/services/ssh_service.dart';

void main() {
  group('sshRemoteCommand', () {
    test('only the three allow-listed words are ever sent', () {
      expect(sshRemoteCommand(SshAction.tunnelUrl), 'url');
      expect(sshRemoteCommand(SshAction.tunnelRestart), 'restart');
      expect(sshRemoteCommand(SshAction.tunnelStatus), 'status');
      expect(sshRemoteCommand(SshAction.connect), '');
    });
  });

  group('generateKeypair', () {
    test('public line is a valid ssh-ed25519 authorized_keys entry', () {
      final pair = SshService.generateKeypair();
      final line = SshService.publicLineFor(pair);
      expect(line, startsWith('ssh-ed25519 '));
      expect(line, endsWith(' mistyroute-manager'));
      final parts = line.split(' ');
      expect(parts.length, 3);
      expect(parts[1].length, greaterThan(40));
    });

    test('fingerprint is OpenSSH SHA256 format without padding', () {
      final pair = SshService.generateKeypair();
      final fp = SshService.fingerprintFor(pair);
      expect(fp, startsWith('SHA256:'));
      expect(fp.contains('='), false);
      expect(fp.length, 50); // "SHA256:" + 43 base64 chars
    });

    test('same pair -> same fingerprint; new pair -> new fingerprint', () {
      final a = SshService.generateKeypair();
      final b = SshService.generateKeypair();
      expect(SshService.fingerprintFor(a), SshService.fingerprintFor(a));
      expect(
        SshService.fingerprintFor(a),
        isNot(SshService.fingerprintFor(b)),
      );
    });

    test('PEM round-trip preserves the public key', () {
      final pair = SshService.generateKeypair();
      final pem = pair.toPem();
      expect(pem, contains('-----BEGIN OPENSSH PRIVATE KEY-----'));
      final restored = SSHKeyPair.fromPem(pem).first;
      expect(
        SshService.publicLineFor(restored),
        SshService.publicLineFor(pair),
      );
    });
  });
}
