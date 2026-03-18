import 'package:flutter/material.dart';

import '../../services/auxilio_service.dart';
import '../../widgets/info_card.dart';

class AuxilioScreen extends StatelessWidget {
  const AuxilioScreen({super.key, required this.myPhone});

  final String myPhone;

  @override
  Widget build(BuildContext context) {
    final service = AuxilioService();
    return Scaffold(
      appBar: AppBar(title: const Text('Auxilio')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFFDC2626),
        foregroundColor: Colors.white,
        onPressed: () => _showRequestDialog(context, service),
        icon: const Icon(Icons.sos_rounded),
        label: const Text('Pedir auxilio'),
      ),
      body: StreamBuilder(
        stream: service.watchAuxilios(),
        builder: (context, snapshot) {
          final list = snapshot.data ?? const [];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              const InfoCard(
                title: 'Asistencia entre usuarios',
                subtitle: 'Base operativa para pedidos de ayuda',
                child: Text('La función de auxilio permite pedir ayuda, aceptar asistencia y completar el proceso sobre una estructura preparada para trazabilidad y validación.'),
              ),
              const SizedBox(height: 16),
              if (list.isEmpty)
                const InfoCard(
                  title: 'No hay auxilios activos',
                  child: Text('Cuando haya pedidos de ayuda o asistencias en curso van a aparecer acá.'),
                )
              else
                ...list.map((a) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: InfoCard(
                        title: 'Auxilio ${a.id.substring(0, 6)}',
                        subtitle: 'Estado: ${a.status}',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Solicitó: ${a.requestedBy}'),
                            if ((a.acceptedBy ?? '').isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text('Aceptó: ${a.acceptedBy}'),
                            ],
                            if (a.note.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text(a.note),
                            ],
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (a.status == 'requested')
                                  OutlinedButton(
                                    onPressed: () => service.acceptAuxilio(id: a.id, helperPhone: myPhone),
                                    child: const Text('Aceptar'),
                                  ),
                                if (a.status == 'accepted' && a.acceptedBy == myPhone)
                                  FilledButton(
                                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
                                    onPressed: () => service.completeAuxilio(a.id),
                                    child: const Text('Completar'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    )),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showRequestDialog(BuildContext context, AuxilioService service) async {
    final noteCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Pedir auxilio'),
        content: TextField(
          controller: noteCtrl,
          decoration: const InputDecoration(labelText: 'Detalle breve'),
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              await service.requestAuxilio(phone: myPhone, note: noteCtrl.text.trim());
              if (context.mounted) Navigator.pop(context);
            },
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
  }
}
