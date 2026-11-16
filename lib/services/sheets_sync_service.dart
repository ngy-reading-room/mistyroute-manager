/// Google Sheets sync for the real `vlesslist` spreadsheet.
///
/// The spreadsheet is named `vlesslist` (ID below) and its only tab
/// is `Sheet1` — verified 2026-11-17 via the Sheets API (the tab is
/// NOT called `vlesslist`; the v0.2.1 code targeted a tab that does
/// not exist, so every sync would 404). Columns A–F, exactly:
///
///   Name | Subscription URL | Config | Expire Date | Group | Remark
///
/// - Name = the clean client name (remark dates stripped).
/// - Subscription URL = `https://ngylab.cloud-ip.cc:2096/ngylab_sub/<subId>`
///   with the panel's REAL subId (mangled for some clients, e.g.
///   EiKay -> 8pt4xbd1kpors3rv), from the per-client record.
/// - Config = the FRESH vless:// link fetched from that sub URL
///   (base64-decoded, first vless:// line). If the fetch fails,
///   the sheet's existing Config cell is kept, never blanked.
/// - Expire Date = the remark end date as ISO yyyy-MM-dd (see
///   [sheetExpireDate]); '∞' for clients with no expiry.
/// - Group = the panel group; Remark = the full remark string.
///
/// Sync behaviour: the sheet is READ first, then existing rows are
/// updated in place (matched by Name, falling back to the subId in
/// the Subscription URL; the sheet's row order is kept), genuinely
/// new clients are appended, and rows for clients no longer in the
/// panel are left untouched and reported — never deleted. The write
/// is one merged PUT of the read-back matrix, never a blind wipe.
/// If any row has content beyond column F, the sync aborts instead
/// of writing. Demo mode is refused by the provider before this
/// service is ever called (sample clients must never overwrite the
/// real sheet).
///
/// No Google account is needed to unit-test this file: the HTTP
/// client is injectable (see test/sheets_sync_test.dart). The real
/// spreadsheet is NEVER touched by tests.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/panel_models.dart';
import 'client_actions.dart';

/// The tab that holds the client table. The spreadsheet is named
/// `vlesslist`; its only tab is `Sheet1` (verified 2026-11-17).
const sheetsTabName = 'Sheet1';

/// The real spreadsheet ID (Drive > Work > mistyroute).
const sheetsSpreadsheetIdDefault =
    '15XUOcPg0PT6uveYInKtf9NlcZhx9RZPeYMlHOl66cW4';

/// The exact header of the live sheet (row 1, columns A–F).
const sheetHeader = [
  'Name',
  'Subscription URL',
  'Config',
  'Expire Date',
  'Group',
  'Remark',
];

/// Base of the subscription URLs (the panel's own domain form).
const _subBaseUrl = 'https://ngylab.cloud-ip.cc:2096/ngylab_sub';

/// The subscription URL for a subId.
String subUrlFor(String subId) => '$_subBaseUrl/$subId';

/// The subId embedded in a subscription URL, or null when the URL
/// does not look like one of ours.
String? subIdFromUrl(String url) {
  final marker = '/ngylab_sub/';
  final i = url.indexOf(marker);
  if (i < 0) return null;
  final rest = url.substring(i + marker.length).split('?').first;
  return rest.isEmpty ? null : rest;
}

/// `2026-11-15` — ISO, zero-padded, so Sheets can never misread it
/// as a US M-D-Y date.
String formatIsoDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Parse an Expire Date cell from the sheet: ISO `2027-01-16` or
/// the display form `15-11-26` / `3-12-26` (day-month-2-digit-year,
/// as Sheets shows real date cells in this sheet — verified: MaMee
/// `3-12-26` is Dec 3, not Mar 12). '∞', '' and anything else
/// parse to null.
DateTime? parseSheetDate(String cell) {
  final s = cell.trim();
  if (s.isEmpty || s == '∞') return null;
  final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(s);
  if (iso != null) {
    return _validDate(
      int.parse(iso.group(1)!),
      int.parse(iso.group(2)!),
      int.parse(iso.group(3)!),
    );
  }
  final dmy = RegExp(r'^(\d{1,2})-(\d{1,2})-(\d{2}|\d{4})$').firstMatch(s);
  if (dmy != null) {
    var year = int.parse(dmy.group(3)!);
    if (year < 100) year += 2000;
    return _validDate(
      year,
      int.parse(dmy.group(2)!),
      int.parse(dmy.group(1)!),
    );
  }
  return null;
}

