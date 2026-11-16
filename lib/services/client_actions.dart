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
///
/// - end: the remark's own end date when it has one; the panel
///   expiryTime's calendar date when the remark has none, or when
///   the panel date disagrees with the remark by MORE than 1 day
///   (a stale/typo remark — ZZWO's remark says Feb 16 but the
///   panel expiry is Jan 16, so the panel wins). A 1-day difference
///   is the panel's end+1-day convention, so the remark wins
///   (MTTM's remark says Oct 29, panel expiry Oct 30 00:00).
///   Verified against the real Nov 16 panel JSON (24 clients):
///   date(expiryTime) equals the remark end for every
///   single-date/bare client except ZZWO (31 days off) and MTTM
///   (1 day off, the convention) — so the task's "expiry minus
///   1 day" is WRONG and is NOT used here.
/// - start: the remark's own start date for pair remarks;
///   otherwise the client record's updated_at date when it is
///   trusted (unique across the loaded clients, not the creation
///   time, before the end and within 3 calendar months of it),
///   the created_at date when the record was never edited since
///   creation (updated within a minute of created — ZZWO), and
///   otherwise the end date minus 1 calendar month (the standard
///   1-month validity; verified against the live subIds, e.g.
///   MaTheint 24.9.26 and MTTM 29.9.26).
///   updated_at is a BULK STAMP for clients never edited since
///   Nov 3 (1793689936000 = 2026-11-03 13:42, shared by 10
///   clients) — it does NOT equal any renewal date for them, so
///   a shared updated_at is never trusted.
/// A client whose end date cannot be determined is skipped.
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
/// `expiryTimeMs` is the panel record's expiry (epoch ms, 0 = none).
/// `updatedAtMs` / `createdAtMs` are the panel record's timestamps
/// (epoch ms, 0 = not loaded yet); `sharedUpdatedAtMs` holds the
/// updated_at values that appear for more than one client in the
/// loaded list (the Nov 3 bulk stamp) and are therefore untrusted.
/// - pair present (`EiKay15.10.26-15.11.26` or the canonical form):
///   start + end are known -> canonical `Name_start-end`; if the
///   remark is already canonical, unchanged.
/// - single date (`MaNwe22.11.26`, `ZZWO_16.2.27`) or bare name
///   (`MaSandar-1`): the end comes from [remarkEndDate] and the
///   start from the record (see the class doc above); when neither
///   the remark nor the panel gives an end date, the client is
///   skipped (e.g. bigsun, expiry 0).
/// - end not after start: skipped (inconsistent dates).
NameCorrection planNameCorrection(
  String email,
  int expiryTimeMs, {
  int updatedAtMs = 0,
  int createdAtMs = 0,
  Set<int> sharedUpdatedAtMs = const {},
}) {
  final parts = parseRemark(email);
  final end = remarkEndDate(email, expiryTimeMs);
  if (end == null) {
    return NameSkipped(email, 'no dates in the existing data');
  }
  final start = parts.start ??
      _startFromRecord(
        end,
        updatedAtMs: updatedAtMs,
        createdAtMs: createdAtMs,
        sharedUpdatedAtMs: sharedUpdatedAtMs,
      );
  if (start == null || !end.isAfter(start)) {
    return NameSkipped(email, 'end date is not after the start date');
  }
  final corrected = buildRemark(parts.name, start, end);
  if (corrected == email) return NameAlreadyCorrect(email);
  return NameFixed(email, corrected);
}

/// The calendar date (local time) of a panel epoch-ms timestamp,
/// or null when the timestamp is 0 (no expiry / not loaded).
DateTime? dateOfEpochMs(int epochMs) {
  if (epochMs <= 0) return null;
  final d = DateTime.fromMillisecondsSinceEpoch(epochMs);
  return DateTime(d.year, d.month, d.day);
}

/// The remark end date for `email`, from existing data only:
/// the remark's own end date when it has one, EXCEPT when the
/// panel expiry's calendar date disagrees with it by more than
/// 1 day — then the panel date wins (the remark is stale or a
/// typo: ZZWO's remark says 16.2.27, the panel expiry is
/// 2027-01-16). A 1-day difference is the panel's end+1-day
/// convention (MTTM: remark 29.10.26, expiry 2026-10-30 00:00),
/// so the remark wins. Bare names have no remark date, so the
/// panel date is used; with neither, null.
DateTime? remarkEndDate(String email, int expiryTimeMs) {
  final remarkEnd = parseRemark(email).end;
  final panelDate = dateOfEpochMs(expiryTimeMs);
  if (remarkEnd == null) return panelDate;
  if (panelDate != null &&
      (panelDate.difference(remarkEnd).inDays).abs() > 1) {
    return panelDate;
  }
  return remarkEnd;
}

/// The updated_at values that occur for more than one client
/// (the panel's Nov 3 bulk stamp, 1793689936000, is the known
/// case). Values of 0 (not loaded) never count as shared.
Set<int> bulkUpdatedAtValues(Iterable<int> updatedAtMs) {
  final counts = <int, int>{};
  for (final ms in updatedAtMs) {
    if (ms > 0) counts[ms] = (counts[ms] ?? 0) + 1;
  }
  return counts.entries
      .where((e) => e.value > 1)
      .map((e) => e.key)
      .toSet();
}

/// Derive a start date for a remark with no start of its own.
/// Order: never-edited record -> trusted last edit -> the
/// standard 1-month validity (end minus 1 calendar month).
/// Never returns a date on or after `end` (callers check).
DateTime? _startFromRecord(
  DateTime end, {
  required int updatedAtMs,
  required int createdAtMs,
  required Set<int> sharedUpdatedAtMs,
}) {
  // Never edited since creation: updated_at within a minute of
  // created_at (ZZWO: 14 ms apart) — the period started on the
  // creation date.
  if (createdAtMs > 0 &&
      updatedAtMs > 0 &&
      (updatedAtMs - createdAtMs).abs() < 60000) {
    final created = dateOfEpochMs(createdAtMs);
    if (created != null && created.isBefore(end)) return created;
  }
  // Trusted last edit: a unique updated_at that is not the
  // creation time, before the end, and within 3 calendar months
  // of the end (inclusive — MaSandar's Nov 15 -> Feb 15 is
  // exactly 3 months).
  if (updatedAtMs > 0 &&
      updatedAtMs != createdAtMs &&
      !sharedUpdatedAtMs.contains(updatedAtMs)) {
    final updated = dateOfEpochMs(updatedAtMs);
    if (updated != null && updated.isBefore(end)) {
      final earliest = addMonths(end, -3);
      if (!updated.isBefore(earliest)) return updated;
    }
  }
  // Fallback: the standard 1-month validity, end minus 1 month.
  return addMonths(end, -1);
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
