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
/// - renewal = the new period CONTINUES from the old remark end
///   date (NayGyi's rule, 2026-11-16: EiKay_15.10.26-15.11.26 + 1
///   month -> EiKay_15.11.26-15.12.26); if the old end is already
///   past, the period starts today instead. Panel expiry = remark
///   end-date + 1 day, 00:00:00. Renewal also resets traffic.
/// - quota rule: any client at >=80% gets quota x1.35.
///
/// Quotas: the panel's `model.Client.totalGB` is `int64` (whole GB), so
/// every GB value sent to the panel is a whole number. The x1.35 result
/// is rounded to the nearest whole GB.
library;

/// The parts of a remark/email: the stable name and the two dates.
/// Dates are null when the remark has no parseable date part.
/// Single-date forms exist in the live panel (`MaNwe22.11.26`,
/// `MAMS11.12.26`, `ZZWO_16.2.27`, `MaMee_3.12.26`): for those,
/// `start` is null and `end` is the one date; `name` is the clean
/// name with the date suffix stripped, so renewal never mangles it
/// into `MaNwe22.11.26_...`.
class RemarkParts {
  const RemarkParts({required this.name, this.start, this.end});

  final String name;
  final DateTime? start;
  final DateTime? end;
}

/// Split a remark into name + dates. Handles all live forms:
/// - pair with underscore: `MaSandar-1_15.11.26-15.2.27`
/// - single date with underscore: `ZZWO_16.2.27`, `MaMee_3.12.26`
/// - pair stuck to the name: `EiKay15.10.26-15.11.26`
/// - single date stuck to the name: `MaNwe22.11.26`, `MAMS11.12.26`
/// - bare name: `KoYeMin`, `bigsun`
/// A remark without a parseable date part yields just the name
/// (e.g. a legacy client).
RemarkParts parseRemark(String email) {
  final underscore = email.indexOf('_');
  if (underscore >= 0) {
    final name = email.substring(0, underscore);
    final dates = email.substring(underscore + 1).split('-');
    if (dates.length == 2) {
      final start = _parseDmYy(dates[0]);
      final end = _parseDmYy(dates[1]);
      if (start != null && end != null) {
        return RemarkParts(name: name, start: start, end: end);
      }
    } else if (dates.length == 1) {
      final end = _parseDmYy(dates[0]);
      if (end != null) return RemarkParts(name: name, end: end);
    }
    return RemarkParts(name: name);
  }
  final pair =
      RegExp(r'^(.+?)(\d{1,2}\.\d{1,2}\.\d{2})-(\d{1,2}\.\d{1,2}\.\d{2})$')
          .firstMatch(email);
  if (pair != null) {
    final start = _parseDmYy(pair.group(2)!);
    final end = _parseDmYy(pair.group(3)!);
    if (start != null && end != null) {
      return RemarkParts(name: pair.group(1)!, start: start, end: end);
    }
  }
  final single = RegExp(r'^(.+?)(\d{1,2}\.\d{1,2}\.\d{2})$')
      .firstMatch(email);
  if (single != null) {
    final end = _parseDmYy(single.group(2)!);
    if (end != null) {
      return RemarkParts(name: single.group(1)!, end: end);
    }
  }
  return RemarkParts(name: email);
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

/// Renew `email` for `months` (NayGyi's rule, 2026-11-16).
/// The new period CONTINUES from the old remark end date:
/// start = old end, end = old end + months (calendar months, day
/// clamped). Example: `EiKay_15.10.26-15.11.26` + 1 month ->
/// `EiKay_15.11.26-15.12.26` (format: `Name_D.M.YY-D.M.YY`,
/// underscore after the name, dots inside each date, one dash
/// between the dates, no zero-padding).
/// If there is no parseable old end, or the old end is already past,
/// the period starts today instead — never backdate a period that
/// would already be over. Panel expiry = end + 1 day at 00:00.
RenewalPlan planRenewal(String email, int months, {DateTime? today}) {
  final now = today ?? DateTime.now();
  final todayDate = DateTime(now.year, now.month, now.day);
  final parts = parseRemark(email);
  final oldEnd = parts.end;
  final start = (oldEnd != null && !oldEnd.isBefore(todayDate))
      ? oldEnd
      : todayDate;
  final end = addMonths(start, months);
  return RenewalPlan(
    newEmail: buildRemark(parts.name, start, end),
    expiryTimeMs: DateTime(end.year, end.month, end.day + 1)
        .millisecondsSinceEpoch,
    endDate: end,
  );
}

/// Quota x1.35, rounded to the nearest whole GB (the panel's
/// totalGB is int64). 67.5 GB -> 91 GB; 60 GB -> 81 GB; 100 GB -> 135 GB.
int extendQuotaGb(num currentGb) => (currentGb * 1.35).round();

/// The outcome of planning a name correction for one client.
/// Dates come from EXISTING data only — never invented:
/// 1. the remark's own dates when parseable (a start+end pair), or
/// 2. the panel record's expiryTime (remark end = panel expiry - 1
///    day) — which only gives an END date, never a start.
/// A client whose start date cannot be determined is skipped.
sealed class NameCorrection {
  const NameCorrection(this.email);
  final String email;
}

/// The remark needs reformatting and the corrected form is known.
class NameFixed extends NameCorrection {
  const NameFixed(super.email, this.correctedEmail);
  final String correctedEmail;
}

/// The remark is already exactly `Name_D.M.YY-D.M.YY`.
class NameAlreadyCorrect extends NameCorrection {
  const NameAlreadyCorrect(super.email);
}

/// The remark cannot be corrected from existing data.
class NameSkipped extends NameCorrection {
  const NameSkipped(super.email, this.reason);
  final String reason;
}

/// Plan a name correction for `email` (the panel remark).
///
/// `expiryTimeMs` is the panel record's expiry (epoch ms, 0 = none);
/// it is only consulted for the skip reason — a start date can
/// never come from it, so a single-date or bare remark can never
/// be fixed by this function, only skipped.
/// - pair present (`EiKay15.10.26-15.11.26` or the canonical form):
///   start + end are known -> canonical `Name_start-end`; if the
///   remark is already canonical, unchanged.
/// - single date (`MaNwe22.11.26`, `ZZWO_16.2.27`) or bare name
///   (`MaSandar-1`): start unknown -> skipped, with the reason.
/// - end not after start: skipped (inconsistent dates).
NameCorrection planNameCorrection(String email, int expiryTimeMs) {
  final parts = parseRemark(email);
  final start = parts.start;
  final end = parts.end;
  if (start != null && end != null) {
    if (!end.isAfter(start)) {
      return NameSkipped(email, 'end date is not after the start date');
    }
    final corrected = buildRemark(parts.name, start, end);
    if (corrected == email) return NameAlreadyCorrect(email);
    return NameFixed(email, corrected);
  }
  if (end != null) {
    return NameSkipped(email,
        'start date is not in the existing data — only an end date is known');
  }
  if (expiryTimeMs > 0) {
    return NameSkipped(email,
        'start date is not in the existing data — only a panel expiry is known');
  }
  return NameSkipped(email, 'no dates in the existing data');
}

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
/// - `group` is the panel grouping label ('' = no group).
Map<String, dynamic> buildCreatePayload({
  required String name,
  required int quotaGb,
  required int expiryTimeMs,
  required int inboundId,
  int limitIp = 1,
  String group = '',
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
      'group': group,
      'comment': '',
      'reset': 0,
    },
    'inboundIds': [inboundId],
  };
}