DateTime? _validDate(int year, int month, int day) {
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final d = DateTime(year, month, day);
  if (d.year != year || d.month != month || d.day != day) return null;
  return d;
}

/// The Expire Date cell for a client: the remark end date as ISO
/// yyyy-MM-dd (same end-date rule as Fix names — see
/// [remarkEndDate]), or '∞' when there is no end date.
String sheetExpireDate(ClientInfo client) {
  final end = remarkEndDate(client.email, client.expiryTimeMs);
  return end == null ? '∞' : formatIsoDate(end);
}

/// One A–F row for a client.
///
/// `freshConfig` is the vless:// link fetched from the sub URL;
/// when it is empty, the existing row's Config cell is kept (never
/// blanked). `existingRow` is the matched sheet row, if any.
///
/// Panel-date safeguard: when the existing Expire Date cell holds a
/// date that differs from the computed one AND equals the panel
/// expiry's calendar date, the existing cell is kept — the sheet
/// already holds panel truth there (live cases: ZZWO 2027-01-16
/// and MTTM 30-10-26), and the sync must not silently regress it.
List<String> buildSheetRow(
  ClientInfo client, {
  String freshConfig = '',
  List<String>? existingRow,
}) {
  final name = parseRemark(client.email).name;
  final existingSubId =
      existingRow != null && existingRow.length > 1
          ? subIdFromUrl(existingRow[1])
          : null;
  final subId = client.subId.isNotEmpty
      ? client.subId
      : (existingSubId ?? name);
  final config = freshConfig.isNotEmpty
      ? freshConfig
      : (existingRow != null && existingRow.length > 2
          ? existingRow[2]
          : '');
  var expire = sheetExpireDate(client);
  if (existingRow != null && existingRow.length > 3) {
    final existingDate = parseSheetDate(existingRow[3]);
    final computed = remarkEndDate(client.email, client.expiryTimeMs);
    final panelDate = dateOfEpochMs(client.expiryTimeMs);
    if (existingDate != null &&
        computed != null &&
        existingDate != computed &&
        panelDate != null &&
        existingDate == panelDate) {
      expire = formatIsoDate(existingDate);
    }
  }
  return [
    name,
    subUrlFor(subId),
    config,
    expire,
    client.group,
    client.email,
  ];
}

/// The result of merging panel clients into the sheet's rows.
class SheetMerge {
  const SheetMerge({
    required this.rows,
    required this.updated,
    required this.appended,
    required this.orphans,
    required this.keptPanelDates,
  });

  /// The full matrix to write back (header + all rows).
  final List<List<String>> rows;

  /// Existing rows updated in place.
  final int updated;

  /// Genuinely new clients appended as new rows.
  final int appended;

  /// Sheet rows kept untouched because the client is not in the
  /// panel any more.
  final int orphans;

  /// Clients whose Expire Date cell was kept as the sheet's panel
  /// date instead of the computed date (see [buildSheetRow]).
  final List<String> keptPanelDates;
}

