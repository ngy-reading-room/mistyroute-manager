/// Billing estimate for the DigitalOcean VPS (mistyroute).
///
/// PRIMARY source is the VPS/panel data — no DO token needed.
/// The panel's inbound "down" total is traffic the server sent to
/// clients, i.e. DigitalOcean outbound. DO bills outbound only:
/// 1 TB/month (1024 GiB) included, overage $0.01/GiB; the droplet
/// (ubuntu-s-1vcpu-1gb-sgp1) is $6.00/month.
///
/// Honest label: this is an ESTIMATE from VPS data. The panel
/// counters are cumulative since the last traffic reset — for an
/// exact calendar-month figure, reset traffic on the 1st. MMK uses
/// the AYA card effective rate 4,600.67 MMK/USD and is an estimate.
///
/// The DO API token is OPTIONAL and secondary only: if one is
/// saved, the app can also show the DO account balance
/// (`GET /v2/customers/my/balance`). If DO is unreachable, the
/// estimate below is unaffected.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

/// DO list price for the 1 vCPU / 1 GB droplet, USD/month.
const double dropletMonthlyUsd = 6.0;

/// DO bandwidth allowance, GiB/month outbound.
const double bandwidthAllowanceGib = 1024;

/// DO overage price, USD per GiB over the allowance.
const double overageUsdPerGib = 0.01;

/// AYA Visa effective rate (base + 3% fee), MMK per USD.
/// Verified 2026-11-09 from the October DO charge. MMK figures
/// are estimates — the card rate can move.
const double mmkPerUsd = 4600.67;

/// AYA base rate, MMK per USD — stored at the statement's own
/// precision (38,993.99 MMK / $8.73) rather than the rounded
/// 4,466.67, so the October bill reproduces exactly; the 2dp
/// figures 4,466.67 (base) and 4,600.67 (effective) are display
/// roundings of these rates.
const double ayaBaseMmkPerUsd = 38993.99 / 8.73;

/// AYA oversea transaction fee on foreign charges.
const double ayaOverseaFeeRate = 0.03;

/// AYA effective rate = base x 1.03 (displays as 4,600.67).
double get ayaEffectiveMmkPerUsd => ayaBaseMmkPerUsd * 1.03;

/// Round to 2 decimals (kyats and cents).
double _round2(double v) => (v * 100).round() / 100;

/// The AYA Credit breakdown for one USD amount: base MMK, the 3%
/// oversea fee, and the final charge. Each component is rounded to
/// 2dp and final = base + fee, so the three displayed figures
/// always add up. October check: $8.73 -> base 38,993.99 +
/// fee 1,169.82 = final 40,163.81.
class AyaBreakdown {
  const AyaBreakdown({
    required this.usd,
    required this.baseMmk,
    required this.feeMmk,
    required this.finalMmk,
  });

  factory AyaBreakdown.fromUsd(double usd) {
    final base = _round2(usd * ayaBaseMmkPerUsd);
    final fee = _round2(base * ayaOverseaFeeRate);
    return AyaBreakdown(
      usd: usd,
      baseMmk: base,
      feeMmk: fee,
      finalMmk: base + fee,
    );
  }

  final double usd;

  /// USD x 4,466.67 (base rate).
  final double baseMmk;

  /// 3% of the base.
  final double feeMmk;

  /// Base + fee — what AYA actually charges (USD x 4,600.67).
  final double finalMmk;
}

double _gib(int bytes) => bytes / (1024 * 1024 * 1024);

int _daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// A month-to-date billing estimate computed from panel data.
class BillingEstimate {
  const BillingEstimate({
    required this.outboundGib,
    required this.allowanceGib,
    required this.overageGib,
    required this.dropletUsdMtd,
    required this.overageUsd,
    required this.totalUsdMtd,
    required this.totalMmkEstimate,
    required this.ayaMtd,
    required this.projectedOutboundGib,
    required this.projectedTotalUsd,
    required this.projectedTotalMmkEstimate,
    required this.ayaProjected,
    required this.dayOfMonth,
    required this.daysInMonth,
  });

  /// Outbound so far (panel inbound "down" total), GiB.
  final double outboundGib;
  final double allowanceGib;

  /// GiB over the allowance so far (0 when under).
  final double overageGib;

  /// Droplet cost so far this month (prorated), USD.
  final double dropletUsdMtd;

  /// Overage cost so far, USD.
  final double overageUsd;

