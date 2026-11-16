// Smoke test: the app boots into the dashboard with clearly-labelled
// demo data (no panel credentials configured).
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mistyroutemanager/main.dart';
import 'package:mistyroutemanager/services/panel_provider.dart';

void main() {
  // The Setup tab loads the app's SSH keypair from secure storage on
  // start; there is no secure-storage plugin in the test env, so the
  // channel is mocked (read -> null, write -> ok) and key generation
  // (pure Dart) runs for real.
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
  });

  testWidgets('Dashboard shows demo data with 24 sample clients',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    // Tall viewport so the header cards, flags row and the first
    // client tiles are all built without scrolling.
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final provider = PanelProvider();
    await provider.init();

    await tester.pumpWidget(MistyRouteApp(provider: provider));
    await tester.pumpAndSettle();

    expect(find.text('MistyRoute Manager'), findsWidgets);
    expect(find.text('DEMO DATA'), findsOneWidget);
    expect(find.text('24 clients'), findsOneWidget);
    // Three tabs in v0.2: Dashboard, Setup, Settings.
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Setup'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('v0.2.0'), findsOneWidget);
    // Flags row counts (checked before scrolling, while still on screen).
    expect(find.text('≥80% quota (3)'), findsOneWidget);
    expect(find.text('Expiring ≤7d (3)'), findsOneWidget);
    expect(find.text('Disabled (2)'), findsOneWidget);
    // Highest-usage demo client renders first (sorted by usage desc).
    expect(find.text('Demo User 10'), findsOneWidget);
  });
}