/// Merge panel clients into the sheet's existing rows (pure:
/// no I/O, so it is unit-tested with fake data).
///
/// - The sheet's row order is kept; matching is by Name first,
///   then by the subId in the Subscription URL.
/// - New clients are appended in panel order; rows for clients no
///   longer in the panel are left untouched.
/// - `freshConfigs` maps client email -> fresh vless:// link; a
///   client without one keeps its existing Config cell.
SheetMerge mergeSheetRows({
  required List<List<String>> existing,
  required List<ClientInfo> clients,
  required Map<String, String> freshConfigs,
}) {
  List<List<String>> rows;
  if (existing.isEmpty) {
    rows = [List<String>.from(sheetHeader)];
  } else {
    // Normalise every row to exactly 6 cells: pad ragged rows
    // (the Sheets API omits trailing empty cells) and drop any
    // extra cells (the sync aborts on those before merging, but
    // the merge itself must never crash on them).
    rows = existing.map((r) {
      final row = List<String>.from(r);
      while (row.length < 6) {
        row.add('');
      }
      if (row.length > 6) row.length = 6;
      return row;
    }).toList();
    if (rows.first[0] == 'Name') {
      rows[0] = List<String>.from(sheetHeader);
    } else {
      rows.insert(0, List<String>.from(sheetHeader));
    }
  }
  final nameIndex = <String, int>{};
  final subIdIndex = <String, int>{};
  for (var i = 1; i < rows.length; i++) {
    final name = rows[i][0];
    if (name.isNotEmpty) nameIndex.putIfAbsent(name, () => i);
    final subId = subIdFromUrl(rows[i][1]);
    if (subId != null) subIdIndex.putIfAbsent(subId, () => i);
  }
  var updated = 0;
  var appended = 0;
  final keptPanelDates = <String>[];
  final seenRows = <int>{};
  for (final client in clients) {
    final name = parseRemark(client.email).name;
    var idx = nameIndex[name];
    idx ??= client.subId.isNotEmpty ? subIdIndex[client.subId] : null;
    final row = buildSheetRow(
      client,
      freshConfig: freshConfigs[client.email] ?? '',
      existingRow: idx != null ? rows[idx] : null,
    );
    // Record the panel-date safeguard (see buildSheetRow).
    if (idx != null) {
      final existingDate = parseSheetDate(rows[idx][3]);
      final computed = remarkEndDate(client.email, client.expiryTimeMs);
      final panelDate = dateOfEpochMs(client.expiryTimeMs);
      if (existingDate != null &&
          computed != null &&
          existingDate != computed &&
          panelDate != null &&
          existingDate == panelDate) {
        keptPanelDates.add(name);
      }
    }
    if (idx != null) {
      rows[idx] = row;
      seenRows.add(idx);
      updated++;
    } else {
      rows.add(row);
      appended++;
    }
  }
  // Orphans are the pre-existing data rows no client matched
  // (appended rows sit past them, so they are excluded here).
  var orphans = 0;
  for (var i = 1; i < rows.length - appended; i++) {
    if (!seenRows.contains(i)) orphans++;
  }
  return SheetMerge(
    rows: rows,
    updated: updated,
    appended: appended,
    orphans: orphans,
    keptPanelDates: keptPanelDates,
  );
}

/// The one-time Cloud Console setup the app cannot do itself.
/// Shown in the app before the first sign-in and again when
/// sign-in fails because it is missing.
String sheetsSetupSteps() => '''Google Sheets sync needs a one-time setup in Google Cloud Console (about 10 minutes, done once):

1. Open console.cloud.google.com and pick the project that owns the `vlesslist` spreadsheet (or create one).
2. Enable the Google Sheets API: APIs & Services → Library → search "Google Sheets API" → Enable.
3. Create the Android OAuth client: APIs & Services → Credentials → Create Credentials → OAuth client ID → Android. Package name: com.ngy.mistyroutemanager — SHA-1: 2A:F2:AC:97:7F:A8:9D:3C:01:9F:A7:61:BB:63:B4:4D:55:CF:CC:C6
4. Add google-services.json to the app: download it from the Firebase/Cloud project (or from the OAuth client page) into android/app/google-services.json, then rebuild the APK and reinstall it.
5. Share the spreadsheet: in Google Sheets, share `vlesslist` with the Google account you sign in with here, as Editor.

The app itself only reads the sheet, updates rows in place, and appends new clients — it never deletes rows.''';

/// Thrown when Google sign-in cannot work because the one-time
/// setup above is missing.
class SheetsSetupNeeded implements Exception {
  SheetsSetupNeeded(this.steps);
  final String steps;
}

