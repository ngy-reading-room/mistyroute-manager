// Unit + widget tests for the per-client copyable links (v0.2.3):
// the shared sub-URL builder, the shared config fetch/decode path,
// the demo-mode guard (no live fetch from sample data), and the
// Links card on the detail screen. All HTTP is faked; the real
// panel and the real sheet are never touched.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mistyroutemanager/models/panel_models.dart';
import 'package:mistyroutemanager/screens/client_detail_screen.dart';
import 'package:mistyroutemanager/services/panel_provider.dart';
import 'package:mistyroutemanager/services/sheets_sync_service.dart';

ClientInfo _client({required String email, String subId = ''}) {
  return ClientInfo(
    email: email,
    inbound: 'VLESS Reality',
    enabled: true,
    upBytes: 100,
    downBytes: 200,
    quotaBytes: 10 * 1024 * 1024 * 1024,
    expiryTimeMs: DateTime(2026, 12, 3).millisecondsSinceEpoch,
    subId: subId,
  );
}

void main() {
  group('subUrlFor / subIdFromUrl', () {
    test('builds the ngylab.cloud-ip.cc:2096 form', () {
      expect(
        subUrlFor('MaMee'),
        'https://ngylab.cloud-ip.cc:2096/ngylab_sub/MaMee',
      );
    });

    test('keeps the panel\'s real (mangled) subId', () {
      expect(
        subUrlFor('8pt4xbd1kpors3rv'),
        'https://ngylab.cloud-ip.cc:2096/ngylab_sub/8pt4xbd1kpors3rv',
      );
    });

    test('never uses the trycloudflare tunnel hostname', () {
      expect(subUrlFor('ZZWO'), isNot(contains('trycloudflare')));
    });

    test('subIdFromUrl round-trips and rejects other URLs', () {
      expect(subIdFromUrl(subUrlFor('MaMee')), 'MaMee');
      expect(subIdFromUrl('https://example.com/x'), isNull);
      expect(
        subIdFromUrl('https://ngylab.cloud-ip.cc:2096/ngylab_sub/'),
        isNull,
      );
    });
  });

  group('subIdForClient', () {
    test('record subId wins over the remark name', () {
      expect(
        subIdForClient(
          _client(
            email: 'EiKay_15.10.26-15.11.26',
            subId: '8pt4xbd1kpors3rv',
          ),
        ),
        '8pt4xbd1kpors3rv',
      );
    });

    test('falls back to the clean remark name when no subId', () {
      expect(
        subIdForClient(_client(email: 'MaMee_3.11.26-3.12.26')),
        'MaMee',
      );
    });
  });

  group('sampleVlessLink', () {
    test('clearly-marked sample, never a real link', () {
      final link =
          sampleVlessLink(_client(email: 'MaMee_3.11.26-3.12.26'));
      expect(link, startsWith('vless://'));
      expect(link, contains('demo.invalid'));
      expect(link, contains('#Demo-MaMee'));
      expect(link, isNot(contains('ngylab.cloud-ip.cc')));
      expect(link, isNot(contains('168.144.250.99')));
    });
  });

  group('SheetsSyncService.fetchFreshConfig', () {
    test('base64 body decodes to the vless link', () async {
      const link = 'vless://abc@168.144.250.99:443?x=1#MaMee';
      final service = SheetsSyncService(
        client: MockClient(
          (_) async => http.Response(base64Encode(utf8.encode(link)), 200),
        ),
      );
      expect(await service.fetchFreshConfig('MaMee'), link);
    });

    test('plain vless:// body returns its first line', () async {
      final service = SheetsSyncService(
        client: MockClient(
          (_) async => http.Response(
            'vless://plain@host:443?x=1#X\nvless://second@host:443#Y',
            200,
          ),
        ),
      );
      expect(
        await service.fetchFreshConfig('X'),
        'vless://plain@host:443?x=1#X',
      );
    });

    test('non-200, garbage and empty bodies are null', () async {
      final notFound = SheetsSyncService(
        client: MockClient((_) async => http.Response('nope', 404)),
      );
      expect(await notFound.fetchFreshConfig('X'), isNull);
      final garbage = SheetsSyncService(
        client: MockClient(
          (_) async =>
              http.Response(base64Encode(utf8.encode('hello world')), 200),
        ),
      );
      expect(await garbage.fetchFreshConfig('X'), isNull);
    });
  });

  group('PanelProvider.fetchClientConfig', () {
    test('demo mode returns null without any HTTP call', () async {
      var called = false;
      final provider = PanelProvider(
        sheets: SheetsSyncService(
          client: MockClient((_) async {
            called = true;
            return http.Response('', 500);
          }),
        ),
      );
      expect(provider.showingDemo, true);
      expect(
        await provider.fetchClientConfig(
          _client(email: 'MaMee_3.11.26-3.12.26', subId: 'MaMee'),
        ),
        isNull,
      );
      expect(called, false);
    });
  });

  group('ClientDetailScreen Links card (demo mode)', () {
    testWidgets('shows Sub URL + sample link with Copy buttons',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      // Clipboard.setData has no plugin in the test env.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => null,
      );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding
            .instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      final provider = PanelProvider();
      await provider.init();
      final client = provider.data!.clients.first;

      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: ClientDetailScreen(client: client, provider: provider),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Links'), findsOneWidget);
      expect(
        find.textContaining('ngylab.cloud-ip.cc:2096/ngylab_sub/'),
        findsOneWidget,
      );
      expect(find.textContaining('demo.invalid'), findsOneWidget);
      expect(find.text('VLESS link (sample — demo mode)'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Copy'), findsNWidgets(2));

      // Tapping Copy shows the confirmation.
      await tester.tap(find.widgetWithText(FilledButton, 'Copy').first);
      await tester.pump();
      expect(find.text('Subscription URL copied.'), findsOneWidget);
    });
  });
}
