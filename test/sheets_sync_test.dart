// Unit tests for the Sheets sync: row building (ISO dates) and the
// REST write, against a fake HTTP client (no Google account needed).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mistyroutemanager/models/panel_models.dart';
import 'package:mistyroutemanager/services/sheets_sync_service.dart';

ClientInfo _client({
  required String email,
  required int quotaGb,
  required int usedGb,
  required int daysToExpiry,
  bool enabled = true,
}) {
  const gb = 1024 * 1024 * 1024;
  return ClientInfo(
    email: email,
    inbound: 'VLESS Reality',
    enabled: enabled,
    upBytes: (usedGb * gb * 0.3).round(),
    downBytes: (usedGb * gb * 0.7).round(),
    quotaBytes: quotaGb * gb,
    expiryTimeMs: daysToExpiry > 9000
        ? 0
        : DateTime.now().add(Duration(days: daysToExpiry))
            .millisecondsSinceEpoch,
  );
}

void main() {
  group('buildSheetRows', () {
    test('header + ISO dates, never D.M.YY', () {
      final rows = buildSheetRows([
        _client(email: 'A_1.1.26-1.4.26', quotaGb: 50, usedGb: 10, daysToExpiry: 30),
        _client(email: 'B', quotaGb: 0, usedGb: 5, daysToExpiry: 99999, enabled: false),
      ]);
      expect(rows.first, [
        'Name', 'Inbound', 'Status', 'Used GB', 'Quota GB', 'Used %',
        'Expiry', 'Days left',
      ]);
      expect(rows[1][0], 'A_1.1.26-1.4.26');
      // Expiry is ISO yyyy-MM-dd, not the remark's D.M.YY.
      expect(rows[1][6] as String, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
      expect(rows[1][4], 50);
      expect(rows[1][3], 10.0);
      // Unlimited quota renders as text, not a number.
      expect(rows[2][4], 'Unlimited');
      expect(rows[2][2], 'Disabled');
      expect(rows[2][6], '');
    });
  });

  group('parseSpreadsheetId', () {
    test('extracts the ID from a full sheet URL', () {
      expect(
        parseSpreadsheetId(
          'https://docs.google.com/spreadsheets/d/abcDEF123_-/edit#gid=0',
        ),
        'abcDEF123_-',
      );
      expect(parseSpreadsheetId('abcDEF123_-'), 'abcDEF123_-');
    });
  });

  group('SheetsSyncService.sync', () {
    test('PUTs the values matrix to the vlesslist tab', () async {
      late http.Request captured;
      final service = SheetsSyncService(
        client: MockClient((request) async {
          captured = request;
          return http.Response(jsonEncode({'updatedCells': 18}), 200);
        }),
      );
      final (ok, msg) = await service.sync(
        accessToken: 'ya29.test',
        spreadsheetId: 'sheet-id-1',
        clients: [
          _client(email: 'A', quotaGb: 50, usedGb: 10, daysToExpiry: 30),
        ],
      );
      expect(ok, true);
      expect(msg, contains('1 clients'));
      expect(captured.method, 'PUT');
      expect(
        captured.url.path,
        '/v4/spreadsheets/sheet-id-1/values/vlesslist!A1:H2',
      );
      expect(captured.url.queryParameters['valueInputOption'], 'USER_ENTERED');
      expect(captured.headers['Authorization'], 'Bearer ya29.test');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['range'], 'vlesslist!A1:H2');
      expect((body['values'] as List).length, 2);
    });

    test('404 explains the missing spreadsheet/tab', () async {
      final service = SheetsSyncService(
        client: MockClient((request) async => http.Response('not found', 404)),
      );
      final (ok, msg) = await service.sync(
        accessToken: 'ya29.test',
        spreadsheetId: 'bad-id',
        clients: [_client(email: 'A', quotaGb: 50, usedGb: 1, daysToExpiry: 5)],
      );
      expect(ok, false);
      expect(msg, contains('404'));
    });
  });
}
