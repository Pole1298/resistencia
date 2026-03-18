import 'package:flutter/material.dart';
import '../../models/access_diagnosis.dart';

class BlockedScreen extends StatelessWidget {
  const BlockedScreen({
    super.key,
    required this.allowed,
    required this.requiresPayment,
    required this.userNumber,
    required this.freeLimit,
    required this.priceMonthly,
    required this.diagnosis,
    required this.onLogout,
    required this.onRetry,
  });

  final bool allowed;
  final bool requiresPayment;
  final int? userNumber;
  final int freeLimit;
  final int priceMonthly;
  final AccessDiagnosis? diagnosis;
  final VoidCallback onLogout;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final title = !allowed
        ? 'Acceso bloqueado'
        : (requiresPayment ? 'Acceso requiere pago' : 'Bloqueado');

    final msg = !allowed
        ? (diagnosis?.reason == 'Número deshabilitado'
            ? 'Tu número figura en la invitación, pero está deshabilitado. Pedile al administrador que lo habilite.'
            : diagnosis?.reason == 'Usuario suspendido'
                ? 'Tu acceso fue suspendido. Pedile al administrador que revise tu estado.'
                : 'Tu número no figura como habilitado. Pedile al administrador que revise la whitelist.')
        : '''Tu usuario es #${userNumber ?? "-"}.
Se superó el límite gratis ($freeLimit).
Precio mensual: $priceMonthly ARS.
Pedile al administrador que te habilite el pago.''';

    final d = diagnosis;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Acceso'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(18),
        child: ListView(
          children: [
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(msg),
            const SizedBox(height: 18),
            if (d != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(bottom: 8),
                    title: const Text(
                      'Diagnóstico técnico',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(d.reason),
                    children: [
                      _diagRow('Número leído', d.phoneDigits10),
                      _diagRow('Whitelist por ID', d.whitelistByDoc ? 'Sí' : 'No'),
                      _diagRow(
                        'Whitelist por campo phone',
                        d.whitelistByField ? 'Sí' : 'No',
                      ),
                      _diagRow('Admin por ID', d.adminByDoc ? 'Sí' : 'No'),
                      _diagRow(
                        'Admin por campo phone',
                        d.adminByField ? 'Sí' : 'No',
                      ),
                      _diagRow('Enabled', d.enabled ? 'true' : 'false'),
                      _diagRow('Suspended', d.suspended ? 'true' : 'false'),
                      _diagRow('Rol', d.role),
                      _diagRow('UserNumber', '${d.userNumber ?? '-'}'),
                      _diagRow('Pago vigente', d.isPaid ? 'Sí' : 'No'),
                      _diagRow('Requiere pago', d.requiresPayment ? 'Sí' : 'No'),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('Reintentar'),
            ),
            TextButton(
              onPressed: onLogout,
              child: const Text('Salir / Cambiar cuenta'),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _diagRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 170,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(
          child: Text(value),
        ),
      ],
    ),
  );
}