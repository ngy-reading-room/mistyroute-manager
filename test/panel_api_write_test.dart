// Unit tests for the panel write API: request paths, bodies and
// envelope handling, against a fake HTTP client (no live panel).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mistyroutemanager/services/panel_api.dart';

const _base = 'https://panel.example/MjfgiJflHcfijX4TYv/';
const _token = 'test-token';

Map<String, dynamic> _envelope(Object obj) =>
    {'success': true, 'msg': '', 'obj': obj};

void main() {
  group('PanelApiService write path', () {
    test('addClient posts the create payload to /clients/add', () async {
      late http.Request captured;
      final api = PanelApiService(
        client: MockClient((request) async {
          captured = request;
          return http.Response(jsonEncode(_envelope({})), 200);
        }),
      );
      final payload = {
        'client': {'email': 'X_16.11.26-16.2.27', 'totalGB': 50},
        'inboundIds': [1],
      };
      await api.addClient(baseUrl: _base, token: _token, payload: payload);
      expect(captured.url.path, '/MjfgiJflHcfijX4TYv/panel/api/clients/add');
      expect(captured.headers['Authorization'], 'Bearer $_token');
      expect(jsonDecode(captured.body), payload);
    });

    test('updateClient posts the raw client JSON to /clients/update/:email',
        () async {
      late http.Request captured;
      final api = PanelApiService(
        client: MockClient((request) async {
          captured = request;
          return http.Response(jsonEncode(_envelope({})), 200);
        }),
      );
      final body = {
        'id': 'some-uuid',
        'email': 'X_16.11.26-16.2.27',
        'totalGB': 91,
        'enable': true,
      };
      await api.updateClient(
        baseUrl: _base,
        token: _token,
        email: 'X_15.8.26-15.11.26',
        clientJson: body,
      );
      expect(
        captured.url.path,
        '/MjfgiJflHcfijX4TYv/panel/api/clients/update/X_15.8.26-15.11.26',
      );
      expect(jsonDecode(captured.body), body);
    });

    test('deleteClient posts to /clients/del/:email with keepTraffic=0',
        () async {
      late http.Request captured;
      final api = PanelApiService(
        client: MockClient((request) async {
          captured = request;
          return http.Response(jsonEncode(_envelope({})), 200);
        }),
      );
      await api.deleteClient(baseUrl: _base, token: _token, email: 'X');
      expect(
        captured.url.toString(),
        '${_base}panel/api/clients/del/X?keepTraffic=0',
      );
    });

    test('resetClientTraffic posts to /clients/resetTraffic/:email',
        () async {
      late http.Request captured;
      final api = PanelApiService(
        client: MockClient((request) async {
          captured = request;
          return http.Response(jsonEncode(_envelope({})), 200);
        }),
      );
      await api.resetClientTraffic(baseUrl: _base, token: _token, email: 'X');
      expect(
        captured.url.path,
        '/MjfgiJflHcfijX4TYv/panel/api/clients/resetTraffic/X',
      );
    });

    test('fetchClientRecord parses the record from the envelope',
        () async {
      final api = PanelApiService(
        client: MockClient((request) async {
          return http.Response(
            jsonEncode(_envelope({
              'client': {
                'id': 7,
                'email': 'X_15.8.26-15.11.26',
                'subId': 'X',
                'uuid': 'uuid-123',
                'flow': 'xtls-rprx-vision',
                'limitIp': 1,
                'totalGB': 50,
                'expiryTime': 1794000000000,
                'enable': true,
                'tgId': 0,
                'comment': '',
                'reset': 0,
              },
              'inboundIds': [1],
            })),
            200,
          );
        }),
      );
      final record = await api.fetchClientRecord(
        baseUrl: _base,
        token: _token,
        email: 'X_15.8.26-15.11.26',
      );
      expect(record.uuid, 'uuid-123');
      expect(record.subId, 'X');
      expect(record.totalGb, 50);
      // The update body carries the UUID as `id` and preserves the rest.
      final body = record.toClientJson(totalGb: 91);
      expect(body['id'], 'uuid-123');
      expect(body['totalGB'], 91);
      expect(body['email'], 'X_15.8.26-15.11.26');
      expect(body['flow'], 'xtls-rprx-vision');
    });

    test('a failed envelope throws PanelApiException', () async {
      final api = PanelApiService(
        client: MockClient((request) async {
          return http.Response(
            jsonEncode({'success': false, 'msg': 'no such client'}),
            200,
          );
        }),
      );
      expect(
        () => api.resetClientTraffic(baseUrl: _base, token: _token, email: 'X'),
        throwsA(isA<PanelApiException>()),
      );
    });

    test('401 throws with a token hint', () async {
      final api = PanelApiService(
        client: MockClient((request) async => http.Response('no', 401)),
      );
      try {
        await api.resetClientTraffic(baseUrl: _base, token: _token, email: 'X');
        fail('should have thrown');
      } on PanelApiException catch (e) {
        expect(e.message, contains('401'));
      }
    });
  });
}