  /// Month-to-date total, USD.
  final double totalUsdMtd;

  /// Month-to-date total in MMK (ESTIMATE at the AYA card rate).
  /// Same as [ayaMtd.finalMmk].
  final double totalMmkEstimate;

  /// AYA breakdown of the month-to-date total: base MMK, +3% fee,
  /// = final AYA charge. Shown side by side with the USD total.
  final AyaBreakdown ayaMtd;

  /// Projected outbound for the full month at the current pace, GiB.
  final double projectedOutboundGib;

  /// Projected month-end total, USD.
  final double projectedTotalUsd;

  /// Projected month-end total in MMK (ESTIMATE).
  /// Same as [ayaProjected.finalMmk].
  final double projectedTotalMmkEstimate;

  /// AYA breakdown of the projected month-end total.
  final AyaBreakdown ayaProjected;

  final int dayOfMonth;
  final int daysInMonth;

  bool get isOverAllowance => overageGib > 0;
}

/// Compute the estimate from the panel's inbound down total
/// (bytes sent by the server = DO outbound).
BillingEstimate computeBilling({
  required int outboundBytes,
  DateTime? now,
  double dropletUsd = dropletMonthlyUsd,
  double allowanceGib = bandwidthAllowanceGib,
  double overagePerGib = overageUsdPerGib,
}) {
  final date = now ?? DateTime.now();
  final dim = _daysInMonth(date.year, date.month);
  final day = date.day;
  final outboundGib = _gib(outboundBytes);
  final overageGib = outboundGib > allowanceGib
      ? outboundGib - allowanceGib
      : 0.0;
  final dropletMtd = dropletUsd * day / dim;
  final overageUsd = overageGib * overagePerGib;
  final totalUsd = dropletMtd + overageUsd;
  final pace = outboundGib / day;
  final projectedOutbound = pace * dim;
  final projectedOverage = projectedOutbound > allowanceGib
      ? (projectedOutbound - allowanceGib) * overagePerGib
      : 0.0;
  final projectedTotal = dropletUsd + projectedOverage;
  final ayaMtd = AyaBreakdown.fromUsd(totalUsd);
  final ayaProjected = AyaBreakdown.fromUsd(projectedTotal);
  return BillingEstimate(
    outboundGib: outboundGib,
    allowanceGib: allowanceGib,
    overageGib: overageGib,
    dropletUsdMtd: dropletMtd,
    overageUsd: overageUsd,
    totalUsdMtd: totalUsd,
    totalMmkEstimate: ayaMtd.finalMmk,
    ayaMtd: ayaMtd,
    projectedOutboundGib: projectedOutbound,
    projectedTotalUsd: projectedTotal,
    projectedTotalMmkEstimate: ayaProjected.finalMmk,
    ayaProjected: ayaProjected,
    dayOfMonth: day,
    daysInMonth: dim,
  );
}

/// Format USD with 2 decimals, e.g. "$3.20".
String formatUsd(double usd) => '\$${usd.toStringAsFixed(2)}';

/// Format MMK with thousands separators, e.g. "14,722 MMK".
String formatMmk(double mmk) {
  final whole = mmk.round().toString();
  final buf = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buf.write(',');
    buf.write(whole[i]);
  }
  return '${buf.toString()} MMK';
}

/// Format MMK with 2 decimals, e.g. "38,993.99 MMK".
String formatMmk2(double mmk) {
  final parts = mmk.toStringAsFixed(2).split('.');
  final whole = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buf.write(',');
    buf.write(whole[i]);
  }
  return '${buf.toString()}.${parts[1]} MMK';
}

/// Optional, secondary only: read the DO account balance
/// (`GET https://api.digitalocean.com/v2/customers/my/balance`).
/// Returns the month-to-date balance string (e.g. "8.73") or null
/// when DO is unreachable / the token is wrong. Never throws.
Future<String?> fetchDoBalance({required String token}) async {
  try {
    final res = await http
        .get(
          Uri.parse('https://api.digitalocean.com/v2/customers/my/balance'),
          headers: {
            'Authorization': 'Bearer ${token.trim()}',
            'Content-Type': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return null;
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final monthToDate = body['month_to_date_balance'];
    if (monthToDate != null) return monthToDate.toString();
    final balance = body['account_balance'];
    if (balance != null) return balance.toString();
    return null;
  } on Exception {
    return null;
  }
}
