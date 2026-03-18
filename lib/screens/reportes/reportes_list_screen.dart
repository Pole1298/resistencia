import 'package:flutter/material.dart';

import '../../models/reporte.dart';
import '../../services/reportes_service.dart';
import '../../widgets/info_card.dart';
import 'reporte_detalle_screen.dart';

class ReportesListScreen extends StatefulWidget {
  const ReportesListScreen({super.key, required this.myPhone});

  final String myPhone;

  @override
  State<ReportesListScreen> createState() => _ReportesListScreenState();
}

class _ReportesListScreenState extends State<ReportesListScreen> {
  final ReportesService service = ReportesService();

  String _chipTextTipo(Reporte r) => tipoTexto(r.tipo);
  String _chipTextEstado(Reporte r) => estadoTexto(r.estado);

  Color _estadoBg(ReporteEstado estado) {
    switch (estado) {
      case ReporteEstado.pendiente:
        return Colors.orange.shade100;
      case ReporteEstado.validado:
        return Colors.green.shade100;
      case ReporteEstado.falso:
        return Colors.red.shade100;
      case ReporteEstado.expirado:
        return Colors.grey.shade300;
      case ReporteEstado.cerrado:
        return Colors.blueGrey.shade100;
    }
  }

  Color _estadoFg(ReporteEstado estado) {
    switch (estado) {
      case ReporteEstado.pendiente:
        return Colors.orange.shade900;
      case ReporteEstado.validado:
        return Colors.green.shade900;
      case ReporteEstado.falso:
        return Colors.red.shade900;
      case ReporteEstado.expirado:
        return Colors.grey.shade800;
      case ReporteEstado.cerrado:
        return Colors.blueGrey.shade900;
    }
  }

  Future<void> _openCreateFlow() async {
    final tipo = await showModalBottomSheet<ReporteTipo>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _TipoReporteSheet(),
    );

