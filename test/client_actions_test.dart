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
  // Timestamps from the real Nov 16 panel JSON (Yangon time).
  // The bulk stamp is shared by 10 clients and must never be
  // trusted as a start date.
  final bulkMs = DateTime(2026, 11, 3, 13, 42).millisecondsSinceEpoch;
  final bulk = {bulkMs};

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

    test('bare name + trusted updated_at (MaSandar-1, renewed Nov 15)', () {
      final r = planNameCorrection(
        'MaSandar-1',
        DateTime(2027, 2, 15, 23, 59).millisecondsSinceEpoch,
        updatedAtMs: DateTime(2026, 11, 15, 11, 10).millisecondsSinceEpoch,
        createdAtMs: DateTime(2026, 10, 14, 10, 2).millisecondsSinceEpoch,
      );
      expect(r, isA<NameFixed>());
      expect(
        (r as NameFixed).correctedEmail,
        'MaSandar-1_15.11.26-15.2.27',
      );
    });

    test('single date + trusted updated_at (MAMS, edited Nov 11)', () {
      final r = planNameCorrection(
        'MAMS11.12.26',
        DateTime(2026, 12, 11, 23, 59).millisecondsSinceEpoch,
        updatedAtMs: DateTime(2026, 11, 11, 15, 13).millisecondsSinceEpoch,
        createdAtMs: DateTime(2026, 9, 29, 13, 40).millisecondsSinceEpoch,
      );
      expect(r, isA<NameFixed>());
      expect((r as NameFixed).correctedEmail, 'MAMS_11.11.26-11.12.26');
    });

    test('single date + trusted updated_at (KoYeMin, edited Nov 5)', () {
      final r = planNameCorrection(
        'KoYeMin_2.12.26',
        DateTime(2026, 12, 2, 23, 59).millisecondsSinceEpoch,
        updatedAtMs: DateTime(2026, 11, 5, 10, 52).millisecondsSinceEpoch,
        createdAtMs: DateTime(2026, 10, 2, 8, 12).millisecondsSinceEpoch,
      );
      expect(r, isA<NameFixed>());
      expect((r as NameFixed).correctedEmail, 'KoYeMin_5.11.26-2.12.26');
    });

    test('single date + shared bulk stamp falls back to end minus 1 month (MaNwe)', () {
      final r = planNameCorrection(
        'MaNwe22.11.26',
        DateTime(2026, 11, 22, 23, 59).millisecondsSinceEpoch,
        updatedAtMs: bulkMs,
        createdAtMs: DateTime(2026, 9, 22, 10, 17).millisecondsSinceEpoch,
        sharedUpdatedAtMs: bulk,
      );
      expect(r, isA<NameFixed>());
      expect((r as NameFixed).correctedEmail, 'MaNwe_22.10.26-22.11.26');
    });

    test('single date + bulk stamp (MaMee, MaTheint, MTTM)', () {
      final maMee = planNameCorrection(
        'MaMee_3.12.26',
        DateTime(2026, 12, 3, 23, 59).millisecondsSinceEpoch,
        updatedAtMs: bulkMs,
        createdAtMs: DateTime(2026, 9, 3, 14, 39).millisecondsSinceEpoch,
        sharedUpdatedAtMs: bulk,
      );
      expect((maMee as NameFixed).correctedEmail, 'MaMee_3.11.26-3.12.26');
      final maTheint = planNameCorrection(
        'MaTheint24.10.26',
        DateTime(2026, 10, 24).millisecondsSinceEpoch,
        updatedAtMs: bulkMs,
        createdAtMs: DateTime(2026, 9, 24, 14, 13).millisecondsSinceEpoch,
        sharedUpdatedAtMs: bulk,
      );
      expect(
        (maTheint as NameFixed).correctedEmail,
        'MaTheint_24.9.26-24.10.26',
      );
      // MTTM: remark end Oct 29 wins over the panel's Oct 30 00:00
      // (a 1-day difference is the end+1-day convention).
      final mttm = planNameCorrection(
        'MTTM29.10.26',
        DateTime(2026, 10, 30).millisecondsSinceEpoch,
        updatedAtMs: bulkMs,
        createdAtMs: DateTime(2026, 9, 29, 13, 17).millisecondsSinceEpoch,
        sharedUpdatedAtMs: bulk,
      );
      expect((mttm as NameFixed).correctedEmail, 'MTTM_29.9.26-29.10.26');
    });

    test('never-edited record starts on the creation date (ZZWO)', () {
      // ZZWO's updated_at is 14 ms after its created_at — never
      // edited since creation. Panel expiry Jan 16 wins over the
      // remark's Feb 16 (31 days apart = a stale remark).
      final created = DateTime(2026, 11, 16, 12, 32).millisecondsSinceEpoch;
      final r = planNameCorrection(
        'ZZWO_16.2.27',
        DateTime(2027, 1, 16, 23, 59).millisecondsSinceEpoch,
        updatedAtMs: created + 14,
        createdAtMs: created,
      );
      expect(r, isA<NameFixed>());
      expect((r as NameFixed).correctedEmail, 'ZZWO_16.11.26-16.1.27');
    });

    test('no expiry and no remark date is skipped (bigsun)', () {
      final r = planNameCorrection('bigsun', 0);
      expect(r, isA<NameSkipped>());
      expect((r as NameSkipped).reason, contains('no dates'));
    });

    test('end not after start is skipped', () {
      final r = planNameCorrection('EiKay15.11.26-15.10.26', 0);
      expect(r, isA<NameSkipped>());
      expect((r as NameSkipped).reason, contains('not after'));
    });
  });

  group('remarkEndDate', () {
    test('bare name uses the panel expiry date (not minus 1 day)', () {
      expect(
        remarkEndDate(
          'MaSandar-1',
          DateTime(2027, 2, 15, 23, 59).millisecondsSinceEpoch,
        ),
        DateTime(2027, 2, 15),
      );
      // A 00:00 expiry is the same calendar day, not the day before.
      expect(
        remarkEndDate(
          'MaTheint24.10.26',
          DateTime(2026, 10, 24).millisecondsSinceEpoch,
        ),
        DateTime(2026, 10, 24),
      );
    });

    test('panel wins only when it differs by more than 1 day', () {
      // ZZWO: 31 days apart -> panel Jan 16.
      expect(
        remarkEndDate(
          'ZZWO_16.2.27',
          DateTime(2027, 1, 16, 23, 59).millisecondsSinceEpoch,
        ),
        DateTime(2027, 1, 16),
      );
      // MTTM: 1 day apart -> remark Oct 29.
      expect(
        remarkEndDate(
          'MTTM29.10.26',
          DateTime(2026, 10, 30).millisecondsSinceEpoch,
        ),
        DateTime(2026, 10, 29),
      );
    });

    test('no remark date and no expiry is null', () {
      expect(remarkEndDate('bigsun', 0), isNull);
    });
  });

  group('bulkUpdatedAtValues', () {
    test('only values occurring more than once, never 0', () {
      expect(
        bulkUpdatedAtValues([0, 0, 5, 5, 7, 9, 9, 9]),
        {5, 9},
      );
      expect(bulkUpdatedAtValues([1, 2, 3]), isEmpty);
    });
  });
}
