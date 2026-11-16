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

    test('single-date forms keep the clean name and the end date', () {
      // Underscore + one date.
      var p = parseRemark('ZZWO_16.2.27');
      expect(p.name, 'ZZWO');
      expect(p.start, isNull);
      expect(p.end, DateTime(2027, 2, 16));
      p = parseRemark('MaMee_3.12.26');
      expect(p.name, 'MaMee');
      expect(p.end, DateTime(2026, 12, 3));
      // Date stuck to the name, no underscore.
      p = parseRemark('MaNwe22.11.26');
      expect(p.name, 'MaNwe');
      expect(p.end, DateTime(2026, 11, 22));
      p = parseRemark('MAMS11.12.26');
      expect(p.name, 'MAMS');
      expect(p.end, DateTime(2026, 12, 11));
    });

    test('date pair stuck to the name (no underscore)', () {
      final p = parseRemark('EiKay15.10.26-15.11.26');
      expect(p.name, 'EiKay');
      expect(p.start, DateTime(2026, 10, 15));
      expect(p.end, DateTime(2026, 11, 15));
    });
  });

  group('formatDmYy / buildRemark', () {
    test('no zero-padding, two-digit year', () {
      expect(formatDmYy(DateTime(2027, 2, 5)), '5.2.27');
      expect(buildRemark('MeMe', DateTime(2026, 11, 16), DateTime(2027, 2, 16)),
          'MeMe_16.11.26-16.2.27');
    });

    test('exact remark format: Name_D.M.YY-D.M.YY, dots not dashes', () {
      expect(
        buildRemark('EiKay', DateTime(2026, 11, 15), DateTime(2026, 12, 15)),
        'EiKay_15.11.26-15.12.26',
      );
      // Single-digit day/month are NOT zero-padded.
      expect(
        buildRemark('ZZWO', DateTime(2027, 2, 16), DateTime(2027, 5, 16)),
        'ZZWO_16.2.27-16.5.27',
      );
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
    test('NayGyi example: EiKay + 1 month continues from the old end', () {
      final plan = planRenewal(
        'EiKay_15.10.26-15.11.26',
        1,
        today: DateTime(2026, 11, 15),
      );
      expect(plan.newEmail, 'EiKay_15.11.26-15.12.26');
      expect(plan.endDate, DateTime(2026, 12, 15));
      expect(
        plan.expiryTimeMs,
        DateTime(2026, 12, 16).millisecondsSinceEpoch,
      );
    });

    test('same result when renewing a day before the old end', () {
      final plan = planRenewal(
        'EiKay_15.10.26-15.11.26',
        1,
        today: DateTime(2026, 11, 14),
      );
      expect(plan.newEmail, 'EiKay_15.11.26-15.12.26');
    });

    test('future end date: new period starts at the old end', () {
      final plan = planRenewal(
        'MaSandar-1_15.11.26-15.2.27',
        3,
        today: DateTime(2026, 11, 16, 14, 30),
      );
      expect(plan.newEmail, 'MaSandar-1_15.2.27-15.5.27');
      expect(plan.endDate, DateTime(2027, 5, 15));
      expect(
        plan.expiryTimeMs,
        DateTime(2027, 5, 16).millisecondsSinceEpoch,
      );
    });

    test('expired long ago: starts today, never backdates', () {
      final plan = planRenewal(
        'EiKay_15.10.26-15.11.26',
        1,
        today: DateTime(2026, 12, 1),
      );
      expect(plan.newEmail, 'EiKay_1.12.26-1.1.27');
      expect(plan.endDate, DateTime(2027, 1, 1));
      expect(
        plan.expiryTimeMs,
        DateTime(2027, 1, 2).millisecondsSinceEpoch,
      );
    });

    test('expired yesterday: starts today', () {
      final plan = planRenewal(
        'EiKay_15.10.26-15.11.26',
        1,
        today: DateTime(2026, 11, 16),
      );
      expect(plan.newEmail, 'EiKay_16.11.26-16.12.26');
    });

    test('single-date remark normalises to Name_start-end', () {
      final plan = planRenewal(
        'MaNwe22.11.26',
        1,
        today: DateTime(2026, 11, 16),
      );
      expect(plan.newEmail, 'MaNwe_22.11.26-22.12.26');
      expect(plan.endDate, DateTime(2026, 12, 22));
    });

    test('bare name falls back to starting today', () {
      final plan = planRenewal(
        'KoYeMin',
        1,
        today: DateTime(2026, 11, 16),
      );
      expect(plan.newEmail, 'KoYeMin_16.11.26-16.12.26');
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
  _nameCorrectionTests();
}

void _nameCorrectionTests() {
  group('planNameCorrection', () {
    test('pair stuck to name is fixed to the canonical form', () {
      final r = planNameCorrection('EiKay15.10.26-15.11.26', 0);
      expect(r, isA<NameFixed>());
      expect((r as NameFixed).correctedEmail, 'EiKay_15.10.26-15.11.26');
    });

    test('already canonical remark is unchanged', () {
      final r = planNameCorrection('EiKay_15.11.26-15.12.26', 0);
      expect(r, isA<NameAlreadyCorrect>());
    });

    test('single-date remark is skipped — start unknown', () {
      final r = planNameCorrection('MaNwe22.11.26', 0);
      expect(r, isA<NameSkipped>());
      expect((r as NameSkipped).reason, contains('start date'));
    });

    test('single date with underscore is skipped too', () {
      expect(planNameCorrection('ZZWO_16.2.27', 0), isA<NameSkipped>());
      expect(planNameCorrection('MAMS11.12.26', 0), isA<NameSkipped>());
    });

    test('bare name is skipped, with or without a panel expiry', () {
      final noExpiry = planNameCorrection('MaSandar-1', 0);
      expect(noExpiry, isA<NameSkipped>());
      expect((noExpiry as NameSkipped).reason, contains('no dates'));
      final withExpiry = planNameCorrection(
        'MaSandar-1',
        DateTime(2027, 2, 15).millisecondsSinceEpoch,
      );
      expect(withExpiry, isA<NameSkipped>());
      expect((withExpiry as NameSkipped).reason, contains('start date'));
    });

    test('end not after start is skipped', () {
      final r = planNameCorrection('EiKay15.11.26-15.10.26', 0);
      expect(r, isA<NameSkipped>());
      expect((r as NameSkipped).reason, contains('not after'));
    });
  });
}
