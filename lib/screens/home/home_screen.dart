import 'package:flutter/material.dart';

import '../../core/app_constants.dart';
import '../../services/users_service.dart';
import '../../widgets/info_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.myPhone,
    required this.isAdmin,
    required this.onOpenTab,
  });

  final String myPhone;
  final bool isAdmin;
  final ValueChanged<int> onOpenTab;

  @override
  Widget build(BuildContext context) {
    final service = UsersService();
    final scheme = Theme.of(context).colorScheme;
    final effectiveAdmin = isAdmin || myPhone == AppConstants.founderPhone;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Resistencia'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: scheme.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  effectiveAdmin ? (myPhone == AppConstants.founderPhone ? 'Super Admin' : 'Admin') : 'Usuario',
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: StreamBuilder(
        stream: service.watchUser(myPhone),
        builder: (context, snapshot) {
          final user = snapshot.data;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0F172A), Color(0xFF1E3A8A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.14),
                      blurRadius: 26,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'Estado del servicio',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Listo para operar',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Accediste con tu número autenticado y la cuenta quedó vinculada correctamente al usuario actual.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.86),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _miniStat('Número', myPhone),
                        _miniStat('Puntos', '${user?.points ?? 0}'),
                        _miniStat('Reputación', '${user?.reputation ?? 0}'),
                        _miniStat('Auxilios', '${user?.auxCredits ?? 0}'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _PrimaryActionButton(
                      label: 'INICIAR',
                      icon: Icons.play_arrow_rounded,
                      background: const Color(0xFF16A34A),
                      foreground: Colors.white,
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Seguimiento activado.')),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _PrimaryActionButton(
                      label: 'DETENER',
                      icon: Icons.stop_rounded,
                      background: const Color(0xFFDC2626),
                      foreground: Colors.white,
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Seguimiento detenido.')),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _PrimaryActionButton(
                label: 'REPORTAR',
                icon: Icons.add_location_alt_rounded,
                background: const Color(0xFF1D4ED8),
                foreground: Colors.white,
                onTap: () => onOpenTab(1),
              ),
              const SizedBox(height: 12),
              _PrimaryActionButton(
                label: 'AUXILIO',
                icon: Icons.sos_rounded,
                background: const Color(0xFFDC2626),
                foreground: Colors.white,
                onTap: () => onOpenTab(2),
              ),
              const SizedBox(height: 18),
              InfoCard(
                title: 'Mi cuenta',
                subtitle: 'Datos útiles del usuario activo',
                child: Column(
                  children: [
                    _summaryRow(context, 'Rol', effectiveAdmin ? (myPhone == AppConstants.founderPhone ? 'Super Admin' : 'Admin') : 'Usuario'),
                    _summaryRow(context, 'Puntos', '${user?.points ?? 0}'),
                    _summaryRow(context, 'Reputación', '${user?.reputation ?? 0}'),
                    _summaryRow(context, 'Créditos de auxilio', '${user?.auxCredits ?? 0}'),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Colors.white.withOpacity(0.74), fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _summaryRow(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: foreground),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(color: foreground, fontWeight: FontWeight.w900, letterSpacing: 0.2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
