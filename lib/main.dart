/// MistyRoute Manager v0.2.0 — 3x-ui panel management.
///
/// Dashboard (bandwidth monitor + user list + write actions), Setup
/// (SSH one-tap tunnel actions, mobile only) and Settings (panel URL +
/// API token, demo-data toggle, Google Sheets sync).
/// Live data comes from the panel API (GET panel/api/inbounds/list +
/// panel/api/server/status, Bearer token); without credentials the app
/// shows clearly-labelled demo data.
library;

import 'package:flutter/material.dart';

import 'screens/dashboard_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/setup_screen.dart';
import 'services/panel_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final provider = PanelProvider();
  await provider.init();
  runApp(MistyRouteApp(provider: provider));
}

class MistyRouteApp extends StatelessWidget {
  const MistyRouteApp({required this.provider, super.key});

  final PanelProvider provider;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MistyRoute Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: MainScreen(provider: provider),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({required this.provider, super.key});

  final PanelProvider provider;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MistyRoute Manager'),
        actions: [
          ListenableBuilder(
            listenable: widget.provider,
            builder: (context, _) {
              return const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Center(
                  child: Text('v0.2.0'),
                ),
              );
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          DashboardScreen(provider: widget.provider),
          SetupScreen(provider: widget.provider),
          SettingsScreen(provider: widget.provider),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.terminal_outlined),
            selectedIcon: Icon(Icons.terminal),
            label: 'Setup',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