    if (tipo == null || !mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReporteCreateScreen(
          myPhone: widget.myPhone,
          initialType: tipo,
          service: service,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reportes'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateFlow,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo reporte'),
      ),
      body: StreamBuilder<List<Reporte>>(
        stream: service.watchReportes(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Error al cargar reportes:\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final items = snapshot.data ?? const <Reporte>[];

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const InfoCard(
                title: 'Crear por categoría',
                subtitle: 'Cada flujo respeta su tipo real',
                child: Text('Operativo, accidente, calle cortada y manifestación se cargan por separado para permitir reglas y puntajes diferentes.'),
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Todavía no hay reportes. Tocá “Nuevo reporte” para cargar uno.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                )
              else
                ...items.map((r) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ReporteDetalleScreen(reporte: r),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 46,
                                  height: 46,
                                  decoration: BoxDecoration(
                                    color: colorPorTipo(r.tipo).withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Icon(
                                    iconPorTipo(r.tipo),
                                    color: colorPorTipo(r.tipo),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        r.tituloCorto,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Fecha: ${r.fecha.day.toString().padLeft(2, '0')}/${r.fecha.month.toString().padLeft(2, '0')}/${r.fecha.year} ${r.fecha.hour.toString().padLeft(2, '0')}:${r.fecha.minute.toString().padLeft(2, '0')}',
                                        style: TextStyle(
                                          color: Colors.grey.shade700,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          _chip(_chipTextTipo(r)),
                                          _chip('+${r.puntosBase} pts'),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: _estadoBg(r.estado),
                                              borderRadius: BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              _chipTextEstado(r),
                                              style: TextStyle(
                                                color: _estadoFg(r.estado),
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                          _chip('Validaciones ${r.validaciones}'),
                                          _chip(r.esGps ? 'GPS' : 'Manual'),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  color: Colors.grey.shade500,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    )),
            ],
          );
        },
      ),
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _TipoReporteSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF4F7FB),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 46,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Elegí qué querés reportar',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            Wrap(
              runSpacing: 12,
              children: ReporteTipo.values.map((tipo) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _TipoTile(tipo: tipo),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _TipoTile extends StatelessWidget {
  const _TipoTile({required this.tipo});

  final ReporteTipo tipo;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () => Navigator.of(context).pop(tipo),
      child: Ink(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: colorPorTipo(tipo).withOpacity(0.25)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: colorPorTipo(tipo).withOpacity(0.12),
              child: Icon(iconPorTipo(tipo), color: colorPorTipo(tipo)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tipoTexto(tipo), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text('Base: +${puntosBasePorTipo(tipo)} puntos', style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

class ReporteCreateScreen extends StatefulWidget {
  const ReporteCreateScreen({
    super.key,
    required this.myPhone,
    required this.initialType,
    required this.service,
  });

  final String myPhone;
  final ReporteTipo initialType;
  final ReportesService service;

  @override
  State<ReporteCreateScreen> createState() => _ReporteCreateScreenState();
}

class _ReporteCreateScreenState extends State<ReporteCreateScreen> {
  final _vehiculoItems = const ['autos', 'motos', 'ambos'];
  final _controlItems = const ['documentacion', 'alcoholemia'];
  final _fuerzaItems = const ['transito', 'policia'];
  final _detalleCtrl = TextEditingController();

  late ReporteTipo _tipo;
  String _vehiculo = 'autos';
  String _control = 'documentacion';
  String _fuerza = 'transito';
  bool _manual = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _tipo = widget.initialType;
  }

  @override
  void dispose() {
    _detalleCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;

    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final reporte = Reporte(
        id: '${now.millisecondsSinceEpoch}_${_tipo.name}_${widget.myPhone}',
        fecha: now,
        tipo: _tipo,
        vehiculo: _tipo == ReporteTipo.operativo ? _vehiculo : 'ambos',
        control: _tipo == ReporteTipo.operativo ? _control : 'documentacion',
        fuerza: _tipo == ReporteTipo.operativo ? _fuerza : 'transito',
        createdBy: widget.myPhone,
        lat: _manual ? null : -31.0,
        lng: _manual ? null : -58.0,
      );

      await widget.service.createReporte(reporte, sourcePhone: widget.myPhone);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${tipoTexto(_tipo)} cargado correctamente.')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar el reporte: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Nuevo ${tipoTexto(_tipo)}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          InfoCard(
            title: tipoTexto(_tipo),
            subtitle: 'Tipo preseleccionado y bloqueado para evitar errores',
            child: Text('Este formulario guarda el tipo real del aviso y aplica una base de +${puntosBasePorTipo(_tipo)} puntos.'),
          ),
          const SizedBox(height: 16),
          if (_tipo == ReporteTipo.operativo) ...[
            DropdownButtonFormField<String>(
              value: _vehiculo,
              items: _vehiculoItems.map((item) => DropdownMenuItem(value: item, child: Text(vehiculoTexto(item)))).toList(),
              onChanged: (value) => setState(() => _vehiculo = value ?? _vehiculo),
              decoration: const InputDecoration(labelText: 'Vehículos'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _control,
              items: _controlItems.map((item) => DropdownMenuItem(value: item, child: Text(controlTexto(item)))).toList(),
              onChanged: (value) => setState(() => _control = value ?? _control),
              decoration: const InputDecoration(labelText: 'Tipo de control'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _fuerza,
              items: _fuerzaItems.map((item) => DropdownMenuItem(value: item, child: Text(fuerzaTexto(item)))).toList(),
              onChanged: (value) => setState(() => _fuerza = value ?? _fuerza),
              decoration: const InputDecoration(labelText: 'Fuerza interviniente'),
            ),
            const SizedBox(height: 12),
          ] else ...[
            TextField(
              controller: _detalleCtrl,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Detalle breve',
                hintText: 'Contá en una línea qué está pasando con este ${tipoTexto(_tipo).toLowerCase()}.',
              ),
            ),
            const SizedBox(height: 12),
          ],
          SwitchListTile.adaptive(
            value: _manual,
            contentPadding: EdgeInsets.zero,
            title: const Text('Aviso manual'),
            subtitle: const Text('Cuando esté apagado, quedará preparado para usar coordenadas GPS reales.'),
            onChanged: (value) => setState(() => _manual = value),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_rounded),
            label: Text(_saving ? 'Guardando...' : 'Guardar reporte'),
          ),
        ],
      ),
    );
  }
}
