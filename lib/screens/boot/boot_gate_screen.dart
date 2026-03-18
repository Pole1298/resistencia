import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shell/app_shell_bridge.dart';

class BootGateScreen extends StatefulWidget {
  final String myPhone;
  final bool isAdmin;

  const BootGateScreen({
    super.key,
    required this.myPhone,
    required this.isAdmin,
  });

  @override
  State<BootGateScreen> createState() => _BootGateScreenState();
}

class _BootGateScreenState extends State<BootGateScreen> {
  static const String wizardDoneKey = 'ro_wizard_done_v2';

  bool notifOk = false;
  bool locationOk = false;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final wizardDone = prefs.getBool(wizardDoneKey) ?? false;

    final notif = await Permission.notification.status;
    final loc = await Permission.locationWhenInUse.status;

    if (!mounted) return;

    final nextNotif = notif.isGranted || notif.isLimited;
    final nextLoc = loc.isGranted || loc.isLimited;

    if (wizardDone) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => AppShellBridge(
            isAdmin: widget.isAdmin,
            myPhone: widget.myPhone,
          ),
        ),
      );
      return;
    }

    setState(() {
      notifOk = nextNotif;
      locationOk = nextLoc;
      loading = false;
    });
  }

  Future<void> _requestNotif() async {
    final res = await Permission.notification.request();
    if (!mounted) return;
    setState(() => notifOk = res.isGranted || res.isLimited);
  }

  Future<void> _requestLocation() async {
    final res = await Permission.locationWhenInUse.request();
    if (!mounted) return;
    setState(() => locationOk = res.isGranted || res.isLimited);
  }

  bool get allOk => notifOk && locationOk;

  Future<void> _continueToApp() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(wizardDoneKey, true);

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => AppShellBridge(
          isAdmin: widget.isAdmin,
          myPhone: widget.myPhone,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Permisos iniciales'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Antes de entrar, habilitá lo necesario para recibir alertas y validar reportes.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFF4B5563),
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 16),
            _PermissionCard(
              icon: Icons.notifications_active_rounded,
              iconColor: notifOk ? Colors.green : Colors.orange,
              title: 'Notificaciones',
              description: 'Se usan para avisos de operativos, novedades y auxilios.',
              granted: notifOk,
              buttonText: notifOk ? 'Activadas' : 'Permitir',
              onPressed: notifOk ? null : _requestNotif,
            ),
            const SizedBox(height: 14),
            _PermissionCard(
              icon: Icons.location_on_rounded,
              iconColor: locationOk ? Colors.green : Colors.orange,
              title: 'Ubicación',
              description: 'Se usa para proximidad, validaciones y mejor calidad de reportes.',
              granted: locationOk,
              buttonText: locationOk ? 'Activada' : 'Permitir',
              onPressed: locationOk ? null : _requestLocation,
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Icon(
                    allOk ? Icons.check_circle_rounded : Icons.info_rounded,
                    color: allOk ? Colors.green : scheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      allOk
                          ? 'Todo listo. Ya podés entrar.'
                          : 'Podés continuar ahora y terminar de habilitar permisos después.',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (widget.isAdmin)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.admin_panel_settings_rounded, color: Color(0xFF1D4ED8)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Ingreso detectado con permisos de administración.',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1E3A8A),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _continueToApp,
                child: Text(widget.isAdmin ? 'Continuar como Admin' : 'Continuar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
  final bool granted;
  final String buttonText;
  final VoidCallback? onPressed;

  const _PermissionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.granted,
    required this.buttonText,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            blurRadius: 10,
            offset: Offset(0, 3),
            color: Color(0x12000000),
          ),
        ],
        border: Border.all(
          color: granted ? Colors.green.withOpacity(0.18) : scheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: iconColor.withOpacity(0.12),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                granted ? Icons.check_circle : Icons.warning_amber_rounded,
                color: granted ? Colors.green : Colors.orange,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: const TextStyle(
              height: 1.35,
              color: Color(0xFF4B5563),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: granted
                ? OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.check_rounded),
                    label: Text(buttonText),
                  )
                : FilledButton.icon(
                    onPressed: onPressed,
                    icon: const Icon(Icons.lock_open_rounded),
                    label: Text(buttonText),
                  ),
          ),
        ],
      ),
    );
  }
}
