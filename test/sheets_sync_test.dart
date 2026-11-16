// Unit tests for the Sheets sync (v0.2.2): the A–F `vlesslist`
// mapping, in-place merge + append, the panel-date safeguard, and
// the REST read/write — all against a fake HTTP client (no Google
// account needed, and the real spreadsheet is never touched).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mistyroutemanager/models/panel_models.dart';
import 'package:mistyroutemanager/services/sheets_sync_service.dart';

ClientInfo _client({
  required String email,
  required String subId,
  required int quotaGb,
  required int usedGb,
  required DateTime expiry, // local date; use DateTime(0) for none
  String group = '',
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
    expiryTimeMs:
        expiry == DateTime(0) ? 0 : expiry.millisecondsSinceEpoch,
    group: group,
    subId: subId,
  );
}

void main() {
  group('sheetExpireDate', () {
    test('remark end as ISO, panel date for ZZWO, ∞ for no expiry', () {
      expect(
        sheetExpireDate(
          _client(
            email: 'MaMar_3.11.26-3.12.26',
            subId: 'MaMar',
            quotaGb: 50,
            usedGb: 10,
            expiry: DateTime(2026, 12, 4),
          ),
        ),
        '2026-12-03',
      );
      // ZZWO: remark says Feb 16, panel expiry Jan 16 — panel wins.
      expect(
        sheetExpireDate(
          _client(
            email: 'ZZWO_16.2.27',
            subId: 'ZZWO',
            quotaGb: 100,
            usedGb: 0,
            expiry: DateTime(2027, 1, 16, 23, 59),
          ),
        ),
        '2027-01-16',
      );
      expect(
        sheetExpireDate(
          _client(
            email: 'bigsun',
            subId: 'bigsun',
            quotaGb: 0,
            usedGb: 40,
            expiry: DateTime(0),
          ),
        ),
        '∞',
      );
    });
  });

  group('parseSheetDate', () {
    test('ISO and D-M-YY display forms, ∞ and junk are null', () {
      expect(parseSheetDate('2027-01-16'), DateTime(2027, 1, 16));
      expect(parseSheetDate('15-11-26'), DateTime(2026, 11, 15));
      expect(parseSheetDate('3-12-26'), DateTime(2026, 12, 3));
      expect(parseSheetDate('30-10-26'), DateTime(2026, 10, 30));
      expect(parseSheetDate('∞'), isNull);
      expect(parseSheetDate(''), isNull);
      expect(parseSheetDate('not a date'), isNull);
    });
  });

  group('buildSheetRow', () {
    test('A–F mapping with the real subId and fresh config', () {
      final row = buildSheetRow(
        _client(
          email: 'EiKay15.10.26-15.11.26',
          subId: '8pt4xbd1kpors3rv',
          quotaGb: 67,
          usedGb: 5,
          expiry: DateTime(2026, 11, 15),
          group: 'MNA',
        ),
        freshConfig: 'vless://uuid@host:443?x=1#frag',
      );
      expect(row, [
        'EiKay',
        'https://ngylab.cloud-ip.cc:2096/ngylab_sub/8pt4xbd1kpors3rv',
        'vless://uuid@host:443?x=1#frag',
        '2026-11-15',
        'MNA',
        'EiKay15.10.26-15.11.26',
      ]);
    });

    test('failed config fetch keeps the existing Config cell', () {
      final row = buildSheetRow(
        _client(
          email: 'MaNwe22.11.26',
          subId: 'MaNwe',
          quotaGb: 160,
          usedGb: 130,
          expiry: DateTime(2026, 11, 22, 23, 59),
          group: 'MayZin',
        ),
        existingRow: [
          'MaNwe',
          'https://ngylab.cloud-ip.cc:2096/ngylab_sub/MaNwe',
          'vless://old-link',
          '22-11-26',
          'MayZin',
          'MaNwe22.11.26',
        ],
      );
      expect(row[2], 'vless://old-link');
      expect(row[3], '2026-11-22');
    });

    test('panel-date safeguard keeps the sheet date for MTTM', () {
      // Computed end is Oct 29 (remark), but the sheet holds
      // Oct 30, which equals the panel expiry date — keep it.
      final row = buildSheetRow(
        _client(
          email: 'MTTM29.10.26',
          subId: 'MaTTM29.9.2529.10.26',
          quotaGb: 0,
          usedGb: 0,
          expiry: DateTime(2026, 10, 30),
          group: 'MNA',
        ),
        existingRow: [
          'MTTM',
          'https://ngylab.cloud-ip.cc:2096/ngylab_sub/MaTTM29.9.2529.10.26',
          'vless://old-link',
          '30-10-26',
          'MNA',
          'MTTM29.10.26',
        ],
      );
      expect(row[3], '2026-10-30');
    });
  });

  group('mergeSheetRows', () {
    final existing = [
      ['Name', 'Subscription URL', 'Config', 'Expire Date', 'Group', 'Remark'],
      [
        'MaNwe',
        'https://ngylab.cloud-ip.cc:2096/ngylab_sub/MaNwe',
        'vless://old-nwe',
        '22-11-26',
        'MayZin',
        'MaNwe22.11.26',
      ],
      [
        'MTTM',
        'https://ngylab.cloud-ip.cc:2096/ngylab_sub/MaTTM29.9.2529.10.26',
        'vless://old-mttm',
        '30-10-26',
        'MNA',
        'MTTM29.10.26',
      ],
      [
        'OldClient',
        'https://ngylab.cloud-ip.cc:2096/ngylab_sub/OldClient',
        'vless://old-gone',
        '1-1-26',
        'MNA',
        'OldClient',
      ],
    ];

    test('updates in place, appends new, keeps orphans and order', () {
      final merge = mergeSheetRows(
        existing: existing,
        clients: [
          _client(
            email: 'MaNwe22.11.26',
            subId: 'MaNwe',
            quotaGb: 160,
            usedGb: 130,
            expiry: DateTime(2026, 11, 22, 23, 59),
            group: 'MayZin',
          ),
          _client(
            email: 'MTTM29.10.26',
            subId: 'MaTTM29.9.2529.10.26',
            quotaGb: 0,
            usedGb: 0,
            expiry: DateTime(2026, 10, 30),
            group: 'MNA',
          ),
          _client(
            email: 'ZZWO_16.2.27',
            subId: 'ZZWO',
            quotaGb: 100,
            usedGb: 0,
            expiry: DateTime(2027, 1, 16, 23, 59),
            group: 'MNA',
          ),
        ],
        freshConfigs: {'MaNwe22.11.26': 'vless://fresh-nwe'},
      );
      expect(merge.updated, 2);
      expect(merge.appended, 1);
      expect(merge.orphans, 1); // OldClient row kept
      expect(merge.rows.length, 5);
      // Row order kept: MaNwe still row 2, MTTM row 3, orphan row 4,
      // ZZWO appended as row 5.
      expect(merge.rows[1][0], 'MaNwe');
      expect(merge.rows[1][2], 'vless://fresh-nwe');
      expect(merge.rows[1][3], '2026-11-22');
      expect(merge.rows[2][0], 'MTTM');
      expect(merge.rows[2][2], 'vless://old-mttm');
      expect(merge.rows[2][3], '2026-10-30'); // safeguard kept
      expect(merge.rows[3][0], 'OldClient');
      expect(merge.rows[4][0], 'ZZWO');
      expect(merge.rows[4][1],
          'https://ngylab.cloud-ip.cc:2096/ngylab_sub/ZZWO');
      expect(merge.rows[4][3], '2027-01-16');
      expect(merge.keptPanelDates, ['MTTM']);
    });

    test('empty sheet starts with the header only', () {
      final merge = mergeSheetRows(
        existing: [],
        clients: [
          _client(
            email: 'A_1.1.26-1.4.26',
            subId: 'A',
            quotaGb: 50,
            usedGb: 10,
            expiry: DateTime(2026, 4, 1),
          ),
        ],
        freshConfigs: {},
      );
      expect(merge.rows.first, sheetHeader);
      expect(merge.rows.length, 2);
      expect(merge.appended, 1);
    });

    test('ragged rows (trailing empties omitted by the API) are padded', () {
      final merge = mergeSheetRows(
        existing: [
          ['Name', 'Subscription URL', 'Config', 'Expire Date', 'Group', 'Remark'],
          ['A', 'https://ngylab.cloud-ip.cc:2096/ngylab_sub/A'],
        ],
        clients: [
          _client(
            email: 'A_1.1.26-1.4.26',
            subId: 'A',
            quotaGb: 50,
            usedGb: 10,
            expiry: DateTime(2026, 4, 1),
            group: 'MNA',
          ),
        ],
        freshConfigs: {},
      );
      expect(merge.updated, 1);
      expect(merge.rows[1].length, 6);
      expect(merge.rows[1], [
        'A',
        'https://ngylab.cloud-ip.cc:2096/ngylab_sub/A',
        '',
        '2026-04-01',
        'MNA',
        'A_1.1.26-1.4.26',
      ]);
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
    test('reads first, then PUTs the merged matrix to Sheet1', () async {
      final existing = {
        'values': [
          ['Name', 'Subscription URL', 'Config', 'Expire Date', 'Group', 'Remark'],
          [
            'A',
            'https://ngylab.cloud-ip.cc:2096/ngylab_sub/A',
            'vless://old-a',
            '2026-04-01',
            'MNA',
            'A_1.1.26-1.4.26',
          ],
        ],
      };
      http.Request? putRequest;
      final service = SheetsSyncService(
        client: MockClient((request) async {
          if (request.url.host == 'sheets.googleapis.com' &&
              request.method == 'GET') {
            return http.Response(jsonEncode(existing), 200);
          }
          if (request.url.host == 'ngylab.cloud-ip.cc') {
            // Sub URL returns base64 of a vless link.
            final link = 'vless://fresh-a@168.144.250.99:443?x=1#A';
            return http.Response(base64Encode(utf8.encode(link)), 200);
          }
          putRequest = request;
          return http.Response(jsonEncode({'updatedCells': 12}), 200);
        }),
      );
      final (ok, msg) = await service.sync(
        accessToken: 'ya29.test',
        spreadsheetId: 'sheet-id-1',
        clients: [
          _client(
            email: 'A_1.1.26-1.4.26',
            subId: 'A',
            quotaGb: 50,
            usedGb: 10,
            expiry: DateTime(2026, 4, 1),
            group: 'MNA',
          ),
        ],
      );
      expect(ok, true);
      expect(msg, contains('1 clients'));
      expect(msg, contains('1 updated'));
      expect(putRequest, isNotNull);
      expect(putRequest!.method, 'PUT');
      expect(
        putRequest!.url.path,
        '/v4/spreadsheets/sheet-id-1/values/Sheet1!A1:F2',
      );
      expect(putRequest!.url.queryParameters['valueInputOption'],
          'USER_ENTERED');
      expect(putRequest!.headers['Authorization'], 'Bearer ya29.test');
      final body = jsonDecode(putRequest!.body) as Map<String, dynamic>;
      expect(body['range'], 'Sheet1!A1:F2');
      final values = body['values'] as List;
      expect(values.length, 2);
      expect(values[1][2], 'vless://fresh-a@168.144.250.99:443?x=1#A');
      expect(values[1][3], '2026-04-01');
    });

    test('failed config fetch keeps the old link and says so', () async {
      final existing = {
        'values': [
          ['Name', 'Subscription URL', 'Config', 'Expire Date', 'Group', 'Remark'],
          [
            'A',
            'https://ngylab.cloud-ip.cc:2096/ngylab_sub/A',
            'vless://old-a',
            '2026-04-01',
            'MNA',
            'A_1.1.26-1.4.26',
          ],
        ],
      };
      String? writtenConfig;
      final service = SheetsSyncService(
        client: MockClient((request) async {
          if (request.url.host == 'sheets.googleapis.com' &&
              request.method == 'GET') {
            return http.Response(jsonEncode(existing), 200);
          }
          if (request.url.host == 'ngylab.cloud-ip.cc') {
            return http.Response('not found', 404);
          }
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          writtenConfig = (body['values'] as List)[1][2] as String;
          return http.Response(jsonEncode({'updatedCells': 12}), 200);
        }),
      );
      final (ok, msg) = await service.sync(
        accessToken: 'ya29.test',
        spreadsheetId: 'sheet-id-1',
        clients: [
          _client(
            email: 'A_1.1.26-1.4.26',
            subId: 'A',
            quotaGb: 50,
            usedGb: 10,
            expiry: DateTime(2026, 4, 1),
            group: 'MNA',
          ),
        ],
      );
      expect(ok, true);
      expect(writtenConfig, 'vless://old-a');
      expect(msg, contains('could not be fetched'));
    });

    test('read 404 explains the missing spreadsheet/tab', () async {
      final service = SheetsSyncService(
        client: MockClient((request) async => http.Response('not found', 404)),
      );
      final (ok, msg) = await service.sync(
        accessToken: 'ya29.test',
        spreadsheetId: 'bad-id',
        clients: [
          _client(
            email: 'A',
            subId: 'A',
            quotaGb: 50,
            usedGb: 1,
            expiry: DateTime(2026, 4, 1),
          ),
        ],
      );
      expect(ok, false);
      expect(msg, contains('404'));
    });

    test('content beyond column F aborts without writing', () async {
      var putCalled = false;
      final service = SheetsSyncService(
        client: MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response(
              jsonEncode({
                'values': [
                  ['Name', 'A', 'B', 'C', 'D', 'E', 'EXTRA'],
                ],
              }),
              200,
            );
          }
          putCalled = true;
          return http.Response('{}', 200);
        }),
      );
      final (ok, msg) = await service.sync(
        accessToken: 'ya29.test',
        spreadsheetId: 'sheet-id-1',
        clients: [
          _client(
            email: 'A',
            subId: 'A',
            quotaGb: 50,
            usedGb: 1,
            expiry: DateTime(2026, 4, 1),
          ),
        ],
      );
      expect(ok, false);
      expect(msg, contains('beyond column F'));
      expect(putCalled, false);
    });
  });
}
