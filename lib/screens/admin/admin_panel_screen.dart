import 'package:flutter/material.dart';

import '../../core/app_constants.dart';
import '../../core/formatters.dart';
import '../../services/admin_service.dart';
import '../../services/users_service.dart';
import '../../widgets/info_card.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key, required this.myPhone});

  final String myPhone;

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  final _phoneCtrl = TextEditingController();
  final _freeLimitCtrl = TextEditingController();
  final _monthlyPriceCtrl = TextEditingController();
  final _subscriptionDaysCtrl = TextEditingController();
  final _payAliasCtrl = TextEditingController();
  final _payCbuCtrl = TextEditingController();
  final _payHolderCtrl = TextEditingController();
  final _payNoteCtrl = TextEditingController();

  final _adminService = AdminService();
  final _usersService = UsersService();

  String _lookupPhone = '';
  bool _payEnabled = true;
  bool _loadingConfig = true;
  bool _savingConfig = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _freeLimitCtrl.dispose();
    _monthlyPriceCtrl.dispose();
    _subscriptionDaysCtrl.dispose();
    _payAliasCtrl.dispose();
    _payCbuCtrl.dispose();
    _payHolderCtrl.dispose();
    _payNoteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    setState(() => _loadingConfig = true);
    try {
      await _adminService.bootstrapFounder();
      final cfg = await _adminService.loadConfig();
      _freeLimitCtrl.text = '${(cfg['freeLimit'] as num?)?.toInt() ?? AppConstants.defaultFreeLimit}';
      _monthlyPriceCtrl.text = '${(cfg['monthlyPriceArs'] as num?)?.toInt() ?? AppConstants.defaultPriceMonthly}';
      _subscriptionDaysCtrl.text = '${(cfg['subscriptionDays'] as num?)?.toInt() ?? AppConstants.defaultSubscriptionDays}';
      _payAliasCtrl.text = (cfg['payAlias'] as String?) ?? '';
      _payCbuCtrl.text = (cfg['payCbu'] as String?) ?? '';
      _payHolderCtrl.text = (cfg['payHolder'] as String?) ?? '';
      _payNoteCtrl.text = (cfg['payNote'] as String?) ?? '';
      _payEnabled = (cfg['payEnabled'] as bool?) ?? true;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cargar configuración: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() => _loadingConfig = false);
    }
  }

  Future<void> _runAction(Future<void> Function() action, String success) async {
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
      setState(() {
        _lookupPhone = normalizeArPhone(_phoneCtrl.text.trim());
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _saveConfig() async {
    final freeLimit = int.tryParse(_freeLimitCtrl.text.trim());
    final monthlyPrice = int.tryParse(_monthlyPriceCtrl.text.trim());
    final subscriptionDays = int.tryParse(_subscriptionDaysCtrl.text.trim());

    if (freeLimit == null || monthlyPrice == null || subscriptionDays == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Revisá Free limit, precio mensual y días de suscripción.')),
      );
      return;
    }

    setState(() => _savingConfig = true);
    try {
      await _adminService.saveConfig(
        freeLimit: freeLimit,
        monthlyPriceArs: monthlyPrice,
        subscriptionDays: subscriptionDays,
        payEnabled: _payEnabled,
        payAlias: _payAliasCtrl.text,
        payCbu: _payCbuCtrl.text,
        payHolder: _payHolderCtrl.text,
        payNote: _payNoteCtrl.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuración guardada.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar configuración: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() => _savingConfig = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final normalizedFounder = normalizeArPhone(widget.myPhone);
    final isFounder = normalizedFounder == AppConstants.founderPhone;

    return Scaffold(
      appBar: AppBar(title: const Text('Panel Admin')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          InfoCard(
            title: 'Administración central',
            subtitle: 'Operación rápida y configuración general',
            child: Text(
              'Usuario actual: $normalizedFounder${isFounder ? ' (Fundador / Super Admin)' : ''}. El fundador (${AppConstants.founderPhone}) queda protegido y no puede perder permisos.',
            ),
          ),
          const SizedBox(height: 16),
          InfoCard(
            title: 'Acciones sobre usuarios',
            child: Column(
              children: [
                TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Número de teléfono'),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed: () => _runAction(
                        () => _adminService.addToWhitelist(_phoneCtrl.text),
                        'Agregado a whitelist.',
                      ),
                      child: const Text('Agregar whitelist'),
                    ),
                    OutlinedButton(
                      onPressed: () => _runAction(
                        () => _adminService.setAdmin(_phoneCtrl.text, value: true),
                        'Usuario promovido a admin.',
                      ),
                      child: const Text('Hacer admin'),
                    ),
                    OutlinedButton(
                      onPressed: () => _runAction(
                        () => _adminService.setWhitelistEnabled(_phoneCtrl.text, true),
                        'Usuario habilitado.',
                      ),
                      child: const Text('Habilitar'),
                    ),
                    OutlinedButton(
                      onPressed: () => _runAction(
                        () => _adminService.setWhitelistEnabled(_phoneCtrl.text, false),
                        'Usuario deshabilitado.',
                      ),
                      child: const Text('Deshabilitar'),
                    ),
                    OutlinedButton(
                      onPressed: () => _runAction(
                        () => _adminService.setSuspended(_phoneCtrl.text, true),
                        'Usuario suspendido.',
                      ),
                      child: const Text('Suspender'),
                    ),
                    OutlinedButton(
                      onPressed: () => _runAction(
                        () => _adminService.setSuspended(_phoneCtrl.text, false),
                        'Usuario reactivado.',
                      ),
                      child: const Text('Reactivar'),
                    ),
                    FilledButton.tonal(
                      onPressed: () => setState(() => _lookupPhone = normalizeArPhone(_phoneCtrl.text.trim())),
                      child: const Text('Ver ficha'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_loadingConfig)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else
            InfoCard(
              title: 'Configuración general',
              subtitle: 'Parámetros que no deberían requerir recompilar',
              child: Column(
                children: [
                  TextField(
                    controller: _freeLimitCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Free limit'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _monthlyPriceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Precio mensual ARS'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _subscriptionDaysCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Días de suscripción'),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    value: _payEnabled,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Cobro habilitado'),
                    subtitle: const Text('Si está apagado, no se exige suscripción aunque supere el free limit.'),
                    onChanged: (value) => setState(() => _payEnabled = value),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _payAliasCtrl,
                    decoration: const InputDecoration(labelText: 'Alias de cobro'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _payCbuCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'CBU / CVU'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _payHolderCtrl,
                    decoration: const InputDecoration(labelText: 'Titular'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _payNoteCtrl,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Nota de pago'),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _savingConfig ? null : _saveConfig,
                    icon: const Icon(Icons.save_rounded),
                    label: Text(_savingConfig ? 'Guardando...' : 'Guardar configuración'),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          if (_lookupPhone.isNotEmpty)
            FutureBuilder(
              future: _usersService.fetchUser(_lookupPhone),
              builder: (context, snapshot) {
                final user = snapshot.data;
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()));
                }
                if (user == null) {
                  return const InfoCard(title: 'Ficha rápida', child: Text('No se encontró usuario.'));
                }
                return InfoCard(
                  title: 'Ficha rápida',
                  subtitle: 'Resumen del usuario consultado',
                  child: Column(
                    children: [
                      _row('Número', user.phone),
                      _row('UserNumber', '${user.userNumber ?? '-'}'),
                      _row('Rol', user.role),
                      _row('Enabled', '${user.enabled}'),
                      _row('Suspended', '${user.suspended}'),
                      _row('Puntos', '${user.points}'),
                      _row('Reputación', '${user.reputation}'),
                      _row('Aux créditos', '${user.auxCredits}'),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

Widget _row(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        SizedBox(width: 110, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
        Expanded(child: Text(value)),
      ],
    ),
  );
}
