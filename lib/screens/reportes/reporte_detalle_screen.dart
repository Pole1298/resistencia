import 'package:flutter/material.dart';
import '../../models/reporte.dart';

class ReporteDetalleScreen extends StatelessWidget {
  final Reporte reporte;

  const ReporteDetalleScreen({
    super.key,
    required this.reporte,
  });

  String _fmtFecha(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yy = d.year.toString();
    final hh = d.hour.toString().padLeft(2, '0');
    final mi = d.minute.toString().padLeft(2, '0');
    return '$dd/$mm/$yy $hh:$mi';
  }

  String _fmtCoord(double? v) {
    if (v == null) return '-';
    return v.toStringAsFixed(6);
  }

  @override
  Widget build(BuildContext context) {
    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle del reporte'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            shape: cardShape,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tipoTexto(reporte.tipo),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    reporte.tituloCorto,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _estadoChip(reporte.estado),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            shape: cardShape,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Información',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _line('Fecha', _fmtFecha(reporte.fecha)),
                  _line('Tipo', tipoTexto(reporte.tipo)),
                  _line('Estado', estadoTexto(reporte.estado)),
                  _line('Validaciones', '${reporte.validaciones}'),
                  _line('Duración', '${reporte.duracionMin} min'),
                  _line(
                    'GPS',
                    reporte.esGps ? 'Sí' : 'No (aviso a distancia)',
                  ),
                  _line(
                    'Puntos acreditados',
                    reporte.puntosAcreditados ? 'Sí' : 'No',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (reporte.tipo == ReporteTipo.operativo)
            Card(
              elevation: 0,
              shape: cardShape,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Detalle del operativo',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _line('Vehículos', vehiculoTexto(reporte.vehiculo)),
                    _line('Control', controlTexto(reporte.control)),
                    _line('Fuerza', fuerzaTexto(reporte.fuerza)),
                  ],
                ),
              ),
            ),
          if (reporte.esGps) ...[
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              shape: cardShape,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ubicación',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _line('Latitud', _fmtCoord(reporte.lat)),
                    _line('Longitud', _fmtCoord(reporte.lng)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _estadoChip(ReporteEstado estado) {
    Color bg;
    Color fg;

    switch (estado) {
      case ReporteEstado.pendiente:
        bg = Colors.orange.shade100;
        fg = Colors.orange.shade900;
        break;
      case ReporteEstado.validado:
        bg = Colors.green.shade100;
        fg = Colors.green.shade900;
        break;
      case ReporteEstado.falso:
        bg = Colors.red.shade100;
        fg = Colors.red.shade900;
        break;
      case ReporteEstado.expirado:
        bg = Colors.grey.shade300;
        fg = Colors.grey.shade800;
        break;
      case ReporteEstado.cerrado:
        bg = Colors.blueGrey.shade100;
        fg = Colors.blueGrey.shade900;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        estadoTexto(estado),
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}