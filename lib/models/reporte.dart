import 'package:flutter/material.dart';

enum ReporteTipo { operativo, accidente, piquete, calleCortada }

enum ReporteEstado { pendiente, validado, falso, expirado, cerrado }

String tipoTexto(ReporteTipo t) {
  switch (t) {
    case ReporteTipo.operativo:
      return 'Operativo';
    case ReporteTipo.accidente:
      return 'Accidente';
    case ReporteTipo.piquete:
      return 'Manifestación';
    case ReporteTipo.calleCortada:
      return 'Calle cortada';
  }
}

int puntosBasePorTipo(ReporteTipo t) {
  switch (t) {
    case ReporteTipo.operativo:
      return 120;
    case ReporteTipo.accidente:
      return 90;
    case ReporteTipo.calleCortada:
      return 70;
    case ReporteTipo.piquete:
      return 60;
  }
}

String vehiculoTexto(String v) {
  switch (v) {
    case 'autos':
      return 'Autos';
    case 'motos':
      return 'Motos';
    case 'ambos':
      return 'Autos y motos';
    default:
      return v;
  }
}

String controlTexto(String c) {
  switch (c) {
    case 'alcoholemia':
      return 'Alcoholemia';
    case 'documentacion':
    case 'papeles':
      return 'Control de documentación';
    default:
      return c;
  }
}

String fuerzaTexto(String f) {
  switch (f) {
    case 'transito':
      return 'Tránsito';
    case 'policia':
      return 'Policía';
    default:
      return f;
  }
}

int duracionMinPorTipo(ReporteTipo t) {
  switch (t) {
    case ReporteTipo.operativo:
      return 60;
    case ReporteTipo.accidente:
      return 30;
    case ReporteTipo.piquete:
      return 30;
    case ReporteTipo.calleCortada:
      return 12 * 60;
  }
}

IconData iconPorTipo(ReporteTipo t) {
  switch (t) {
    case ReporteTipo.operativo:
      return Icons.location_on;
    case ReporteTipo.accidente:
      return Icons.car_crash;
    case ReporteTipo.piquete:
      return Icons.campaign;
    case ReporteTipo.calleCortada:
      return Icons.block;
  }
}

Color colorPorTipo(ReporteTipo t) {
  switch (t) {
    case ReporteTipo.operativo:
      return Colors.red;
    case ReporteTipo.accidente:
      return Colors.orange;
    case ReporteTipo.piquete:
      return Colors.deepPurple;
    case ReporteTipo.calleCortada:
      return Colors.blueGrey;
  }
}

String estadoTexto(ReporteEstado e) {
  switch (e) {
    case ReporteEstado.pendiente:
      return 'Pendiente';
    case ReporteEstado.validado:
      return 'Validado';
    case ReporteEstado.falso:
      return 'Marcado como falso';
    case ReporteEstado.expirado:
      return 'Expirado';
    case ReporteEstado.cerrado:
      return 'Cerrado';
  }
}

class Reporte {
  final String id;
  final DateTime fecha;
  final ReporteTipo tipo;
  final String vehiculo;
  final String control;
  final String fuerza;
  final String zoneKey;
  final String createdBy;
  final double? lat;
  final double? lng;
  final int puntosBase;
  int validaciones;
  ReporteEstado estado;
  final int duracionMin;
  bool puntosAcreditados;

  Reporte({
    required this.id,
    required this.fecha,
    required this.tipo,
    this.vehiculo = 'autos',
    this.control = 'documentacion',
    this.fuerza = 'transito',
    this.zoneKey = '',
    this.createdBy = '',
    this.lat,
    this.lng,
    int? puntosBase,
    this.validaciones = 0,
    this.estado = ReporteEstado.pendiente,
    int? duracionMin,
    this.puntosAcreditados = false,
  })  : puntosBase = puntosBase ?? puntosBasePorTipo(tipo),
        duracionMin = duracionMin ?? duracionMinPorTipo(tipo);

  bool get esGps => lat != null && lng != null;

  DateTime get venceEn => fecha.add(Duration(minutes: duracionMin));

  bool get vencido => DateTime.now().isAfter(venceEn);

  bool get activo =>
      !vencido &&
      estado != ReporteEstado.falso &&
      estado != ReporteEstado.expirado &&
      estado != ReporteEstado.cerrado;

  String get tituloCorto {
    if (tipo == ReporteTipo.operativo) {
      return '${vehiculoTexto(vehiculo)} • ${controlTexto(control)} • ${fuerzaTexto(fuerza)}';
    }
    return tipoTexto(tipo);
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'fecha': fecha.toIso8601String(),
        'tipo': tipo.name,
        'vehiculo': vehiculo,
        'control': control,
        'fuerza': fuerza,
        'zoneKey': zoneKey,
        'createdBy': createdBy,
        'lat': lat,
        'lng': lng,
        'puntosBase': puntosBase,
        'validaciones': validaciones,
        'estado': estado.name,
        'duracionMin': duracionMin,
        'puntosAcreditados': puntosAcreditados,
      };

  static ReporteTipo _parseTipo(String raw) {
    switch (raw) {
      case 'manifestacion':
      case 'piquete':
        return ReporteTipo.piquete;
      case 'calleCortada':
      case 'calle_cortada':
        return ReporteTipo.calleCortada;
      case 'accidente':
        return ReporteTipo.accidente;
      default:
        return ReporteTipo.operativo;
    }
  }

  static Reporte fromMap(Map<String, dynamic> m) {
    final fecha = DateTime.parse(m['fecha'] as String);
    final tipo = _parseTipo((m['tipo'] as String?) ?? 'operativo');

    final rawEstado = (m['estado'] as String?) ?? ReporteEstado.pendiente.name;
    final estado = ReporteEstado.values.firstWhere(
      (e) => e.name == rawEstado,
      orElse: () => ReporteEstado.pendiente,
    );

    return Reporte(
      id: m['id'] as String,
      fecha: fecha,
      tipo: tipo,
      vehiculo: (m['vehiculo'] as String?) ?? 'autos',
      control: (m['control'] as String?) ?? 'documentacion',
      fuerza: (m['fuerza'] as String?) ?? 'transito',
      zoneKey: (m['zoneKey'] as String?) ?? '',
      createdBy: (m['createdBy'] as String?) ?? '',
      lat: (m['lat'] as num?)?.toDouble(),
      lng: (m['lng'] as num?)?.toDouble(),
      puntosBase: (m['puntosBase'] as num?)?.toInt(),
      validaciones: (m['validaciones'] as num?)?.toInt() ?? 0,
      estado: estado,
      duracionMin: (m['duracionMin'] as num?)?.toInt(),
      puntosAcreditados: (m['puntosAcreditados'] as bool?) ?? false,
    );
  }
}
