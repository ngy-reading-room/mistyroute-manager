// Unit tests for the billing estimate: droplet + overage math,
// the AYA breakdown (base + 3% fee = final charge), and the
// October statement case: DO $8.73 -> base 38,993.99 MMK +
// fee 1,169.82 MMK = final 40,163.81 MMK.
import 'package:flutter_test/flutter_test.dart';
import 'package:mistyroutemanager/services/billing.dart';

int _gib(double gib) => (gib * 1024 * 1024 * 1024).round();

void main() {
  group('AyaBreakdown', () {
    test('October bill: \$8.73 -> 38,993.99 + 1,169.82 = 40,163.81', () {
      final b = AyaBreakdown.fromUsd(8.73);
      expect(b.baseMmk.toStringAsFixed(2), '38993.99');
      expect(b.feeMmk.toStringAsFixed(2), '1169.82');
      expect(b.finalMmk.toStringAsFixed(2), '40163.81');
      // The three displayed figures add up exactly.
      expect(
        (b.baseMmk + b.feeMmk).toStringAsFixed(2),
        b.finalMmk.toStringAsFixed(2),
      );
    });

    test('display rates are 4,466.67 base and 4,600.67 effective', () {
      expect(ayaBaseMmkPerUsd.toStringAsFixed(2), '4466.67');
      expect(ayaEffectiveMmkPerUsd.toStringAsFixed(2), '4600.67');
    });

    test('\$6.00 droplet month breaks down consistently', () {
      final b = AyaBreakdown.fromUsd(6.0);
      expect(b.baseMmk.toStringAsFixed(2), '26799.99');
      expect(b.feeMmk.toStringAsFixed(2), '804.00');
      expect(b.finalMmk.toStringAsFixed(2), '27603.99');
    });
  });

  group('computeBilling', () {
    test('under the allowance: droplet only, prorated', () {
      // 16 Nov (day 16 of 30), 500 GiB outbound.
      final e = computeBilling(
        outboundBytes: _gib(500),
        now: DateTime(2026, 11, 16),
      );
      expect(e.outboundGib, 500);
      expect(e.overageGib, 0);
      expect(e.overageUsd, 0);
      expect(e.dropletUsdMtd, closeTo(6.0 * 16 / 30, 0.001));
      expect(e.totalUsdMtd, closeTo(6.0 * 16 / 30, 0.001));
      expect(e.ayaMtd.finalMmk, e.totalMmkEstimate);
      expect(e.ayaMtd.baseMmk + e.ayaMtd.feeMmk, e.ayaMtd.finalMmk);
      // Pace 500/16 per day -> ~937.5 GiB for the month: still under.
      expect(e.projectedOutboundGib, closeTo(937.5, 0.01));
      expect(e.projectedTotalUsd, 6.0);
    });

    test('over the allowance: overage at \$0.01/GiB', () {
      // 16 Nov, 1100 GiB outbound -> 76 GiB over.
      final e = computeBilling(
        outboundBytes: _gib(1100),
        now: DateTime(2026, 11, 16),
      );
      expect(e.overageGib, closeTo(76, 0.001));
      expect(e.overageUsd, closeTo(0.76, 0.001));
      expect(e.totalUsdMtd, closeTo(6.0 * 16 / 30 + 0.76, 0.001));
      expect(e.isOverAllowance, isTrue);
      expect(e.ayaMtd.finalMmk, e.totalMmkEstimate);
    });

    test('formatMmk2 keeps two decimals with separators', () {
      expect(formatMmk2(38993.99), '38,993.99 MMK');
      expect(formatMmk2(40163.81), '40,163.81 MMK');
      expect(formatUsd(8.73), '\$8.73');
    });
  });
}
