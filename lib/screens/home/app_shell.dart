import 'package:flutter/material.dart';

import '../admin/admin_panel_screen.dart';
import '../auth/firestore_access_gate.dart';
import '../auxilio/auxilio_screen.dart';
import '../more/more_screen.dart';
import '../reportes/reportes_list_screen.dart';
import 'home_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.isAdmin,
    required this.myPhone,
  });

  final bool isAdmin;
  final String myPhone;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  void _openTab(int index) {
    if (!mounted) return;
    setState(() => _index = index);
  }

  Future<void> _openAdmin() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminPanelScreen(myPhone: widget.myPhone),
      ),
    );
  }

  Future<void> _logout() async {
    await Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const FirestoreAccessGate()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomeScreen(
        myPhone: widget.myPhone,
        isAdmin: widget.isAdmin,
        onOpenTab: _openTab,
      ),
      ReportesListScreen(myPhone: widget.myPhone),
      AuxilioScreen(myPhone: widget.myPhone),
      MoreScreen(
        myPhone: widget.myPhone,
        isAdmin: widget.isAdmin,
        onOpenAdmin: _openAdmin,
        onLogout: _logout,
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _openTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Inicio',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_location_alt_outlined),
            selectedIcon: Icon(Icons.add_location_alt_rounded),
            label: 'Reportar',
          ),
          NavigationDestination(
            icon: Icon(Icons.sos_outlined),
            selectedIcon: Icon(Icons.sos_rounded),
            label: 'Auxilio',
          ),
          NavigationDestination(
            icon: Icon(Icons.more_horiz_rounded),
            selectedIcon: Icon(Icons.menu_rounded),
            label: 'Más',
          ),
        ],
      ),
    );
  }
}
