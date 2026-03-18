import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_constants.dart';
import '../../services/auth_service.dart';
import '../../widgets/info_card.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({
    super.key,
    required this.myPhone,
    required this.isAdmin,
    required this.onOpenAdmin,
    required this.onLogout,
  });

  final String myPhone;
  final bool isAdmin;
  final Future<void> Function() onOpenAdmin;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    final effectiveAdmin = isAdmin || myPhone == AppConstants.founderPhone;

    return Scaffold(
      appBar: AppBar(title: const Text('Más')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const InfoCard(
            title: 'Información',
            subtitle: 'Base profesional de Resistencia',
            child: Text('Esta versión reorganiza acceso, usuarios, reportes, auxilio y administración con una interfaz más clara, sin valores fijos y con mejor control de roles.'),
          ),
          const SizedBox(height: 16),
          if (effectiveAdmin) ...[
            InfoCard(
              title: 'Panel de administración',
              subtitle: 'Configuración y control',
              trailing: const Icon(Icons.admin_panel_settings_rounded),
              onTap: onOpenAdmin,
              child: const Text('Administrá whitelist, permisos, configuración general y revisá fichas rápidas de usuarios.'),
            ),
            const SizedBox(height: 16),
          ],
          InfoCard(
            title: 'Compartir app',
            subtitle: 'Invitar a conocer Resistencia',
            trailing: const Icon(Icons.share_rounded),
            onTap: () => Share.share('Estoy usando Resistencia. Plataforma privada de reportes y auxilio.'),
            child: const Text('Compartí la idea de Resistencia con un mensaje simple.'),
          ),
          const SizedBox(height: 16),
          InfoCard(
            title: 'Mi número',
            child: Text(myPhone, style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 16),
          InfoCard(
            title: 'Cerrar sesión',
            subtitle: 'Salir y volver a validar el número',
            trailing: const Icon(Icons.logout_rounded),
            onTap: () async {
              await AuthService().signOut();
              await onLogout();
            },
            child: const Text('Usá esta opción para probar otro usuario o forzar una nueva autenticación por teléfono.'),
          ),
        ],
      ),
    );
  }
}
