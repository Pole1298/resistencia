import 'package:flutter/material.dart';

import '../home/app_shell.dart';

class AppShellBridge extends StatelessWidget {
  final bool isAdmin;
  final String myPhone;

  const AppShellBridge({
    super.key,
    required this.isAdmin,
    required this.myPhone,
  });

  @override
  Widget build(BuildContext context) {
    return AppShell(
      isAdmin: isAdmin,
      myPhone: myPhone,
    );
  }
}
