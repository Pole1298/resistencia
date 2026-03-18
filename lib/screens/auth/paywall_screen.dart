import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class PaywallScreen extends StatelessWidget {
  const PaywallScreen({
    super.key,
    required this.phoneDigits10,
    required this.freeLimit,
    required this.userNumber,
    required this.monthlyPriceArs,
    required this.subscriptionDays,
    required this.payAlias,
    required this.payCbu,
    required this.payHolder,
    required this.payNote,
    required this.onRetry,
  });

  final String phoneDigits10;
  final int freeLimit;
  final int? userNumber;
  final int monthlyPriceArs;
  final int subscriptionDays;
  final String payAlias;
  final String payCbu;
  final String payHolder;
  final String payNote;
  final Future<void> Function() onRetry;

  String _buildShareText() {
    final lines = <String>[
      'Resistencia - Pago de acceso',
      'Número: $phoneDigits10',
      'N° usuario: ${userNumber ?? 0} (gratis hasta $freeLimit)',
      'Monto: $monthlyPriceArs ARS - $subscriptionDays días',
    ];

    if (payAlias.trim().isNotEmpty) {
      lines.add('Alias: $payAlias');
    }
    if (payCbu.trim().isNotEmpty) {
      lines.add('CBU/CVU: $payCbu');
    }
    if (payHolder.trim().isNotEmpty) {
      lines.add('Titular: $payHolder');
    }
    if (payNote.trim().isNotEmpty) {
      lines.add('Nota: $payNote');
    }

    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final n = userNumber ?? 0;
    final shareText = _buildShareText();

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Acceso restringido'),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ListView(
                shrinkWrap: true,
                children: [
                  const Text(
                    'Suscripción requerida',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Tu número: $phoneDigits10',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'N° de usuario: $n (gratis hasta $freeLimit)',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Monto: $monthlyPriceArs ARS - $subscriptionDays días',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (payAlias.trim().isNotEmpty)
                    SelectableText(
                      'Alias: $payAlias',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  if (payCbu.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    SelectableText(
                      'CBU/CVU: $payCbu',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                  if (payHolder.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    SelectableText(
                      'Titular: $payHolder',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                  if (payNote.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(payNote),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          if (payAlias.trim().isEmpty) return;
                          await Clipboard.setData(
                            ClipboardData(text: payAlias.trim()),
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Alias copiado')),
                            );
                          }
                        },
                        icon: const Icon(Icons.copy),
                        label: const Text('Copiar alias'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          if (payCbu.trim().isEmpty) return;
                          await Clipboard.setData(
                            ClipboardData(text: payCbu.trim()),
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('CBU/CVU copiado')),
                            );
                          }
                        },
                        icon: const Icon(Icons.copy),
                        label: const Text('Copiar CBU/CVU'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: shareText),
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Datos completos copiados')),
                            );
                          }
                        },
                        icon: const Icon(Icons.copy_all),
                        label: const Text('Copiar todo'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final enc = Uri.encodeComponent(shareText);
                          final waUri = Uri.parse('whatsapp://send?text=$enc');
                          final webWa = Uri.parse('https://wa.me/?text=$enc');

                          try {
                            if (await canLaunchUrl(waUri)) {
                              await launchUrl(
                                waUri,
                                mode: LaunchMode.externalApplication,
                              );
                              return;
                            }
                          } catch (_) {}

                          try {
                            if (await canLaunchUrl(webWa)) {
                              await launchUrl(
                                webWa,
                                mode: LaunchMode.externalApplication,
                              );
                              return;
                            }
                          } catch (_) {}

                          await Share.share(
                            shareText,
                            subject: 'Pago - Resistencia',
                          );
                        },
                        icon: const Icon(Icons.chat),
                        label: const Text('WhatsApp'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        try {
                          await onRetry();
                        } catch (_) {}
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Reintentando validación...'),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Ya pagué / Reintentar'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Cuando el administrador te habilite, se destraba solo.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}