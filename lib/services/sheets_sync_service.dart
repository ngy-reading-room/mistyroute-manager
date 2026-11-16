/// Google Sheets sync: panel -> sheet `vlesslist` (ISO dates only).
///
/// The sync writes the whole client table in one `values.update` call
/// (Sheets API v4, plain REST over the `http` package — no generated
/// googleapis client). Columns: Name | Inbound | Status | Used GB |
/// Quota GB | Used % | Expiry | Days left. Expiry is ISO `yyyy-MM-dd`
/// (see utils/format.dart `formatDate`) — Sheets must never see
/// `3-11-26`, which it parses as US M-D-Y.
///
/// Sign-in is Google Sign-In (google_sign_in 7.2.0): the singleton
/// `GoogleSignIn.instance` must be `initialize()`d once, then
/// `authenticate()`, then the Sheets scope is authorised via
/// `account.authorizationClient.authorizeScopes(...)` to get an OAuth
/// access token.
///
/// SETUP NEEDED (cannot be completed from this workspace): the Android
/// OAuth client + google-services.json live in the user's Google Cloud
/// project, and the release keystore SHA-1 has to be registered there.
/// Until that is done, every sign-in attempt throws
/// [SheetsSetupNeeded] with the exact steps, and the UI shows them
/// instead of failing silently. The sync logic itself (row building +
/// REST write) is fully implemented and unit-tested with a fake HTTP
/// client — it only needs the access token.
library;

import 'dart:convert';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../models/panel_models.dart';
import '../utils/format.dart';

/// Thrown when Google sign-in is not configured yet. [steps] is the
/// exact setup the user must do (shown in the UI).
class SheetsSetupNeeded implements Exception {
  SheetsSetupNeeded(this.steps);
  final String steps;

  @override
  String toString() => steps;
}

class SheetsException implements Exception {
  SheetsException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The exact setup steps (kept in one place so the UI, BUILD_NOTES
/// and the report all say the same thing).
String sheetsSetupSteps(String packageName, String sha1) => '''
Google Sheets sync needs a one-time Google Cloud setup (the app cannot do this itself):

1. Google Cloud Console -> the project that owns the sheet -> APIs & Services -> Library -> enable "Google Sheets API".
2. APIs & Services -> Credentials -> Create Credentials -> OAuth client ID -> Application type: Android.
   Package name: $packageName
   SHA-1 certificate fingerprint: $sha1
   (This is the app's persistent debug keystore — the same fingerprint the APK is signed with.)
3. Download the google-services.json for that Android client and put it in android/app/ in this project, then rebuild the APK.
4. Open the spreadsheet and make sure the Google account you sign in with can edit it (it must own the sheet or be shared on it).
5. In the app: Settings -> Google Sheets -> paste the spreadsheet ID (the long ID in the sheet's URL) -> Sign in with Google -> Sync now.
''';

/// The tab the app writes to. The spreadsheet ID is separate (pasted
/// in Settings) — this is only the tab name inside that spreadsheet.
const sheetsTabName = 'vlesslist';

/// The only scope the sync needs (read/write this user's sheets).
const sheetsScope = 'https://www.googleapis.com/auth/spreadsheets';

/// Build the values matrix: header + one row per client.
/// All dates are ISO `yyyy-MM-dd` (or blank); numbers are plain
/// numbers so Sheets treats them as values, not text.
List<List<Object>> buildSheetRows(List<ClientInfo> clients) {
  final rows = <List<Object>>[
    const [
      'Name',
      'Inbound',
      'Status',
      'Used GB',
      'Quota GB',
      'Used %',
      'Expiry',
      'Days left',
    ],
  ];
  for (final c in clients) {
    rows.add([
      c.email,
      c.inbound,
      c.enabled ? (c.isExpired ? 'Expired' : 'Enabled') : 'Disabled',
      double.parse(c.usedGb.toStringAsFixed(2)),
      c.isUnlimited ? 'Unlimited' : double.parse(c.quotaGb.toStringAsFixed(2)),
      c.usedPct == null
          ? '—'
          : double.parse((c.usedPct! * 100).toStringAsFixed(1)),
      c.expiry == null ? '' : formatDate(c.expiry!),
      c.daysToExpiry?.toString() ?? '',
    ]);
  }
  return rows;
}

/// Pull a spreadsheet ID out of a full sheet URL or a bare ID.
/// `https://docs.google.com/spreadsheets/d/<ID>/edit...` -> `<ID>`.
String parseSpreadsheetId(String raw) {
  final input = raw.trim();
  final match = RegExp(r'/spreadsheets/d/([a-zA-Z0-9_-]+)').firstMatch(input);
  if (match != null) return match.group(1)!;
  return input;
}

class SheetsSyncService {
  SheetsSyncService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Write the whole client table to `vlesslist` (starting at A1).
  /// Returns (ok, message).
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
    final rows = buildSheetRows(clients);
    final range = '$sheetsTabName!A1:H${rows.length}';
    final uri = Uri.parse(
      'https://sheets.googleapis.com/v4/spreadsheets/$id/values/$range'
      '?valueInputOption=USER_ENTERED',
    );
    late http.Response res;
    try {
      res = await _client
          .put(
            uri,
            headers: {
              'Authorization': 'Bearer $accessToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'range': range,
              'majorDimension': 'ROWS',
              'values': rows,
            }),
          )
          .timeout(const Duration(seconds: 30));
    } on Exception catch (e) {
      return (false, 'Could not reach Google Sheets: $e');
    }
    if (res.statusCode == 401) {
      return (
        false,
        'Google rejected the sign-in (401). Sign out and sign in again.',
      );
    }
    if (res.statusCode == 404) {
      return (
        false,
        'Spreadsheet or the `$sheetsTabName` tab was not found (404). '
            'Check the spreadsheet ID and that the tab exists.',
      );
    }
    if (res.statusCode != 200) {
      return (false, 'Sheets answered HTTP ${res.statusCode}: ${res.body}');
    }
    return (
      true,
      'Synced ${clients.length} clients to `$sheetsTabName` '
          '(${rows.length} rows incl. header).',
    );
  }
}

/// Google Sign-In wrapper: initialise once, authenticate, authorise
/// the Sheets scope, return the access token. Any failure before a
/// token exists is reported as [SheetsSetupNeeded] with the steps —
/// the OAuth client / google-services.json setup is a user step.
class GoogleSignInService {
  GoogleSignInService({this.packageName = 'com.ngy.mistyroutemanager'});

  final String packageName;

  /// SHA-1 of ~/workspace/tools/android-debug.keystore (the keystore
  /// the release APK is signed with — stable across rebuilds).
  static const apkSha1 =
      '2A:F2:AC:97:7F:A8:9D:3C:01:9F:A7:61:BB:63:B4:4D:55:CF:CC:C6';

  bool _initialised = false;

  Future<String> signInAndGetAccessToken() async {
    try {
      if (!_initialised) {
        await GoogleSignIn.instance.initialize();
        _initialised = true;
      }
      final account = await GoogleSignIn.instance.authenticate();
      final authz = await account.authorizationClient.authorizeScopes([
        sheetsScope,
      ]);
      return authz.accessToken;
    } on SheetsSetupNeeded {
      rethrow;
    } on Exception {
      throw SheetsSetupNeeded(sheetsSetupSteps(packageName, apkSha1));
    }
  }
}
