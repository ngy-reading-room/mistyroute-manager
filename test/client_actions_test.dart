// Unit tests for the pure client-action logic: remark dates, renewal
// math, quota x1.35 and the add-client payload.
import 'package:flutter_test/flutter_test.dart';
import 'package:mistyroutemanager/services/client_actions.dart';

void main() {
  group('parseRemark', () {
    test('splits name and D.M.YY dates', () {
      final p = parseRemark('MaSandar-1_15.11.26-15.2.27');
      expect(p.name, 'MaSandar-1');
      expect(p.start, DateTime(2026, 11, 15));
      expect(p.end, DateTime(2027, 2, 15));
    });

    test('name without dates yields just the name', () {
      final p = parseRemark('KoYeMin');
      expect(p.name, 'KoYeMin');
      expect(p.start, isNull);
      expect(p.end, isNull);
    });

    test('unparseable dates yield just the name', () {
      final p = parseRemark('Foo_xx-yy');
      expect(p.name, 'Foo');
      expect(p.start, isNull);
    });
  });

  group('formatDmYy / buildRemark', () {
    test('no zero-padding, two-digit year', () {
      expect(formatDmYy(DateTime(2027, 2, 5)), '5.2.27');
      expect(buildRemark('MeMe', DateTime(2026, 11, 16), DateTime(2027, 2, 16)),
          'MeMe_16.11.26-16.2.27');
    });
  });

  group('addMonths', () {
    test('clamps month-end days instead of overflowing', () {
      expect(addMonths(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
      expect(addMonths(DateTime(2026, 11, 16), 3), DateTime(2027, 2, 16));
      expect(addMonths(DateTime(2026, 12, 15), 2), DateTime(2027, 2, 15));
    });
  });

  group('planRenewal', () {
    test('new remark starts today, panel expiry is end + 1 day 00:00', () {
      final plan = planRenewal(
        'MaSandar-1_15.11.26-15.2.27',
        3,
        today: DateTime(2026, 11, 16, 14, 30),
      );
      expect(plan.newEmail, 'MaSandar-1_16.11.26-16.2.27');
      expect(plan.endDate, DateTime(2027, 2, 16));
      expect(
        plan.expiryTimeMs,
        DateTime(2027, 2, 17).millisecondsSinceEpoch,
      );
    });
  });

  group('extendQuotaGb', () {
    test('x1.35 rounded to whole GB', () {
      expect(extendQuotaGb(67.5), 91); // 91.125 -> 91
      expect(extendQuotaGb(60), 81);
      expect(extendQuotaGb(100), 135);
      expect(extendQuotaGb(50), 68); // 67.5 -> 68
    });
  });

  group('buildCreatePayload', () {
    test('VLESS client with stable subId and server-generated UUID', () {
      final payload = buildCreatePayload(
        name: 'NewUser',
        quotaGb: 50,
        expiryTimeMs: DateTime(2027, 2, 17).millisecondsSinceEpoch,
        inboundId: 1,
        today: DateTime(2026, 11, 16),
      );
      final client = payload['client'] as Map<String, dynamic>;
      expect(payload['inboundIds'], [1]);
      expect(client['id'], '');
      expect(client['flow'], 'xtls-rprx-vision');
      expect(client['email'], 'NewUser_16.11.26-16.2.27');
      expect(client['subId'], 'NewUser');
      expect(client['totalGB'], 50);
      expect(client['enable'], true);
      expect(client['limitIp'], 1);
    });

    test('no expiry keeps the bare name as email', () {
      final payload = buildCreatePayload(
        name: 'NoExp',
        quotaGb: 0,
        expiryTimeMs: 0,
        inboundId: 1,
      );
      final client = payload['client'] as Map<String, dynamic>;
      expect(client['email'], 'NoExp');
      expect(client['totalGB'], 0);
    });
  });
}