/// Syncs panel clients to the `vlesslist` spreadsheet (tab
/// `Sheet1`) through the Sheets REST API. The access token comes
/// from the Google sign-in in Settings.
class SheetsSyncService {
  SheetsSyncService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Fetch the fresh vless:// link for one subId from the
  /// subscription URL (same fresh-config rule as the manual sheet
  /// sync). Returns null on any failure — the caller keeps the
  /// sheet's existing Config cell instead of blanking it.
  Future<String?> fetchFreshConfig(String subId) async {
    try {
      final res = await _client
          .get(Uri.parse(subUrlFor(subId)))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final body = res.body.trim();
      if (body.startsWith('vless://')) {
        return body.split('\n').first.trim();
      }
      final decoded = utf8.decode(
        base64Decode(body.replaceAll(RegExp(r'\s'), '')),
      );
      for (final line in decoded.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.startsWith('vless://')) return trimmed;
      }
      return null;
    } on Exception {
      return null;
    }
  }

  /// Read the sheet, merge the clients in, write the merged
  /// matrix back. Returns (ok, message) for the UI to show.
  Future<(bool, String)> sync({
    required String accessToken,
    required String spreadsheetId,
    required List<ClientInfo> clients,
  }) async {
    final id = parseSpreadsheetId(spreadsheetId);
    if (id.isEmpty) {
      return (false, 'No spreadsheet ID — paste it in Settings first.');
    }
    if (accessToken.isEmpty) {
      return (false, 'Not signed in to Google — sign in first.');
    }
    try {
      final readUri = Uri.parse(
        'https://sheets.googleapis.com/v4/spreadsheets/$id'
        '/values/$sheetsTabName!A1:F',
      );
      final read = await _client.get(
        readUri,
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      if (read.statusCode != 200) {
        return (false, _readError(read.statusCode));
      }
      final decoded = jsonDecode(read.body) as Map<String, dynamic>;
      final values = (decoded['values'] as List?) ?? [];
      final existing = values
          .map(
            (r) => (r as List).map((c) => c.toString()).toList(),
          )
          .toList();
      if (existing.any((r) => r.length > 6)) {
        return (
          false,
          'The sheet has content beyond column F — sync refused, '
              'nothing was written. Remove the extra columns first.',
        );
      }
      // Fresh configs, fetched in parallel; a failed fetch keeps
      // that row's existing Config cell (reported below).
      final freshConfigs = <String, String>{};
      final configFailures = <String>[];
      await Future.wait(
        clients.map((c) async {
          final subId =
              c.subId.isNotEmpty ? c.subId : parseRemark(c.email).name;
          final link = await fetchFreshConfig(subId);
          if (link != null) {
            freshConfigs[c.email] = link;
          } else {
            configFailures.add(parseRemark(c.email).name);
          }
        }),
      );
      final merge = mergeSheetRows(
        existing: existing,
        clients: clients,
        freshConfigs: freshConfigs,
      );
      final range = '$sheetsTabName!A1:F${merge.rows.length}';
      final putUri = Uri.parse(
        'https://sheets.googleapis.com/v4/spreadsheets/$id'
        '/values/$range',
      ).replace(queryParameters: {'valueInputOption': 'USER_ENTERED'});
      final put = await _client.put(
        putUri,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'range': range, 'values': merge.rows}),
      );
      if (put.statusCode != 200) {
        return (
          false,
          'Could not write the sheet (HTTP ${put.statusCode}) — '
              'nothing was changed. Check that the signed-in account '
              'can edit the spreadsheet.',
        );
      }
      final msg = StringBuffer(
        'Synced ${clients.length} clients to vlesslist '
        '(${merge.updated} updated, ${merge.appended} new',
      );
      if (merge.orphans > 0) {
        msg.write(', ${merge.orphans} sheet rows kept (not in panel)');
      }
      msg.write(').');
      if (freshConfigs.isNotEmpty) {
        msg.write(' ${freshConfigs.length} fresh links fetched.');
      }
      if (configFailures.isNotEmpty) {
        msg.write(
          ' ${configFailures.length} links could not be fetched — '
          'kept the old ones '
          '(${configFailures.take(3).join(', ')}'
          '${configFailures.length > 3 ? ', …' : ''}).',
        );
      }
      if (merge.keptPanelDates.isNotEmpty) {
        msg.write(
          ' Kept the sheet’s panel date for: '
          '${merge.keptPanelDates.join(', ')} '
          '(differs from the remark).',
        );
      }
      return (true, msg.toString());
    } on Exception catch (e) {
      return (false, 'Could not reach Google Sheets: $e');
    }
  }

  String _readError(int status) {
    if (status == 404) {
      return 'Spreadsheet or the Sheet1 tab not found (404) — '
          'check the spreadsheet ID in Settings.';
    }
    if (status == 401 || status == 403) {
      return 'Google sign-in expired, or the signed-in account '
          'cannot edit this spreadsheet (HTTP $status) — sign in '
          'again and check the sheet is shared with that account.';
    }
    return 'Could not read the sheet (HTTP $status).';
  }
}

/// Extract a spreadsheet ID from a full sheet URL, or return the
/// input unchanged when it already looks like an ID.
String parseSpreadsheetId(String input) {
  final trimmed = input.trim();
  final match = RegExp(r'/spreadsheets/d/([a-zA-Z0-9_-]+)').firstMatch(
    trimmed,
  );
  return match?.group(1) ?? trimmed;
}
