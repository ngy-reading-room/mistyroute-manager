// Unit tests for the group feature: group counts, demo-data groups,
// and the group flowing into the create payload.
import 'package:flutter_test/flutter_test.dart';
import 'package:mistyroutemanager/models/panel_models.dart';
import 'package:mistyroutemanager/services/client_actions.dart';
import 'package:mistyroutemanager/services/demo_data.dart';

ClientInfo _c(String email, String group) => ClientInfo(
      email: email,
      inbound: 'VLESS Reality',
      enabled: true,
      upBytes: 0,
      downBytes: 0,
      quotaBytes: 50 * 1024 * 1024 * 1024,
      expiryTimeMs: 0,
      group: group,
    );

void main() {
  group('PanelData.groupCounts', () {
    test('only groups actually present, sorted, with counts', () {
      final data = PanelData(
        inbounds: const [],
        clients: [
          _c('A', 'MNA'),
          _c('B', 'MayZin'),
          _c('C', 'MNA'),
          _c('D', ''),
          _c('E', 'Friends'),
        ],
      );
      expect(data.groupCounts, {'Friends': 1, 'MNA': 2, 'MayZin': 1});
      expect(data.ungroupedCount, 1);
    });

    test('no groups at all yields empty counts', () {
      final data = PanelData(
        inbounds: const [],
        clients: [_c('A', ''), _c('B', '')],
      );
      expect(data.groupCounts, isEmpty);
      expect(data.ungroupedCount, 2);
    });
  });

  group('demo data groups', () {
    test('demo clients carry MNA / MayZin / Friends / FOC + one ungrouped',
        () {
      final data = buildDemoData();
      expect(data.groupCounts, {
        'FOC': 1,
        'Friends': 4,
        'MNA': 8,
        'MayZin': 10,
      });
      expect(data.ungroupedCount, 1);
      expect(data.clients.length, 24);
    });
  });

  group('buildCreatePayload group', () {
    test('chosen group is sent in the client payload', () {
      final payload = buildCreatePayload(
        name: 'NewUser',
        quotaGb: 50,
        expiryTimeMs: DateTime(2027, 2, 17).millisecondsSinceEpoch,
        inboundId: 1,
        group: 'MNA',
        today: DateTime(2026, 11, 16),
      );
      final client = payload['client'] as Map<String, dynamic>;
      expect(client['group'], 'MNA');
      expect(client['email'], 'NewUser_16.11.26-16.2.27');
    });

    test('no group defaults to an empty group', () {
      final payload = buildCreatePayload(
        name: 'NewUser',
        quotaGb: 50,
        expiryTimeMs: 0,
        inboundId: 1,
        today: DateTime(2026, 11, 16),
      );
      final client = payload['client'] as Map<String, dynamic>;
      expect(client['group'], '');
      expect(client['email'], 'NewUser');
    });
  });
}
