/// Pure client-action logic: remark dates, renewal math, quota math and
/// the add-client payload.
///
/// No I/O here, so every function is unit-tested (see
/// test/client_actions_test.dart).
///
/// Panel conventions (user's, recorded in MEMORY.md):
/// - remark / email = `{Name}_{start D.M.YY}-{end D.M.YY}`, e.g.
///   `MaSandar-1_15.11.26-15.2.27` (day/month NOT zero-padded).
/// - subId = the stable `{Name}` — the subscription URL never changes.
/// - renewal = extend expiry + reset traffic + update remark dates;
///   panel expiry = remark end-date + 1 day, 00:00:00.
/// - quota rule: any client at >=80% gets quota x1.35.
///
/// Quotas: the panel's `model.Client.totalGB` is `int64` (whole GB), so
/// every GB value sent to the panel is a whole number. The x1.35 result
/// is rounded to the nearest whole GB.
library;

/// The parts of a remark/email: the stable name and the two dates.
/// Dates are null when the remark has no parseable `D.M.YY-D.M.YY` part.
class RemarkParts {
  const RemarkParts({required this.name, this.start, this.end});

  final String name;
  final DateTime? start;
  final DateTime? end;
}

/// Split `{Name}_{start D.M.YY}-{end D.M.YY}`. A remark without the
/// `_dates` part yields just the name (e.g. a legacy client).
RemarkParts parseRemark(String email) {
  final underscore = email.indexOf('_');
  if (underscore < 0) return RemarkParts(name: email);
  final name = email.substring(0, underscore);
  final dates = email.substring(underscore + 1).split('-');
  if (dates.length != 2) return RemarkParts(name: name);
  final start = _parseDmYy(dates[0]);
  final end = _parseDmYy(dates[1]);
  if (start == null || end == null) return RemarkParts(name: name);
  return RemarkParts(name: name, start: start, end: end);
}

/// `15.11.26` -> 2026-11-15. Two-digit year = 2000+yy.
DateTime? _parseDmYy(String s) {
  final parts = s.split('.');
  if (parts.length != 3) return null;
  final d = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final y = int.tryParse(parts[2]);
  if (d == null || m == null || y == null) return null;
  if (d < 1 || d > 31 || m < 1 || m > 12 || y < 0 || y > 99) return null;
  return DateTime(2000 + y, m, d);
}

/// `2026-11-15` -> `15.11.26` (no zero-padding, per the convention).
String formatDmYy(DateTime d) => '${d.day}.${d.month}.${d.year % 100}';

String buildRemark(String name, DateTime start, DateTime end) =>
    '${name}_${formatDmYy(start)}-${formatDmYy(end)}';

/// Add calendar months, clamping the day (Jan 31 + 1 month = Feb 28,
/// not Mar 3 — plain DateTime(y, m + n, d) would overflow into March).
DateTime addMonths(DateTime d, int months) {
  final total = (d.year * 12 + (d.month - 1)) + months;
  final year = total ~/ 12;
  final month = total % 12 + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  final day = d.day > lastDay ? lastDay : d.day;
  return DateTime(year, month, day);
}

/// The result of planning a renewal: the new remark, the panel
/// expiryTime (epoch ms) and the remark end date.
class RenewalPlan {
  const RenewalPlan({
    required this.newEmail,
    required this.expiryTimeMs,
    required this.endDate,
  });

  final String newEmail;
  final int expiryTimeMs;
  final DateTime endDate;
}

/// Renew `email` for `months` starting `today` (default: now).
/// New remark start = today, end = today + months; panel expiry =
/// end date + 1 day at 00:00 (the convention).
RenewalPlan planRenewal(String email, int months, {DateTime? today}) {
  final now = today ?? DateTime.now();
  final start = DateTime(now.year, now.month, now.day);
  final end = addMonths(start, months);
  final name = parseRemark(email).name;
  return RenewalPlan(
    newEmail: buildRemark(name, start, end),
    expiryTimeMs: DateTime(end.year, end.month, end.day + 1)
        .millisecondsSinceEpoch,
    endDate: end,
  );
}

/// Quota x1.35, rounded to the nearest whole GB (the panel's
/// totalGB is int64). 67.5 GB -> 91 GB; 60 GB -> 81 GB; 100 GB -> 135 GB.
int extendQuotaGb(num currentGb) => (currentGb * 1.35).round();

/// Whole-GB quota from a byte quota (clientStats `total`).
/// Returns 0 for unlimited.
int bytesToWholeGb(int bytes) =>
    bytes <= 0 ? 0 : (bytes / (1024 * 1024 * 1024)).round();

/// The `model.Client` JSON for `POST /panel/api/clients/add`, wrapped
/// as `{client: ..., inboundIds: [...]}`.
///
/// - `id` is left empty: the panel generates the UUID.
/// - `flow` is `xtls-rprx-vision` for VLESS (the panel would default
///   it, but sending it explicitly is the panel UI's own behaviour).
/// - `subId` is the stable name, so the subscription URL never changes.
/// - `totalGB` is whole GB; 0 = unlimited.
Map<String, dynamic> buildCreatePayload({
  required String name,
  required int quotaGb,
  required int expiryTimeMs,
  required int inboundId,
  int limitIp = 1,
  DateTime? today,
}) {
  final now = today ?? DateTime.now();
  final start = DateTime(now.year, now.month, now.day);
  // expiryTimeMs is the PANEL expiry (remark end + 1 day), so the
  // remark end date is one day earlier.
  final end = expiryTimeMs > 0
      ? DateTime.fromMillisecondsSinceEpoch(expiryTimeMs)
          .subtract(const Duration(days: 1))
      : null;
  final email = end == null
      ? name
      : buildRemark(
          name,
          start,
          DateTime(end.year, end.month, end.day),
        );
  return {
    'client': {
      'id': '',
      'flow': 'xtls-rprx-vision',
      'email': email,
      'limitIp': limitIp,
      'totalGB': quotaGb,
      'expiryTime': expiryTimeMs,
      'enable': true,
      'tgId': 0,
      'subId': name,
      'comment': '',
      'reset': 0,
    },
    'inboundIds': [inboundId],
  };
}
