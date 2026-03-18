import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';

import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

// ================== FIREBASE ==================
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';


// ================== ENTRYPOINT (ANTI-LOGO BLOQUEADO) ==================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initFirebaseSafe();
  runApp(const ROApp());
}

Future<void> _initFirebaseSafe() async {
  try {
    // Para Android, con google-services.json correcto, no hace falta pasar options.
    await Firebase.initializeApp();
  } catch (_) {
    // Si Firebase no está configurado todavía, la app igual puede iniciar en modo legacy.
  }
}


class ROApp extends StatelessWidget {
  const ROApp({super.key});

  bool _chatEnabledForStatus(String status) {
    return const ['open', 'accepted', 'arrived', 'pending_confirm'].contains(status);
  }

  Future<void> _sendChatMessage({required Map<String, dynamic> d, required String text, String kind = 'text'}) async {
    final clean = text.trim();
    if (clean.isEmpty) return;

    final status = (d['status'] ?? '').toString();
    final isRequester = _isRequester(d);
    final isHelper = _isHelper(d);

    if (!_chatEnabledForStatus(status)) {
      widget.onToast('El chat ya quedó cerrado para este auxilio.');
      return;
    }
    if (!(isRequester || isHelper || widget.isAdmin)) {
      widget.onToast('No tenés permiso para escribir en este chat.');
      return;
    }

    final role = isRequester ? 'requester' : (isHelper ? 'helper' : 'admin');

    try {
      await widget.auxRef.collection('chat').add({
        'text': clean,
        'kind': kind,
        'senderPhone': widget.myPhoneDigits,
        'senderRole': role,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await widget.auxRef.set({
        'lastChatAt': FieldValue.serverTimestamp(),
        'lastChatPreview': clean,
      }, SetOptions(merge: true));

      if (_chatCtrl.text.trim() == clean) {
        _chatCtrl.clear();
      }
    } catch (_) {
      widget.onToast('No se pudo enviar el mensaje.');
    }
  }

  Widget _quickMsgChip(Map<String, dynamic> d, String text) {
    return ActionChip(
      label: Text(text),
      onPressed: () => _sendChatMessage(d: d, text: text, kind: 'quick'),
    );
  }

  Widget _buildChatSection(Map<String, dynamic> d, String status, bool isRequester, bool isHelper) {
    final canWrite = _chatEnabledForStatus(status) && (isRequester || isHelper || widget.isAdmin);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        const Text(
          'Chat de coordinación',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
        ),
        const SizedBox(height: 6),
        Text(
          canWrite
              ? 'Sirve para coordinar detalles, ubicación y acuerdos extra dentro del auxilio.'
              : 'El chat queda solo lectura cuando el auxilio ya terminó o no pertenecés a este auxilio.',
          style: const TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _quickMsgChip(d, '¿Dónde estás exactamente?'),
            _quickMsgChip(d, 'Ya voy en camino'),
            _quickMsgChip(d, 'Llegué'),
            _quickMsgChip(d, 'Necesito más detalle'),
            _quickMsgChip(d, 'Hay costo extra'),
            _quickMsgChip(d, 'Acepto costo extra'),
            _quickMsgChip(d, 'No acepto'),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          height: 190,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: widget.auxRef
                .collection('chat')
                .orderBy('createdAt', descending: false)
                .limit(100)
                .snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snap.data?.docs ?? const [];
              if (docs.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Todavía no hay mensajes. Usen el chat para coordinar mejor el auxilio.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black54),
                    ),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(10),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final m = docs[i].data();
                  final txt = (m['text'] ?? '').toString();
                  final sender = (m['senderPhone'] ?? '').toString();
                  final role = (m['senderRole'] ?? '').toString();
                  final mine = sender == widget.myPhoneDigits;
                  final ts = m['createdAt'];
                  final when = ts is Timestamp ? hhmm(ts.toDate()) : '--:--';
                  final label = role == 'requester'
                      ? 'Solicitante'
                      : role == 'helper'
                          ? 'Ayudante'
                          : 'Admin';

                  return Align(
                    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 280),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: mine ? Colors.blue.shade50 : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: mine ? Colors.blue.shade200 : Colors.grey.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$label • $when',
                              style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(txt, style: const TextStyle(fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _chatCtrl,
                enabled: canWrite,
                minLines: 1,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Escribir mensaje',
                  hintText: 'Ej: Estoy en la esquina, traé cables',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: canWrite ? () => _sendChatMessage(d: d, text: _chatCtrl.text) : null,
              icon: const Icon(Icons.send_rounded),
              label: const Text('Enviar'),
            ),
          ],
        ),
      ],
    );
  }


  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Resistencia',
      home: const ROBootGate(),
    );
  }
}

/// Gate liviano para evitar quedarse en el splash/logo por inits pesados.
class ROBootGate extends StatefulWidget {
  const ROBootGate({super.key});

  @override
  State<ROBootGate> createState() => _ROBootGateState();
}

class _ROBootGateState extends State<ROBootGate> {
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Init mínimo y con timeout: nunca splash infinito.
      await _safeInit().timeout(const Duration(seconds: 10));
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const FirestoreAccessGate(),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _safeInit() async {
    // SharedPreferences a veces tarda; lo hacemos acá pero con timeout global.
    await SharedPreferences.getInstance();
    // Nada de permisos/GPS/red acá.
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Error al iniciar',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(onPressed: _boot, child: const Text('Reintentar')),
              ],
            ),
          ),
        ),
      );
    }

    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

// ================== NOTIFICACIONES ==================
final FlutterLocalNotificationsPlugin _noti = FlutterLocalNotificationsPlugin();
const String CH_SILENCIO = 'ro_silencio';
const String CH_ALARMA = 'ro_alarma';
const String CH_VIBRA = 'ro_vibra';

// ================== STORAGE KEYS ==================

// ================== ANTI-SPAM (NOTIFICACIONES / TOASTS) ==================
// Evita repetir mensajes molestos cada pocos segundos (ej: "GPS reiniciado").
final Map<String, int> _throttleLastMs = {};
bool _throttle(String key, {int ms = 60000}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  final last = _throttleLastMs[key] ?? 0;
  if (now - last < ms) return false;
  _throttleLastMs[key] = now;
  return true;
}

const String K_STATE = 'ro_state_v3';
const String K_ACCESS = 'ro_access_v2';
const String K_CONFIG_FINAL = 'ro_config_final_v1';
const String K_WIZARD_DONE = 'ro_wizard_done_v1';


// ================== OTP ANTI-ABUSO ==================
// Cooldown mínimo 60s entre envíos y máximo 3 intentos en 10 minutos.
const String K_OTP_LAST_SENT_MS = 'ro_otp_last_sent_ms';
const String K_OTP_WINDOW_START_MS = 'ro_otp_window_start_ms';
const String K_OTP_WINDOW_COUNT = 'ro_otp_window_count';
// ================== PAYWALL (REMOTE) ==================
// Opción PRO "500 gratis" con contador GLOBAL (servidor).
// La app llama a un backend (ideal: Firebase Functions + Firestore) para:
// - Asignar número de usuario único (userNumber) por teléfono (transacción server-side)
// - Devolver estado: freeLimit / paywallEnabled / isPaid
//
// ✅ No requiere plugins de Firebase en Flutter (no toca android/gradle).
// ✅ Solo usa HTTPS (HttpClient) y cache local.
// ⚠️ Tenés que montar el backend y poner la URL abajo.
const bool USE_REMOTE_PAYWALL = false; // Migración oficial: Firestore
// Ejemplo: https://<tu-proyecto>.cloudfunctions.net/roGate
const String REMOTE_PAYWALL_BASE_URL = ''; // Render eliminado: Firebase/Firestore es el backend oficial

// URLs alternativas por si cambia la IP LAN o estás fuera de WiFi.
// Se prueban en orden (primero REMOTE_PAYWALL_BASE_URL, luego estas).
const List<String> REMOTE_PAYWALL_FALLBACK_URLS = []; // Render eliminado
const String K_LAST_GOOD_BASE = 'ro_last_good_base';
const String K_ACCESS_TOKEN = 'ro_fs_access_token_v1';

// ================== FIRESTORE ACCESS (INVITACIÓN CENTRALIZADA) ==================
// Desarrollo estable: arrancar por gate local para no bloquear pruebas con OTP/Firebase.
const bool USE_FIRESTORE_ACCESS = true;

// Firestore paths
const String FS_CONFIG_COL = 'config';
const String FS_CONFIG_DOC = 'app';
const String FS_WHITELIST_COL = 'whitelist';
const String FS_ADMINS_COL = 'admins';
const String FS_USERS_COL = 'users';
const String FS_REPORTES_COL = 'reportes';

const String FS_AUXILIOS_COL = 'auxilios';
// ================== RANKING / ZONAS (MVP) ==================
// Nota: en esta versión el "zoneKey" es configurable (default: Concordia/ER) para no depender de geocoding.
// Luego podemos migrar a geocoding y asignación automática por Ciudad/Departamento/Provincia.
const String FS_LEADERBOARDS_COL = 'leaderboards';
const String FS_LEDGER_COL = 'ledger';

// Config keys en config/app
const String CFG_ZONE_KEY_DEFAULT = 'zoneKeyDefault'; // ej: 'AR-ER-CONCORDIA'
const String CFG_ZONE_MODE = 'zoneMode'; // 'manual' (MVP) | 'auto_geocoding' (futuro)
const String CFG_FONDO_PERCENT = 'fondoPercent'; // ej 5
const String CFG_FONDO_ENABLED = 'fondoEnabled'; // bool


// ===== AUXILIO: tabla oficial (28/02/2026) =====
const int AUX_PEDIR_AUXILIO_PTS = -400;
const int AUX_COMPLETADO_PTS = 900;
const int AUX_BONUS_RAPIDEZ_PTS = 100;
const int AUX_CANCELACION_INJUST_PTS = -300;

const double AUX_LLEGADA_RADIO_M = 150.0;
const int AUX_PERMANENCIA_MIN_S = 180;
const int AUX_BONUS_VENTANA_MIN = 10;

const String K_BASE_OVERRIDE = 'ro_base_override';

// Clave opcional para acciones admin (marcar PAGADO) en backend.
// En MVP privado puede ir acá; idealmente en el backend con auth fuerte.
const String REMOTE_PAYWALL_ADMIN_KEY = '';

// Cache / prefs
const String K_GATE_CACHE = 'ro_gate_cache_v1';

// Gate cache: si el server cae, solo Founder/Admin pueden usar cache reciente.
const int GATE_CACHE_TTL_MS = 10 * 60 * 1000; // 10 min

const String K_DEVICE_ID = 'ro_device_id_v1';

const int DEFAULT_FREE_LIMIT = 500;

// Fundador / Super Admin fijo
const String FOUNDER_PHONE = '3435064401';
const String APP_NAME = 'Resistencia';

// ================== VERSIONADO OBLIGATORIO ==================
// Subí este número cuando publiques una versión nueva.
const int APP_BUILD_CODE = 3; // ejemplo: 1,2,3...
// El backend puede exigir un mínimo (minBuild) desde /health.

// ================== PUNTOS ==================
const int P_OPERATIVO_VALIDADO_GPS = 300;
const int P_OPERATIVO_VALIDADO_DISTANCIA = 120;
const int P_VALIDAR_APORTE = 25;
const int P_AVISO_ACCIDENTE = 8;
const int P_AVISO_PIQUETE = 8;
const int P_AVISO_CALLE_CORTADA = 10;

// BONUS: cerrar operativo (ya no hay) da unos puntos chicos
const int P_YA_NO_HAY_OPERATIVO = 12;

// ================== VALIDACION REAL ==================
const double VALIDACION_MAX_METROS = 300;
const int VALIDACION_COOLDOWN_MS = 10 * 1000;

// ================== WATCHDOG GPS ==================
const int GPS_WATCHDOG_MS = 10 * 1000;

// ================== ANTI-SPAM (A) ==================
// 1) cooldown por tipo
const int CD_OPERATIVO_MS = 30 * 1000;
const int CD_OTROS_MS = 20 * 1000;

// 2) rate limit: max 4 reportes cada 2 minutos
const int RL_WINDOW_MS = 2 * 60 * 1000;
const int RL_MAX_REPORTES = 4;

// 3) anti-duplicado: mismo tipo + (gps cerca) dentro de 200m en 2 minutos
const double DUP_METROS = 200;
const int DUP_WINDOW_MS = 2 * 60 * 1000;

// ================== ACCESO CERRADO (C) ==================
// PIN Admin para gestionar whitelist (cambialo)
const String ADMIN_PIN = '2580';

// Lista inicial hardcodeada (podés dejarla vacía y cargar desde panel)
const List<String> WHITELIST_INICIAL = [
  // Ej: '5493456123456',
];

// ================== ENUMS ==================
enum AlertaModo { unaSolaVez, repetirCada30s }

enum AvisoSonido { silencioso, vibracion, alarma }

enum ReporteTipo { operativo, accidente, piquete, calleCortada }

enum ReporteEstado { pendiente, validado, falso, expirado, cerrado }

// ================== HELPERS UI ==================
String tipoTexto(ReporteTipo t) {
  switch (t) {
    case ReporteTipo.operativo:
      return 'Operativo';
    case ReporteTipo.accidente:
      return 'Accidente';
    case ReporteTipo.piquete:
      return 'Piquete/Manifestación';
    case ReporteTipo.calleCortada:
      return 'Calle cortada';
  }
}

String vehiculoTexto(String v) {
  switch (v) {
    case 'autos':
      return 'Autos';
    case 'motos':
      return 'Motos';
    case 'ambos':
      return 'Ambos';
    default:
      return v;
  }
}

String controlTexto(String c) {
  switch (c) {
    case 'alcoholemia':
      return 'Alcoholemia';
    case 'documentacion':
      return 'Control de documentación';
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
      return 'pendiente';
    case ReporteEstado.validado:
      return 'validado';
    case ReporteEstado.falso:
      return 'falso';
    case ReporteEstado.expirado:
      return 'expirado';
    case ReporteEstado.cerrado:
      return 'cerrado';
  }
}

String hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String _onlyDigits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

// ================== MODELO ==================
class Reporte {
  final String id;
  final DateTime fecha;
  final ReporteTipo tipo;

  final String vehiculo;
  final String control;
  final String fuerza;

  final double? lat;
  final double? lng;

  int validaciones;
  ReporteEstado estado;

  final int duracionMin;
  bool puntosAcreditados;

  Reporte({
    String? id,
    required this.fecha,
    required this.tipo,
    this.vehiculo = 'autos',
    this.control = 'alcoholemia',
    this.fuerza = 'transito',
    this.lat,
    this.lng,
    this.validaciones = 0,
    this.estado = ReporteEstado.pendiente,
    int? duracionMin,
    this.puntosAcreditados = false,
  })  : duracionMin = duracionMin ?? duracionMinPorTipo(tipo),
        id = id ??
            '${fecha.millisecondsSinceEpoch}_${tipo.name}_${lat?.toStringAsFixed(6) ?? 'nogps'}_${lng?.toStringAsFixed(6) ?? 'nogps'}_${vehiculo}_${control}_${fuerza}';

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
        'lat': lat,
        'lng': lng,
        'validaciones': validaciones,
        'estado': estado.name,
        'duracionMin': duracionMin,
        'puntosAcreditados': puntosAcreditados,
      };

  static Reporte fromMap(Map<String, dynamic> m) {
    final fecha = DateTime.parse(m['fecha'] as String);
    final tipo =
        ReporteTipo.values.firstWhere((e) => e.name == (m['tipo'] as String));

    // compat: estados viejos (si existieran)
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
      control: (m['control'] as String?) ?? 'alcoholemia',
      fuerza: (m['fuerza'] as String?) ?? 'transito',
      lat: (m['lat'] as num?)?.toDouble(),
      lng: (m['lng'] as num?)?.toDouble(),
      validaciones: (m['validaciones'] as num?)?.toInt() ?? 0,
      estado: estado,
      duracionMin: (m['duracionMin'] as num?)?.toInt(),
      puntosAcreditados: (m['puntosAcreditados'] as bool?) ?? false,
    );
  }
}

class GateStatus {
  final bool ok;

  /// true si el backend de gate/paywall está activo (feature encendida)
  final bool paywallEnabled;

  /// compatibilidad con versiones viejas
  bool get gateEnabled => paywallEnabled;

  final int freeLimit;
  final int? userNumber;
  final bool isPaid;

  /// true si ESTE usuario debe pagar (según backend)
  final bool requiresPayment;

  final String message;

  const GateStatus({
    required this.ok,
    bool? paywallEnabled,
    bool? gateEnabled,
    required this.freeLimit,
    required this.userNumber,
    required this.isPaid,
    required this.requiresPayment,
    required this.message,
  }) : paywallEnabled = paywallEnabled ?? gateEnabled ?? false;

  static GateStatus okOffline({String msg = 'Modo offline (cache)'}) {
    return const GateStatus(
      ok: true,
      paywallEnabled: true,
      freeLimit: DEFAULT_FREE_LIMIT,
      userNumber: null,
      isPaid: false,
      requiresPayment: false,
      message: 'Modo offline (cache)',
    );
  }

  static GateStatus error(String msg) {
    return GateStatus(
      ok: false,
      paywallEnabled: true,
      freeLimit: DEFAULT_FREE_LIMIT,
      userNumber: null,
      isPaid: false,
      requiresPayment: true,
      message: msg,
    );
  }

  factory GateStatus.fromJson(Map<String, dynamic> j) {
    // backend típico:
    // { phone, role, userNumber, freeLimit, isPaid, requiresPayment, paywallEnabled? }
    final freeLimit = (j['freeLimit'] as num?)?.toInt() ?? DEFAULT_FREE_LIMIT;
    final userNumber = (j['userNumber'] as num?)?.toInt();
    final isPaid = (j['isPaid'] as bool?) ?? false;
    final requiresPayment = (j['requiresPayment'] as bool?) ?? false;

    final paywallEnabled =
        (j['paywallEnabled'] as bool?) ?? (j['gateEnabled'] as bool?) ?? true;

    return GateStatus(
      ok: true,
      paywallEnabled: paywallEnabled,
      freeLimit: freeLimit,
      userNumber: userNumber,
      isPaid: isPaid,
      requiresPayment: requiresPayment,
      message: 'OK',
    );
  }

  Map<String, dynamic> toJson() => {
        'ok': ok,
        'paywallEnabled': paywallEnabled,
        'freeLimit': freeLimit,
        'userNumber': userNumber,
        'isPaid': isPaid,
        'requiresPayment': requiresPayment,
        'message': message,
      };

  bool get isPaywalled => (paywallEnabled && requiresPayment && !isPaid);
}

// ================== REMOTE PAYWALL / GATE ==================
class RemotePaywallApi {
  static const Duration timeout = Duration(seconds: 6);

  static Uri _u(String path, {required String base}) {
    final b = base.trim();
    if (b.isEmpty) return Uri.parse('https://invalid.local/$path');

    // Normaliza path
    final p = path.startsWith('/') ? path.substring(1) : path;
    final baseUri = Uri.parse(b);

    final joinedPath = (baseUri.path.endsWith('/') || baseUri.path.isEmpty)
        ? '${baseUri.path}$p'
        : '${baseUri.path}/$p';

    return baseUri.replace(path: joinedPath);
  }

  static Future<String?> _loadBaseOverride() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(K_BASE_OVERRIDE);
      if (v == null || v.trim().isEmpty) return null;
      return v.trim();
    } catch (_) {
      return null;
    }
  }

  static Future<void> setBaseOverride(String? base) async {
    final prefs = await SharedPreferences.getInstance();
    if (base == null || base.trim().isEmpty) {
      await prefs.remove(K_BASE_OVERRIDE);
    } else {
      await prefs.setString(K_BASE_OVERRIDE, base.trim());
    }
  }

  static Future<String?> _loadLastGoodBase() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(K_LAST_GOOD_BASE);
      if (v == null || v.trim().isEmpty) return null;
      return v.trim();
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveLastGoodBase(String base) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(K_LAST_GOOD_BASE, base.trim());
    } catch (_) {}
  }

  static Future<List<String>> _baseCandidates() async {
    final list = <String>[];

    final override = await _loadBaseOverride();
    if (override != null && override.trim().isNotEmpty)
      list.add(override.trim());

    final lastGood = await _loadLastGoodBase();
    if (lastGood != null && lastGood.trim().isNotEmpty)
      list.add(lastGood.trim());

    final base = REMOTE_PAYWALL_BASE_URL.trim();
    if (base.isNotEmpty) list.add(base);

    // evita duplicados conservando orden
    final seen = <String>{};
    final out = <String>[];
    for (final b in list) {
      final k = b.trim();
      if (k.isEmpty) continue;
      if (seen.add(k)) out.add(k);
    }
    return out;
  }

  static Future<String> getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(K_DEVICE_ID);
    if (existing != null && existing.trim().isNotEmpty) return existing.trim();

    final now = DateTime.now().millisecondsSinceEpoch;
    final rand = now.toString() + '-' + (now % 100000).toString();
    await prefs.setString(K_DEVICE_ID, rand);
    return rand;
  }

  static Future<Map<String, dynamic>?> _postJson(
    String base,
    String path,
    Map<String, dynamic> body,
  ) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      return await (() async {
        final req = await client.postUrl(_u(path, base: base));
        req.headers.contentType = ContentType.json;
        req.add(utf8.encode(jsonEncode(body)));
        final res = await req.close();
        final raw = await res.transform(utf8.decoder).join();
        if (raw.trim().isEmpty) return <String, dynamic>{};
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) return decoded;
        return {'_raw': raw};
      })()
          .timeout(timeout);
    } finally {
      client.close(force: true);
    }
  }

  static Future<Map<String, dynamic>?> _getJson(
      String base, String path) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      return await (() async {
        final req = await client.getUrl(_u(path, base: base));
        final res = await req.close();
        final raw = await res.transform(utf8.decoder).join();
        if (raw.trim().isEmpty) return <String, dynamic>{};
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) return decoded;
        return {'_raw': raw};
      })()
          .timeout(timeout);
    } finally {
      client.close(force: true);
    }
  }

  static Future<GateStatus> registerOrGetStatus({
    required String phoneDigits,
    String? deviceId,
  }) async {
    if (!USE_REMOTE_PAYWALL || REMOTE_PAYWALL_BASE_URL.trim().isEmpty) {
      return GateStatus(
        ok: true,
        paywallEnabled: false,
        freeLimit: DEFAULT_FREE_LIMIT,
        userNumber: null,
        isPaid: false,
        requiresPayment: false,
        message: 'Remote paywall desactivado',
      );
    }

    final did = deviceId ?? await RemotePaywallApi.getOrCreateDeviceId();
    final bases = await _baseCandidates();

    for (final base in bases) {
      try {
        final j = await _postJson(base, 'register', {
          'phone': phoneDigits,
          'deviceId': did,
        });
        if (j != null) {
          await _saveLastGoodBase(base);
          return GateStatus.fromJson(j);
        }
      } catch (_) {
        // probamos la próxima base
      }
    }

    return GateStatus.error(
        'No se pudo contactar al servidor (todas las URLs fallaron).');
  }

  static Future<GateStatus> markPaid({
    required String adminPhoneDigits,
    required String phoneDigits,
    required bool paid,
  }) async {
    final bases = await _baseCandidates();

    for (final base in bases) {
      try {
        final j = await _postJson(base, 'markPaid', {
          'adminPhone': adminPhoneDigits,
          'phone': phoneDigits,
          'paid': paid,
        });

        if (j != null) {
          await _saveLastGoodBase(base);
          return GateStatus.fromJson(j);
        }
      } catch (_) {}
    }

    return GateStatus.error('No se pudo ejecutar /markPaid (URLs fallaron).');
  }

  // -------- Cache local (para offline) --------
  static Future<void> cacheStatus(String phoneDigits, GateStatus st) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(K_GATE_CACHE);
    final map = raw == null
        ? <String, dynamic>{}
        : (jsonDecode(raw) as Map<String, dynamic>);

    map[phoneDigits] = {
      'ts': DateTime.now().millisecondsSinceEpoch,
      'data': st.toJson(),
    };

    await prefs.setString(K_GATE_CACHE, jsonEncode(map));
  }

  static Future<Map<String, dynamic>?> _readCachedMeta(
      String phoneDigits) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(K_GATE_CACHE);
    if (raw == null) return null;
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final v = map[phoneDigits];
    if (v is Map<String, dynamic>) return v;
    return null;
  }

  static Future<GateStatus?> readCached(String phoneDigits) async {
    final meta = await _readCachedMeta(phoneDigits);
    if (meta == null) return null;
    final data = meta['data'];
    if (data is Map) {
      final j = data.map((k, v) => MapEntry('$k', v));
      return GateStatus.fromJson(j);
    }
    return null;
  }

  static Future<int?> readCachedAgeMs(String phoneDigits) async {
    final meta = await _readCachedMeta(phoneDigits);
    if (meta == null) return null;
    final ts = (meta['ts'] as num?)?.toInt();
    if (ts == null) return null;
    return DateTime.now().millisecondsSinceEpoch - ts;
  }

  static Future<GateStatus?> loadCachedStatus(String phoneDigits) =>
      readCached(phoneDigits);

  // -------- Version gate --------
  static Future<int?> getMinBuildFromHealth() async {
    final bases = await _baseCandidates();
    for (final base in bases) {
      try {
        final j = await _getJson(base, 'health');
        if (j == null) continue;

        // soporta "minBuild" o "min_build"
        final mb = j['minBuild'] ?? j['min_build'] ?? j['min_version_code'];
        if (mb is num) {
          await _saveLastGoodBase(base);
          return mb.toInt();
        }
      } catch (_) {}
    }
    return null;
  }
}

class UpdateRequiredScreen extends StatelessWidget {
  final int minBuild;
  const UpdateRequiredScreen({super.key, required this.minBuild});

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false, // bloqueante
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Actualización requerida'),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Debe actualizar la aplicación para continuar',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Hay una versión mínima obligatoria configurada por el servidor.',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Cerrá la app y actualizá desde el instalador que te pase el Fundador/Admin.',
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

class OfflineGateScreen extends StatefulWidget {
  final String message;
  final String phoneDigits;
  final Future<void> Function() onRetry;

  const OfflineGateScreen({
    super.key,
    required this.message,
    required this.phoneDigits,
    required this.onRetry,
  });

  @override
  State<OfflineGateScreen> createState() => _OfflineGateScreenState();
}

class _OfflineGateScreenState extends State<OfflineGateScreen> {
  Timer? _t;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    // 🔁 Auto-reintento: cada 6s revalida. Si el servidor vuelve, regresa al gate oficial de Firestore.
    _t = Timer.periodic(const Duration(seconds: 6), (_) => _check());
    Future.delayed(const Duration(milliseconds: 600), _check);
  }

  @override
  void dispose() {
    _t?.cancel();
    // (sin controllers locales para dispose aquí)
    super.dispose();
  }

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    try {
      await widget.onRetry();

      // Si luego del retry el gate queda OK y no paywalled, volvemos al gate oficial de Firestore.
      final me = _onlyDigits(widget.phoneDigits);
      if (me.isEmpty) return;

      final st = await RemotePaywallApi.loadCachedStatus(me);
      if (st != null && st.ok && !st.isPaywalled) {
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const FirestoreAccessGate()),
          (r) => false,
        );
      }
    } catch (_) {
      // silencioso
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Servidor no disponible'),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '🔒 Acceso temporalmente bloqueado',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'No se pudo validar tu acceso con el servidor.',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  if (widget.message.trim().isNotEmpty)
                    Text('Detalle: ${widget.message}'),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        try {
                          await widget.onRetry();
                        } catch (_) {}
                        if (!mounted) return;
                        setState(() {});
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Auto-reintento cada 6s (se destraba solo cuando el servidor vuelve).',
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

class FirestorePaywallScreen extends StatelessWidget {
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

  const FirestorePaywallScreen({
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

  @override
  Widget build(BuildContext context) {
    final n = userNumber ?? 0;
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '🔒 Suscripción requerida',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  Text('Tu número: $phoneDigits10',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text('N° de usuario: $n (gratis hasta $freeLimit)',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  Text(
                    'Monto: $monthlyPriceArs ARS • ${subscriptionDays} días',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 12),
                  if (payAlias.trim().isNotEmpty)
                    SelectableText('Alias: $payAlias',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (payCbu.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    SelectableText('CBU/CVU: $payCbu',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                  if (payHolder.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    SelectableText('Titular: $payHolder',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
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
                          await Clipboard.setData(ClipboardData(text: payAlias.trim()));
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
                          await Clipboard.setData(ClipboardData(text: payCbu.trim()));
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
                          final lines = <String>[];
                          lines.add('Resistencia – Pago de acceso');
                          lines.add('Número: $phoneDigits10');
                          lines.add('N° usuario: ${userNumber ?? 0} (gratis hasta $freeLimit)');
                          lines.add('Monto: $monthlyPriceArs ARS • ${subscriptionDays} días');
                          if (payAlias.trim().isNotEmpty) lines.add('Alias: $payAlias');
                          if (payCbu.trim().isNotEmpty) lines.add('CBU/CVU: $payCbu');
                          if (payHolder.trim().isNotEmpty) lines.add('Titular: $payHolder');
                          if (payNote.trim().isNotEmpty) lines.add('Nota: $payNote');
                          final full = lines.join('\n');
                          await Clipboard.setData(ClipboardData(text: full));
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
                          final lines = <String>[];
                          lines.add('Resistencia – Pago de acceso');
                          lines.add('Número: $phoneDigits10');
                          lines.add('N° usuario: ${userNumber ?? 0} (gratis hasta $freeLimit)');
                          lines.add('Monto: $monthlyPriceArs ARS • ${subscriptionDays} días');
                          if (payAlias.trim().isNotEmpty) lines.add('Alias: $payAlias');
                          if (payCbu.trim().isNotEmpty) lines.add('CBU/CVU: $payCbu');
                          if (payHolder.trim().isNotEmpty) lines.add('Titular: $payHolder');
                          if (payNote.trim().isNotEmpty) lines.add('Nota: $payNote');
                          final full = lines.join('\n');

                          final enc = Uri.encodeComponent(full);
                          final waUri = Uri.parse('whatsapp://send?text=$enc');
                          final webWa = Uri.parse('https://wa.me/?text=$enc');

                          try {
                            if (await canLaunchUrl(waUri)) {
                              await launchUrl(waUri, mode: LaunchMode.externalApplication);
                              return;
                            }
                          } catch (_) {}

                          try {
                            if (await canLaunchUrl(webWa)) {
                              await launchUrl(webWa, mode: LaunchMode.externalApplication);
                              return;
                            }
                          } catch (_) {}

                          await Share.share(full, subject: 'Pago – $APP_NAME');
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
                            const SnackBar(content: Text('Reintentando validación...')),
                          );
                        }
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Ya pagué / Reintentar'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Cuando el Admin te habilite, se destraba solo.',
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




class AccessDiagnosis {
  final String phoneDigits10;
  final bool whitelistByDoc;
  final bool whitelistByField;
  final bool adminByDoc;
  final bool adminByField;
  final bool enabled;
  final bool suspended;
  final String role;
  final bool requiresPayment;
  final bool isPaid;
  final int? userNumber;
  final String reason;

  const AccessDiagnosis({
    required this.phoneDigits10,
    required this.whitelistByDoc,
    required this.whitelistByField,
    required this.adminByDoc,
    required this.adminByField,
    required this.enabled,
    required this.suspended,
    required this.role,
    required this.requiresPayment,
    required this.isPaid,
    required this.userNumber,
    required this.reason,
  });

  bool get whitelistFound => whitelistByDoc || whitelistByField;
  bool get adminFound => adminByDoc || adminByField;
}

// ================== FIRESTORE ACCESS GATE ==================
// Reemplaza whitelist LOCAL por whitelist CENTRAL en Firestore + login OTP (Firebase Auth).
class FirestoreAccessGate extends StatefulWidget {
  const FirestoreAccessGate({super.key});

  @override
  State<FirestoreAccessGate> createState() => _FirestoreAccessGateState();
}

class _FirestoreAccessGateState extends State<FirestoreAccessGate> {
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _codeCtrl = TextEditingController();

  bool _sending = false;
  bool _verifying = false;
  String? _verificationId;
  String? _error;

  // Gate result
  bool _allowed = false;
  bool _isAdmin = false;
  bool _requiresPayment = false;
  int? _userNumber;
  int _freeLimit = 500;
  int _priceMonthly = 500;
  String _founderPhone = _onlyDigits(FOUNDER_PHONE);
  // Datos de pago editables desde Firestore config/app
  String _payAlias = '';
  String _payCbu = '';
  String _payHolder = '';
  String _payNote = '';
  int _subscriptionDays = 30;
  bool _payEnabled = true;
  int _minBuild = 0;
  AccessDiagnosis? _diag;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAppConfig() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection(FS_CONFIG_COL)
          .doc(FS_CONFIG_DOC)
          .get();
      final d = snap.data() ?? {};
      setState(() {
        _freeLimit = (d['freeLimit'] as num?)?.toInt() ?? _freeLimit;
        _priceMonthly = (d['monthlyPriceArs'] as num?)?.toInt() ?? _priceMonthly;
        _payAlias = (d['payAlias'] as String?) ?? _payAlias;
        _payCbu = (d['payCbu'] as String?) ?? _payCbu;
        _payHolder = (d['payHolder'] as String?) ?? _payHolder;
        _payNote = (d['payNote'] as String?) ?? _payNote;
        _subscriptionDays = (d['subscriptionDays'] as num?)?.toInt() ?? _subscriptionDays;
        _payEnabled = (d['payEnabled'] as bool?) ?? _payEnabled;
        _minBuild = (d['minBuild'] as num?)?.toInt() ?? _minBuild;
      });
    } catch (_) {
      // si falla, usar defaults locales
    }
  }

  Future<int> _assignUserNumberTxn(DocumentReference<Map<String, dynamic>> userRef) async {
    // contador global en config/app: nextUserNumber (arranca en 0)
    final cfgRef = FirebaseFirestore.instance.collection(FS_CONFIG_COL).doc(FS_CONFIG_DOC);
    return FirebaseFirestore.instance.runTransaction<int>((tx) async {
      final cfgSnap = await tx.get(cfgRef);
      final cfg = cfgSnap.data() as Map<String, dynamic>? ?? {};
      final next = (cfg['nextUserNumber'] as num?)?.toInt() ?? 0;
      final newNumber = next + 1;
      tx.set(cfgRef, {'nextUserNumber': newNumber}, SetOptions(merge: true));
      tx.set(userRef, {'userNumber': newNumber}, SetOptions(merge: true));
      return newNumber;
    });
  }

  Future<Map<String, dynamic>> _ensureUserDoc(String phoneDigits10) async {
    final ref = FirebaseFirestore.instance.collection(FS_USERS_COL).doc(phoneDigits10);
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({
        'phone': phoneDigits10,
        'createdAt': FieldValue.serverTimestamp(),
        'points': 0,
        'reputation': 0,
        'auxCredits': 0,
      }, SetOptions(merge: true));
    }
    // asegurar userNumber
    final s2 = await ref.get();
    var data = s2.data() ?? <String, dynamic>{};
    if (data['userNumber'] == null) {
      final n = await _assignUserNumberTxn(ref);
      data = (await ref.get()).data() ?? data;
      data['userNumber'] = n;
    }
    return data;
  }

  bool _isPaidNow(Map<String, dynamic> userData) {
    final pu = userData['paidUntil'];
    if (pu is Timestamp) {
      return pu.toDate().isAfter(DateTime.now());
    }
    return false;
  }
Future<void> _bootstrap() async {
    await _loadAppConfig();
    // Si ya hay sesión, validar gate.
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await _loadGateForUser(user);
      }
    } catch (_) {
      // Firebase no configurado todavía -> caer a modo legacy.
    }
    if (mounted) setState(() {});
  }

  String _normalizeArPhone(String input) {
    final d = _onlyDigits(input);
    if (d.isEmpty) return '';
    if (d.startsWith('549') && d.length >= 13) return d.substring(d.length - 10);
    if (d.startsWith('54') && d.length >= 12) return d.substring(d.length - 10);
    if (d.length == 11 && d.startsWith('0')) return d.substring(1);
    if (d.length == 11 && d.startsWith('9')) return d.substring(1);
    if (d.length > 10) return d.substring(d.length - 10);
    return d;
  }

  String _formatE164Ar(String phoneDigits10) {
    // Argentina (móviles): suele requerir +549 + 10 dígitos.
    return '+549$phoneDigits10';
  }

  Future<void> _sendCode() async {
    setState(() {
      _error = null;
      _sending = true;
    });

    try {
      final digits = _normalizeArPhone(_phoneCtrl.text);
      if (digits.length != 10) {
        throw Exception('Ingresá tu número (10 dígitos, sin +54). Ej: 3435064401');
      }

      
      // ---- Anti-abuso OTP (local) ----
      final prefs = await SharedPreferences.getInstance();
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      final lastSent = prefs.getInt(K_OTP_LAST_SENT_MS) ?? 0;
      if (nowMs - lastSent < 60000) {
        final waitSec = ((60000 - (nowMs - lastSent)) / 1000).ceil();
        throw Exception('Esperá $waitSec segundos para pedir otro código.');
      }

      final winStart = prefs.getInt(K_OTP_WINDOW_START_MS) ?? 0;
      final winCount = prefs.getInt(K_OTP_WINDOW_COUNT) ?? 0;
      if (winStart == 0 || nowMs - winStart > 10 * 60 * 1000) {
        // nueva ventana
        await prefs.setInt(K_OTP_WINDOW_START_MS, nowMs);
        await prefs.setInt(K_OTP_WINDOW_COUNT, 0);
      } else {
        if (winCount >= 3) {
          throw Exception('Demasiados intentos. Esperá 10 minutos e intentá de nuevo.');
        }
      }

      // Reservamos el intento antes de enviar (para evitar spam).
      await prefs.setInt(K_OTP_LAST_SENT_MS, nowMs);
      await prefs.setInt(K_OTP_WINDOW_COUNT, (prefs.getInt(K_OTP_WINDOW_COUNT) ?? 0) + 1);
await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: _formatE164Ar(digits),
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Auto-verificación (algunos teléfonos)
          try {
            final credUser = await FirebaseAuth.instance.signInWithCredential(credential);
            await _loadGateForUser(credUser.user!);
          } catch (e) {
            if (mounted) setState(() => _error = 'No se pudo verificar automáticamente: $e');
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          if (!mounted) return;
          String msg = e.message ?? 'Falló verificación OTP';
          if (e.code == 'too-many-requests') {
            msg = 'Firebase bloqueó temporalmente este dispositivo/número por demasiados intentos. Esperá un rato y probá de nuevo.';
          } else if (e.code == 'captcha-check-failed') {
            msg = 'Falló el chequeo anti-abuso (Play Services/reCAPTCHA). Actualizá Google Play Services y reintentá.';
          } else if (e.code == 'invalid-phone-number') {
            msg = 'Número inválido. Ingresalo en formato local (10 dígitos, sin +54).';
          }
          setState(() => _error = msg);
        },
        codeSent: (String verificationId, int? resendToken) {
          if (mounted) {
            setState(() {
              _verificationId = verificationId;
            });
          }
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          if (mounted) {
            setState(() {
              _verificationId = verificationId;
            });
          }
        },
      );
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _verifyCode() async {
    final vid = _verificationId;
    if (vid == null || vid.isEmpty) {
      setState(() => _error = 'Primero pedí el código.');
      return;
    }

    setState(() {
      _error = null;
      _verifying = true;
    });

    try {
      final sms = _onlyDigits(_codeCtrl.text);
      if (sms.length < 4) throw Exception('Código inválido');

      final cred = PhoneAuthProvider.credential(verificationId: vid, smsCode: sms);
      final res = await FirebaseAuth.instance.signInWithCredential(cred);

      final user = res.user;
      if (user == null) throw Exception('No se pudo iniciar sesión');

      await _loadGateForUser(user);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _loadGateForUser(User user) async {
    await _loadAppConfig();

    final raw = user.phoneNumber ?? '';
    final phoneDigits10 = _normalizeArPhone(raw);
    if (phoneDigits10.length != 10) {
      throw Exception('No se pudo leer tu número desde Firebase. Reingresá y verificá de nuevo.');
    }

    final fs = FirebaseFirestore.instance;
    final wlByDocRef = fs.collection(FS_WHITELIST_COL).doc(phoneDigits10);
    final adminByDocRef = fs.collection(FS_ADMINS_COL).doc(phoneDigits10);

    final wlByDocSnap = await wlByDocRef.get();
    final adminByDocSnap = await adminByDocRef.get();
    final wlByFieldQuery = await fs.collection(FS_WHITELIST_COL).where('phone', isEqualTo: phoneDigits10).limit(1).get();
    final adminByFieldQuery = await fs.collection(FS_ADMINS_COL).where('phone', isEqualTo: phoneDigits10).limit(1).get();

    final bool founder = phoneDigits10 == _onlyDigits(FOUNDER_PHONE);
    final bool whitelistByDoc = wlByDocSnap.exists;
    final bool whitelistByField = wlByFieldQuery.docs.isNotEmpty;
    final bool adminByDoc = adminByDocSnap.exists;
    final bool adminByField = adminByFieldQuery.docs.isNotEmpty;

    final Map<String, dynamic> wlData = whitelistByDoc
        ? (wlByDocSnap.data() ?? <String, dynamic>{})
        : (whitelistByField ? wlByFieldQuery.docs.first.data() : <String, dynamic>{});
    final Map<String, dynamic> adminData = adminByDoc
        ? (adminByDocSnap.data() ?? <String, dynamic>{})
        : (adminByField ? adminByFieldQuery.docs.first.data() : <String, dynamic>{});

    final bool enabled = founder
        ? true
        : ((wlData['enabled'] as bool?) ?? (adminData['enabled'] as bool?) ?? true);
    final bool suspended = founder
        ? false
        : ((wlData['suspended'] as bool?) ?? (adminData['suspended'] as bool?) ?? false);
    final String role = founder
        ? 'founder'
        : ((wlData['role'] as String?) ?? (adminData['role'] as String?) ?? 'usuario');

    final bool allowedByList = founder || whitelistByDoc || whitelistByField || adminByDoc || adminByField;
    final bool isAdmin = founder || adminByDoc || adminByField;

    final userData = await _ensureUserDoc(phoneDigits10);
    final userNumber = (userData['userNumber'] as num?)?.toInt();
    final bool isPaid = _isPaidNow(userData);
    bool requiresPayment = false;
    if (_payEnabled && userNumber != null && userNumber > _freeLimit) {
      requiresPayment = !isPaid;
    }

    bool allowed = allowedByList && enabled && !suspended;
    String reason = 'OK';
    if (!allowedByList) {
      allowed = false;
      reason = 'Número no invitado';
    } else if (!enabled) {
      allowed = false;
      reason = 'Número deshabilitado';
    } else if (suspended) {
      allowed = false;
      reason = 'Usuario suspendido';
    } else if (requiresPayment) {
      allowed = true;
      reason = 'Suscripción requerida';
    }

    if (!mounted) return;
    setState(() {
      _allowed = allowed;
      _isAdmin = isAdmin;
      _requiresPayment = requiresPayment;
      _userNumber = userNumber;
      _diag = AccessDiagnosis(
        phoneDigits10: phoneDigits10,
        whitelistByDoc: whitelistByDoc,
        whitelistByField: whitelistByField,
        adminByDoc: adminByDoc,
        adminByField: adminByField,
        enabled: enabled,
        suspended: suspended,
        role: role,
        requiresPayment: requiresPayment,
        isPaid: isPaid,
        userNumber: userNumber,
        reason: reason,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Si Firebase no está listo, caemos al gate legacy
    final hasFirebase = (() {
      try {
        return Firebase.apps.isNotEmpty;
      } catch (_) {
        return false;
      }
    })();

    if (!hasFirebase) {
      return const _FirebaseMissingScreen();
    }


    final currentUser = FirebaseAuth.instance.currentUser;

    // Si ya hay sesión válida y pasó el gate, entrar directo a la app.
    if (currentUser != null && _allowed && !_requiresPayment) {
      final pd = _normalizeArPhone(currentUser.phoneNumber ?? _founderPhone);
      return AppShell(isAdmin: _isAdmin, myPhone: pd.isEmpty ? _founderPhone : pd);
    }

    // Si ya hay sesión y la gate dice "bloqueado", mostramos motivo.
    if (currentUser != null && (!_allowed || _requiresPayment)) {
      return _BlockedScreen(
        allowed: _allowed,
        requiresPayment: _requiresPayment,
        userNumber: _userNumber,
        freeLimit: _freeLimit,
        priceMonthly: _priceMonthly,
        diagnosis: _diag,
        onLogout: () async {
          await FirebaseAuth.instance.signOut();
          if (mounted) {
            setState(() {
              _verificationId = null;
              _codeCtrl.clear();
              _phoneCtrl.clear();
              _allowed = false;
              _requiresPayment = false;
              _userNumber = null;
            });
          }
        },
        onRetry: () async {
          final u = FirebaseAuth.instance.currentUser;
          if (u != null) await _loadGateForUser(u);
        },
      );
    }

    // UI OTP
    final waitingCode = (_verificationId != null);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Acceso (OTP)'),
        backgroundColor: Colors.black,
      ),
      body: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Text(
              waitingCode
                  ? 'Ingresá el código SMS'
                  : 'Ingresá tu número (10 dígitos, sin +54)',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (!waitingCode) ...[
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Número',
                  hintText: 'Ej: 3435064401',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _sending ? null : _sendCode,
                child: Text(_sending ? 'Enviando...' : 'Enviar código'),
              ),
            ] else ...[
              TextField(
                controller: _codeCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Código',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _verifying ? null : _verifyCode,
                child: Text(_verifying ? 'Verificando...' : 'Verificar y entrar'),
              ),
              TextButton(
                onPressed: () => setState(() => _verificationId = null),
                child: const Text('Cambiar número'),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const Spacer(),
            const Text(
              'Si te bloquea, es porque tu número no está invitado en Firestore (whitelist).',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}


class _FirebaseMissingScreen extends StatelessWidget {
  const _FirebaseMissingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Acceso')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            SizedBox(height: 8),
            Text(
              'Firebase no configurado',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Text(
              'Esta versión requiere Firebase (OTP + Firestore).\n\n'
              'Solución:\n'
              '1) Colocá el google-services.json en android/app/\n'
              '2) Aplicá el plugin de Google Services en Gradle\n'
              '3) Recompilá e instalá de nuevo\n\n'
              'Si estás en RELEASE, además necesitás cargar SHA-1/SHA-256 en Firebase.',
              style: TextStyle(fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlockedScreen extends StatelessWidget {
  const _BlockedScreen({
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
        ? '⛔ Acceso bloqueado'
        : (requiresPayment ? '🔒 Acceso requiere pago' : '⛔ Bloqueado');

    final msg = !allowed
        ? (diagnosis?.reason == 'Número deshabilitado'
            ? 'Tu número figura en la invitación, pero está deshabilitado. Pedile al admin que lo habilite.'
            : diagnosis?.reason == 'Usuario suspendido'
                ? 'Tu acceso fue suspendido. Pedile al admin que revise tu estado.'
                : 'Tu número no figura como habilitado. Pedile al admin que revise la whitelist.')
        : '''Tu usuario es #${userNumber ?? "-"}.
Se superó el límite gratis ($freeLimit).
Precio mensual: $priceMonthly ARS.
Pedile al admin que te habilite el pago.''';

    final d = diagnosis;
    return Scaffold(
      appBar: AppBar(title: const Text('Acceso')),
      body: Padding(
        padding: const EdgeInsets.all(18),
        child: ListView(
          children: [
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
                    title: const Text('Diagnóstico técnico', style: TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(d.reason),
                    children: [
                      _diagRow('Número leído', d.phoneDigits10),
                      _diagRow('Whitelist por ID', d.whitelistByDoc ? 'Sí' : 'No'),
                      _diagRow('Whitelist por campo phone', d.whitelistByField ? 'Sí' : 'No'),
                      _diagRow('Admin por ID', d.adminByDoc ? 'Sí' : 'No'),
                      _diagRow('Admin por campo phone', d.adminByField ? 'Sí' : 'No'),
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
            ElevatedButton(onPressed: onRetry, child: const Text('Reintentar')),
            TextButton(onPressed: onLogout, child: const Text('Salir / Cambiar cuenta')),
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
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

// LEGACY: flujo anterior, ya no es el acceso oficial.
class AccessGate extends StatefulWidget {
  final String myPhone;
  const AccessGate({required this.myPhone, super.key});

  @override
  State<AccessGate> createState() => _AccessGateState();
}

class _AccessGateState extends State<AccessGate> {
  bool cargando = true;
  bool permitido = false;
  bool isAdmin = false;
  bool configFinal = false;
  // (server url ctrl vive en AdminPanel)

  // Remote paywall state
  GateStatus? gate;
  bool gateLoading = false;

  String? phone;

  List<String> whitelist = [];
  List<String> admins = [];

  bool _savingFinal = false;

  Future<void> _loadConfigFinal() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getBool(K_CONFIG_FINAL) ?? false;
    if (mounted) setState(() => configFinal = v);
  }

  Future<void> _finalizarConfiguracion() async {
    if (_savingFinal) return;
    setState(() => _savingFinal = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(K_CONFIG_FINAL, true);
    if (mounted) {
      setState(() {
        configFinal = true;
        _savingFinal = false;
      });
    }
  }

  bool _computeIsAdmin(String phoneDigits) {
    // ✅ MODELO "PRO": admins por LISTA (sin PIN)
    // Bootstrap seguro/simple:
    // - Si todavía NO hay admins definidos, el primer usuario habilitado (whitelist) actúa como admin.
    // - Apenas agrega admins, la app pasa a exigir pertenecer a la lista de admins.
    if (admins.isEmpty) return whitelist.contains(phoneDigits);
    return admins.contains(phoneDigits);
  }

  void _ensureFounder() {
    final f = _onlyDigits(FOUNDER_PHONE);
    if (f.isEmpty) return;
    if (!whitelist.contains(f)) whitelist.add(f);
    if (!admins.contains(f)) admins.add(f);
    whitelist = whitelist.toSet().toList()..sort();
    admins = admins.toSet().toList()..sort();
  }

  Future<void> _refreshRemoteGate(String phoneDigits) async {
    if (!mounted) return;

    setState(() => gateLoading = true);
    try {
      // 1) cache primero (para modo sin internet)
      final cached = await RemotePaywallApi.readCached(phoneDigits);
      if (cached != null && mounted) setState(() => gate = cached);

      // 2) pide al servidor (con timeout total)
      try {
        final st =
            await RemotePaywallApi.registerOrGetStatus(phoneDigits: phoneDigits)
                .timeout(const Duration(seconds: 6));

        // Guardamos/cacheamos siempre lo que venga si es OK;
        // si no es OK, igual actualizamos gate para mostrar mensaje.
        if (st.ok) {
          await RemotePaywallApi.cacheStatus(phoneDigits, st);
        }
        if (mounted) setState(() => gate = st);
      } catch (_) {
        // Si el server no responde, nos quedamos con cache (si había).
      }
    } finally {
      if (mounted) setState(() => gateLoading = false);
    }
  }

  bool _passesPaywall(String phoneDigits) {
    // Fundador siempre pasa (por si el server cae, no te deja afuera)
    final digits = _onlyDigits(phoneDigits);
    if (digits == _onlyDigits(FOUNDER_PHONE)) return true;

    // Si no usamos gate remoto, dejamos pasar.
    if (!USE_REMOTE_PAYWALL) return true;

    // Regla segura (anti-bloqueo): si NO hay respuesta del server o gate no está OK,
// NO bloqueamos. Dejamos entrar por whitelist local y mostramos estado Offline en UI.
if (gate == null) return true;
if (gate!.ok == false) return true;

// Si el server respondió OK y requiere pago y NO está pago => bloquea.
if (gate!.isPaywalled) return false;

return true;
  }

  Future<void> _loadAccess() async {
    final prefs = await SharedPreferences.getInstance();

    // ✅ SIEMPRE liberamos "cargando", pase lo que pase (blindaje anti-logo).
    try {
      configFinal = prefs.getBool(K_CONFIG_FINAL) ?? false;

      // bootstrap: si no existe, crea con whitelist inicial y admins iniciales
      final raw = prefs.getString(K_ACCESS);
      if (raw == null) {
        whitelist = List.from(WHITELIST_INICIAL);
        admins = const []; // admins iniciales vacíos (bootstrap por whitelist)
        await prefs.setString(
          K_ACCESS,
          jsonEncode({
            'whitelist': whitelist,
            'admins': admins,
            'phone': null,
            'allowed': false,
          }),
        );
      } else {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        whitelist = (data['whitelist'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList();

        admins = (data['admins'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList();

        phone = data['phone'] as String?;
        permitido = (data['allowed'] as bool?) ?? false;
      }

      // ✅ Fundador/Super Admin fijo (anti-bloqueo)
      _ensureFounder();
      await _saveAccess(
        phone: phone != null ? _onlyDigits(phone!) : null,
        allowed: permitido,
        whitelist: whitelist,
        admins: admins,
      );

      // si ya hay teléfono guardado, recalcula allowed/admin
      if (phone != null && phone!.trim().isNotEmpty) {
        final n = _onlyDigits(phone!);
        permitido = whitelist.contains(n);
        isAdmin = permitido ? _computeIsAdmin(n) : false;

        if (permitido) {
          // ✅ el primer render NO depende de red.
          // Revalidamos con timeout y sin dejar la app colgada.
          try {
            await _refreshRemoteGate(n);
          } catch (_) {}
          // aplica paywall SOLO si es usuario común (admin siempre entra)
          if (!isAdmin && !_passesPaywall(n)) {
            permitido = false;
          }
        }

        await _saveAccess(
          phone: n,
          allowed: permitido,
          whitelist: whitelist,
          admins: admins,
        );
      }
    } catch (_) {
      // Si algo falla, no trabamos el arranque.
    } finally {
      if (mounted) setState(() => cargando = false);
    }
  }

  Future<void> _saveAccess({
    String? phone,
    required bool allowed,
    required List<String> whitelist,
    required List<String> admins,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      K_ACCESS,
      jsonEncode({
        'whitelist': whitelist,
        'admins': admins,
        'phone': phone,
        'allowed': allowed,
      }),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadConfigFinal();
    _loadAccess();
  }

  Future<void> _pedirTelefono() async {
    String tmp = phone ?? '';

    final res = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Acceso privado'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Ingresá tu número (solo dígitos, ej: 5493456...)',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            TextField(
              keyboardType: TextInputType.phone,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Teléfono'),
              onChanged: (v) => tmp = v,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, tmp),
              child: const Text('Continuar')),
        ],
      ),
    );

    if (res == null) return;

    final n = _onlyDigits(res);
    final ok = whitelist.contains(n);

    phone = n;
    permitido = ok;
    isAdmin = ok ? _computeIsAdmin(n) : false;

    // ✅ Remote paywall (contador global 500 gratis)
    if (permitido) {
      await _refreshRemoteGate(n);
      if (!isAdmin && !_passesPaywall(n)) {
        permitido = false;
      }
    }

    await _saveAccess(
        phone: phone, allowed: permitido, whitelist: whitelist, admins: admins);

    setState(() {});
    if (!permitido && ok) {
      _snack('💳 Acceso bloqueado por paywall (superó el límite gratis).');
    } else if (!ok) _snack('⛔ Número no habilitado');
  }

  Future<void> _abrirAdmin() async {
    // Sin PIN. Solo admins (o bootstrap: admins vacíos y usuario habilitado).
    if (phone == null || phone!.isEmpty) {
      _snack('Primero ingresá tu número.');
      return;
    }

    final n = _onlyDigits(phone!);
    final okWh = whitelist.contains(n);
    final okAdmin = okWh && _computeIsAdmin(n);

    if (!okAdmin) {
      _snack('⛔ No sos Admin. Pedí que te agreguen a la lista de admins.');
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminPanelScreen(
          initialWhitelist: whitelist,
          initialAdmins: admins,
          myPhone: n,
          onSave: (newWhitelist, newAdmins) async {
            whitelist = newWhitelist
                .map(_onlyDigits)
                .where((e) => e.isNotEmpty)
                .toSet()
                .toList()
              ..sort();

            admins = newAdmins
                .map(_onlyDigits)
                .where((e) => e.isNotEmpty)
                .toSet()
                .toList()
              ..sort();

            // recalcular acceso
            permitido = whitelist.contains(n);
            isAdmin = permitido ? _computeIsAdmin(n) : false;

            await _saveAccess(
              phone: phone,
              allowed: permitido,
              whitelist: whitelist,
              admins: admins,
            );

            setState(() {});
          },
          onResetAccess: () async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove(K_ACCESS);

            whitelist = List.from(WHITELIST_INICIAL);
            admins = const []; // vuelve a bootstrap por whitelist
            phone = null;
            permitido = false;
            isAdmin = false;

            await _saveAccess(
                phone: null,
                allowed: false,
                whitelist: whitelist,
                admins: admins);
            _snack('🔄 Acceso reseteado');
            setState(() {});
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (cargando) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (permitido) {
      // ✅ ENCHUFE LIMPIO: mañana reemplazás AppShell sin tocar el gate
      return AppShell(isAdmin: isAdmin, myPhone: _onlyDigits(widget.myPhone));
    }

    final pd = _onlyDigits(widget.myPhone);
    if (gate != null && gate!.isPaywalled && pd.isNotEmpty) {
      return FirestorePaywallScreen(
        phoneDigits10: pd,
        freeLimit: gate?.freeLimit ?? DEFAULT_FREE_LIMIT,
        userNumber: gate?.userNumber,
        monthlyPriceArs: 500,
        subscriptionDays: 30,
        payAlias: '',
        payCbu: '',
        payHolder: '',
        payNote: 'Acceso bloqueado por paywall remoto. Pedí habilitación al administrador.',
        onRetry: () async {
          await _refreshRemoteGate(pd);
          if (mounted) setState(() {});
        },
      );
    }

    if (USE_REMOTE_PAYWALL) {
      final me = _onlyDigits(widget.myPhone);
      final founder = _onlyDigits(FOUNDER_PHONE);
      final isFounder = me == founder;

      // ✅ Si el server está caído (y no hay cache OK), mostramos pantalla OFFLINE para reintentar.
      if (!isFounder && (gate == null || gate!.ok == false)) {
        return OfflineGateScreen(
          phoneDigits: _onlyDigits(widget.myPhone),
          message: gate?.message ?? 'No se pudo validar con el servidor',
          onRetry: () async {
            final p = _onlyDigits(widget.myPhone);
            if (p.isNotEmpty) {
              await _refreshRemoteGate(p);
            }
            if (mounted) setState(() {});
          },
        );
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Acceso restringido'),
        actions: [
          if (isAdmin)
            IconButton(
              onPressed: _abrirAdmin,
              icon: const Icon(Icons.admin_panel_settings),
              tooltip: 'Admin',
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (isAdmin)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('🛡️ Admin',
                        style: TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    const Text(
                      'Administradores + whitelist',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          // ✅ Panel Admin oficial: Firestore (sin SharedPreferences / FileStore).
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => FirestoreAdminPanelScreen(
                                myPhone: _onlyDigits(widget.myPhone),
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.admin_panel_settings),
                        label: const Text('ABRIR PANEL ADMIN (WHITELIST)'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Estado de configuración',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text(configFinal ? '✅ Finalizada' : '⚙️ Pendiente',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  if (!configFinal)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed:
                            _savingFinal ? null : _finalizarConfiguracion,
                        icon: const Icon(Icons.check_circle),
                        label: Text(_savingFinal
                            ? 'Finalizando...'
                            : 'FINALIZAR CONFIGURACIÓN'),
                      ),
                    ),
                  if (!configFinal)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Después de finalizar, los usuarios comunes ya no verán pantallas técnicas.',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Resistencia',
                      style:
                          TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                  const SizedBox(height: 8),
                  const Text(
                    'Esta app funciona solo por invitación.\n'
                    'Ingresá tu número y se habilita si está en la whitelist.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Text('Tu número: ${phone ?? "(sin ingresar)"}',
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  if (!configFinal)
                    Text(
                        'Admins configurados: ${admins.length == 0 ? "0 (modo bootstrap)" : admins.length}',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _pedirTelefono,
            child: const Text('INGRESAR NÚMERO'),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Si no estás habilitado',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  const Text(
                    'Pedile al Fundador/Admin que agregue tu número.\n'
                    'Luego reintentá.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text('Whitelist actual: ${whitelist.length} números',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}


// ================== FIRESTORE ADMIN PANEL (OFICIAL) ==================
// Administra whitelist/admins/config directamente en Firestore.
// Esto es CRÍTICO para que los números agregados se validen en el gate OTP.
// NO usa SharedPreferences, NO usa JSON local, NO usa FileStore.
class FirestoreAdminPanelScreen extends StatefulWidget {
  final String myPhone; // 10 dígitos (normalizado)
  const FirestoreAdminPanelScreen({super.key, required this.myPhone});

  @override
  State<FirestoreAdminPanelScreen> createState() => _FirestoreAdminPanelScreenState();
}

class _FirestoreAdminPanelScreenState extends State<FirestoreAdminPanelScreen> {
  final _addWlCtrl = TextEditingController();
  final _addAdCtrl = TextEditingController();

  final _freeLimitCtrl = TextEditingController();
  final _priceMonthlyCtrl = TextEditingController();
  final _payAliasCtrl = TextEditingController();
  final _payCbuCtrl = TextEditingController();
  final _payHolderCtrl = TextEditingController();
  final _payNoteCtrl = TextEditingController();
  final _subscriptionDaysCtrl = TextEditingController();
  final _minBuildCtrl = TextEditingController();
  bool _paywallEnabled = true;
  bool _payEnabled = true;

  bool _savingCfg = false;

  String _normalizeAr10(String input) {
    final d = _onlyDigits(input);
    if (d.isEmpty) return '';
    // Si viene con +54 / 54, nos quedamos con los últimos 10 dígitos.
    if (d.length > 10) return d.substring(d.length - 10);
    // Si viene con 0 adelante (11 dígitos), recortamos.
    if (d.length == 11 && d.startsWith('0')) return d.substring(1);
    return d;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  bool get _isFounder {
    return _onlyDigits(widget.myPhone) == _onlyDigits(FOUNDER_PHONE);
  }

  Future<void> _loadConfig() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection(FS_CONFIG_COL)
          .doc(FS_CONFIG_DOC)
          .get();
      final cfg = snap.data() ?? <String, dynamic>{};
      final freeLimit = (cfg['freeLimit'] as num?)?.toInt() ?? 500;
      final priceMonthly = (cfg['monthlyPriceArs'] as num?)?.toInt() ?? (cfg['priceMonthly'] as num?)?.toInt() ?? 500;
      final paywallEnabled = (cfg['paywallEnabled'] as bool?) ?? true;
      final payEnabled = (cfg['payEnabled'] as bool?) ?? true;
      final subscriptionDays = (cfg['subscriptionDays'] as num?)?.toInt() ?? 30;
      final minBuild = (cfg['minBuild'] as num?)?.toInt() ?? APP_BUILD_CODE;

      _freeLimitCtrl.text = '$freeLimit';
      _priceMonthlyCtrl.text = '$priceMonthly';
      _payAliasCtrl.text = (cfg['payAlias'] as String?) ?? '';
      _payCbuCtrl.text = (cfg['payCbu'] as String?) ?? '';
      _payHolderCtrl.text = (cfg['payHolder'] as String?) ?? '';
      _payNoteCtrl.text = (cfg['payNote'] as String?) ?? '';
      _subscriptionDaysCtrl.text = '$subscriptionDays';
      _minBuildCtrl.text = '$minBuild';
      _paywallEnabled = paywallEnabled;
      _payEnabled = payEnabled;

      if (mounted) setState(() {});
    } catch (e) {
      // Si falla, no bloqueamos.
    }
  }

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _addWlCtrl.dispose();
    _addAdCtrl.dispose();
    _freeLimitCtrl.dispose();
    _priceMonthlyCtrl.dispose();
    _payAliasCtrl.dispose();
    _payCbuCtrl.dispose();
    _payHolderCtrl.dispose();
    _payNoteCtrl.dispose();
    _subscriptionDaysCtrl.dispose();
    _minBuildCtrl.dispose();
    super.dispose();
  }

  Future<bool> _upsertPhone({
    required String col,
    required String phone10,
    required bool enabled,
  }) async {
    if (phone10.length != 10) {
      _snack('Ingresá 10 dígitos (sin +54). Ej: 3435064401');
      return false;
    }

    try {
      final ref = FirebaseFirestore.instance.collection(col).doc(phone10);

      await ref.set({
        'phone': phone10,
        'enabled': enabled,
        // Si es whitelist, guardamos role para que se vea claro en consola.
        if (col == FS_WHITELIST_COL) 'role': 'usuario',
        if (col == FS_ADMINS_COL) 'role': 'admin',
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': _onlyDigits(widget.myPhone),
      }, SetOptions(merge: true));

      // Verificación dura: leemos el doc para confirmar que existe (evita "falsos OK"
      // cuando hay reglas, proyecto equivocado, o fallo silencioso).
      final verify = await ref.get(const GetOptions(source: Source.server));
      if (!verify.exists) {
        _snack('No se confirmó el guardado en Firestore (doc no existe). Revisá reglas / proyecto / conexión.');
        return false;
      }

      return true;
    } catch (e) {
      _snack('No se pudo guardar en Firestore: $e');
      return false;
    }
  }

  Future<void> _disablePhone({required String col, required String phone10}) async {
    final ref = FirebaseFirestore.instance.collection(col).doc(phone10);
    await ref.set({
      'enabled': false,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': _onlyDigits(widget.myPhone),
    }, SetOptions(merge: true));
  }

  Future<void> _saveConfig() async {
    if (_savingCfg) return;
    setState(() => _savingCfg = true);
    try {
      final freeLimit = int.tryParse(_onlyDigits(_freeLimitCtrl.text)) ?? 500;
      final priceMonthly = int.tryParse(_onlyDigits(_priceMonthlyCtrl.text)) ?? 500;
      final subscriptionDays = int.tryParse(_onlyDigits(_subscriptionDaysCtrl.text)) ?? 30;
      final minBuild = int.tryParse(_onlyDigits(_minBuildCtrl.text)) ?? APP_BUILD_CODE;

      await FirebaseFirestore.instance
          .collection(FS_CONFIG_COL)
          .doc(FS_CONFIG_DOC)
          .set({
        'freeLimit': freeLimit,
        'priceMonthly': priceMonthly,
        'monthlyPriceArs': priceMonthly,
        'paywallEnabled': _paywallEnabled,
        'payEnabled': _payEnabled,
        'payAlias': _payAliasCtrl.text.trim(),
        'payCbu': _payCbuCtrl.text.trim(),
        'payHolder': _payHolderCtrl.text.trim(),
        'payNote': _payNoteCtrl.text.trim(),
        'subscriptionDays': subscriptionDays,
        'minBuild': minBuild,
        'founderPhone': _onlyDigits(FOUNDER_PHONE), // fundador fijo (seguro)
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': _onlyDigits(widget.myPhone),
      }, SetOptions(merge: true));

      _snack('✅ Config guardada');
    } catch (e) {
      _snack('❌ Error guardando config: $e');
    } finally {
      if (mounted) setState(() => _savingCfg = false);
    }
  }

  Widget _phoneRow({
    required String title,
    required TextEditingController ctrl,
    required VoidCallback onAdd,
  }) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: ctrl,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: title,
              hintText: 'Ej: 3435064401',
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 56,
          child: ElevatedButton(
            onPressed: onAdd,
            child: const Text('AGREGAR'),
          ),
        ),
      ],
    );
  }

  Widget _listCol(String col, {required bool protectFounder}) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection(col)
          .orderBy('updatedAt', descending: true)
          .limit(200)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs;
        final items = docs.where((d) {
          final data = d.data();
          return (data['enabled'] ?? true) == true;
        }).toList();

        if (items.isEmpty) {
          return const Center(child: Text('Sin registros'));
        }

        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final d = items[i];
            final id = d.id;
            final phone10 = _normalizeAr10(id);

            final isFounderPhone = phone10 == _onlyDigits(FOUNDER_PHONE);
            final canDisable = !(protectFounder && isFounderPhone);

            return ListTile(
              title: Text(phone10),
              subtitle: Text('doc: ${d.id}'),
              trailing: IconButton(
                icon: const Icon(Icons.block),
                onPressed: canDisable
                    ? () async {
                        await _disablePhone(col: col, phone10: phone10);
                        _snack('⛔ Deshabilitado: $phone10');
                      }
                    : () {
                        _snack('⛔ El Fundador no se puede deshabilitar');
                      },
              ),
            );
          },
        );
      },
    );
  }

  Widget _configTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('⚙️ Configuración general',
                    style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                TextField(
                  controller: _freeLimitCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'FREE_LIMIT (usuarios gratis)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _priceMonthlyCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Precio mensual (ARS)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _subscriptionDaysCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Duración de suscripción (días)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _minBuildCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Versión mínima obligatoria (minBuild)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  value: _paywallEnabled,
                  onChanged: (v) => setState(() => _paywallEnabled = v),
                  title: const Text('Paywall habilitado'),
                ),
                SwitchListTile(
                  value: _payEnabled,
                  onChanged: (v) => setState(() => _payEnabled = v),
                  title: const Text('Cobro habilitado'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('💳 Datos de cobro', style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                TextField(
                  controller: _payAliasCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Alias',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _payCbuCtrl,
                  decoration: const InputDecoration(
                    labelText: 'CBU / CVU',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _payHolderCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Titular',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _payNoteCtrl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Nota / instrucciones de pago',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('🧠 Notas', style: TextStyle(fontWeight: FontWeight.w900)),
                SizedBox(height: 8),
                Text('• Este panel guarda tanto priceMonthly como monthlyPriceArs para compatibilidad.'),
                Text('• minBuild permite forzar actualización obligatoria desde el gate.'),
                Text('• payEnabled y paywallEnabled quedan separados para no mezclar cobro con política de acceso.'),
                Text('• El Fundador sigue fijo y no se puede remover.'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _savingCfg ? null : _saveConfig,
            child: Text(_savingCfg ? 'Guardando...' : 'GUARDAR CONFIG'),
          ),
        ),
      ],
    );
  }

  @override
  
  // ================== AUXILIOS: ACREDITACIÓN (ADMIN) ==================
  Stream<QuerySnapshot<Map<String, dynamic>>> _auxiliosParaAcreditarStream() {
    // Firestore requiere índice para orderBy + whereIn; si no, quitá orderBy.
    return FirebaseFirestore.instance
        .collection(FS_AUXILIOS_COL)
        .where('status', whereIn: ['resolved', 'finalizado'])
        .limit(50)
        .snapshots();
  }

  int _calcBonusRapidez(Map<String, dynamic> a) {
    try {
      final created = a['createdAt'];
      final arrived = a['arrivedAt'];
      if (created is! Timestamp || arrived is! Timestamp) return 0;
      final diffMin = arrived.toDate().difference(created.toDate()).inMinutes;
      return (diffMin >= 0 && diffMin <= AUX_BONUS_VENTANA_MIN) ? AUX_BONUS_RAPIDEZ_PTS : 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _acreditarAuxilio(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final id = doc.id;
    final auxRef = doc.reference;

    try {
      setState(() {}); // refresh UI a demanda

      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(auxRef);
        if (!snap.exists) {
          throw Exception('Auxilio no existe.');
        }
        final a = snap.data() as Map<String, dynamic>;

        final status = (a['status'] ?? '').toString();
        if (status != 'resolved' && status != 'finalizado') {
          throw Exception('Estado inválido para acreditar ($status).');
        }

        final credited = (a['credited'] == true);
        if (credited) {
          throw Exception('Ya fue acreditado.');
        }

        // Verificación anti-inconsistencia: el solicitante debe haber sido cobrado server-side (-400)
        final charged = (a['requesterCharged'] == true);
        if (!charged) {
          throw Exception('Aún no se descontó el -400 al solicitante (server-side). Esperá unos segundos y reintentá.');
        }

        final helper = (a['helperPhone'] ?? a['ayudantePhone10'] ?? '').toString();
        if (helper.trim().isEmpty) {
          throw Exception('No hay ayudante asignado.');
        }

        // Base + bonus
        final bonus = _calcBonusRapidez(a);
        final reward = AUX_COMPLETADO_PTS + bonus;

        // Sumar puntos al ayudante (users/{phone10})
        final helperRef = FirebaseFirestore.instance.collection(FS_USERS_COL).doc(_onlyDigits(helper));
        final helperSnap = await tx.get(helperRef);
        if (!helperSnap.exists) {
          tx.set(helperRef, {
            'phone': _onlyDigits(helper),
            'points': reward,
            'pointsPending': 0,
            'createdAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } else {
          tx.set(helperRef, {
            'points': FieldValue.increment(reward),
          }, SetOptions(merge: true));
        }

        // Marcar acreditado en el auxilio
        tx.set(auxRef, {
          'credited': true,
          'creditedAt': FieldValue.serverTimestamp(),
          'creditedBy': widget.myPhone,
          'creditReward': reward,
          'creditBonus': bonus,
          'logs': FieldValue.arrayUnion([
            {
              't': FieldValue.serverTimestamp(),
              'by': widget.myPhone,
              'ev': 'credit',
              'msg': 'Acreditado +$reward (bonus $bonus)',
            }
          ]),
        }, SetOptions(merge: true));
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ Auxilio $id acreditado.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('⛔ No se pudo acreditar: $e')),
      );
    } finally {
      if (mounted) setState(() {});
    }
  }

  Widget _auxiliosTab() {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Auxilios para acreditar (status: resolved/finalizado)',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _auxiliosParaAcreditarStream(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: Text('Error: ${snap.error}'));
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snap.data!.docs.where((d) {
                final m = d.data();
                return m['credited'] != true;
              }).toList();

              if (docs.isEmpty) {
                return const Center(child: Text('No hay auxilios pendientes.'));
              }

              return ListView.separated(
                itemCount: docs.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final d = docs[i];
                  final a = d.data();

                  final requester = (a['requesterPhone'] ?? a['solicitantePhone10'] ?? '').toString();
                  final helper = (a['helperPhone'] ?? a['ayudantePhone10'] ?? '').toString();
                  final status = (a['status'] ?? '').toString();
                  final bonus = _calcBonusRapidez(a);
                  final reward = AUX_COMPLETADO_PTS + bonus;

                  DateTime? createdAt;
                  final c = a['createdAt'];
                  if (c is Timestamp) createdAt = c.toDate();

                  return ListTile(
                    title: Text('Auxilio ${d.id} • $status'),
                    subtitle: Text(
                      'Solicitante: $requester\nAyudante: $helper\nReward: +$reward (bonus $bonus)'
                      + (createdAt != null ? '\nCreado: ${createdAt.toLocal()}' : ''),
                    ),
                    isThreeLine: true,
                    trailing: ElevatedButton(
                      onPressed: () => _acreditarAuxilio(d),
                      child: const Text('ACREDITAR'),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

Widget build(BuildContext context) {
    // Seguridad: solo Admin/Fundador debería llegar acá desde UI.
    // Aun así, si no hay sesión Firebase, mostramos bloqueo.
    final hasUser = FirebaseAuth.instance.currentUser != null;
    if (!hasUser) {
      return const Scaffold(
        body: Center(child: Text('⛔ FirebaseAuth no iniciado.')),
      );
    }

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Panel Admin (Firestore)'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Whitelist'),
              Tab(text: 'Admins'),
              Tab(text: 'Config'),
              Tab(text: 'Auxilios'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Whitelist
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: _phoneRow(
                    title: 'Agregar a whitelist',
                    ctrl: _addWlCtrl,
                    onAdd: () async {
                      final p = _normalizeAr10(_addWlCtrl.text);
                      await _upsertPhone(col: FS_WHITELIST_COL, phone10: p, enabled: true);
                      _addWlCtrl.clear();
                      _snack('✅ Agregado a whitelist: $p');
                    },
                  ),
                ),
                const Divider(height: 1),
                Expanded(child: _listCol(FS_WHITELIST_COL, protectFounder: false)),
              ],
            ),

            // Admins
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: _phoneRow(
                    title: 'Agregar Admin',
                    ctrl: _addAdCtrl,
                    onAdd: () async {
                      final p = _normalizeAr10(_addAdCtrl.text);
                      await _upsertPhone(col: FS_ADMINS_COL, phone10: p, enabled: true);
                      _addAdCtrl.clear();
                      _snack('✅ Agregado a admins: $p');
                    },
                  ),
                ),
                const Divider(height: 1),
                Expanded(child: _listCol(FS_ADMINS_COL, protectFounder: true)),
              ],
            ),

            // Config
            _configTab(),

            // Auxilios
            _auxiliosTab(),

          ],
        ),
      ),
    );
  }
}

class AdminPanelScreen extends StatefulWidget {
  final List<String> initialWhitelist;
  final List<String> initialAdmins;
  final String myPhone;

  final Future<void> Function(List<String> whitelist, List<String> admins)
      onSave;
  final Future<void> Function() onResetAccess;

  const AdminPanelScreen({
    super.key,
    required this.initialWhitelist,
    required this.initialAdmins,
    required this.myPhone,
    required this.onSave,
    required this.onResetAccess,
  });

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  // ================== RESET SEGURO (SOLO SERVER URLS) ==================
  Future<void> _resetSeguroServer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(K_BASE_OVERRIDE);
      await prefs.remove(K_LAST_GOOD_BASE);
      _serverUrlCtrl.text = REMOTE_PAYWALL_BASE_URL;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            '🧹 Reset seguro: se limpió Override y LastGood (solo server URLs)'),
      ));
      setState(() {});
    } catch (_) {}
  }

  // ================== BACKUP / RESTORE (CONFIG) ==================
  final TextEditingController _backupCtrl = TextEditingController();
  final TextEditingController _serverUrlCtrl = TextEditingController();
  bool _backupBusy = false;
  String _backupMsg = '';

  Future<void> _generarBackup() async {
    if (_backupBusy) return;
    setState(() {
      _backupBusy = true;
      _backupMsg = 'Generando backup...';
    });

    try {
      final prefs = await SharedPreferences.getInstance();

      // Seleccionamos keys importantes (ro_* + state)
      final keys = prefs.getKeys().toList()..sort();
      final pick = <String, dynamic>{};

      bool allow(String k) {
        if (k == K_STATE) return true;
        if (k.startsWith('ro_')) return true;
        // si tu app usa otras keys críticas, agregalas acá
        return false;
      }

      for (final k in keys) {
        if (!allow(k)) continue;
        final v = prefs.get(k);
        // only json-safe
        if (v is String || v is int || v is double || v is bool) {
          pick[k] = v;
        } else if (v is List<String>) {
          pick[k] = v;
        } else if (v != null) {
          pick[k] = v.toString();
        }
      }

      final payload = {
        'app': 'resistencia_operativos',
        'ts': DateTime.now().toIso8601String(),
        'keys': pick,
      };

      final txt = const JsonEncoder.withIndent('  ').convert(payload);
      _backupCtrl.text = txt;

      if (!mounted) return;
      setState(() {
        _backupBusy = false;
        _backupMsg = '✅ Backup generado (${pick.length} keys).';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _backupBusy = false;
        _backupMsg = '❌ Error backup: $e';
      });
    }
  }

  Future<void> _copiarBackup() async {
    try {
      final txt = _backupCtrl.text.trim();
      if (txt.isEmpty) return;
      await Clipboard.setData(ClipboardData(text: txt));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✅ Backup copiado'),
      ));
    } catch (_) {}
  }

  Future<void> _hacerBackup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = <String, dynamic>{};

      // Guardamos claves importantes (acceso + estado completo).
      for (final k in <String>[
        K_ACCESS,
        K_STATE,
        K_DEVICE_ID,
        K_CONFIG_FINAL,
        K_WIZARD_DONE,
        K_BASE_OVERRIDE,
        K_LAST_GOOD_BASE,
        K_GATE_CACHE,
      ]) {
        final v = prefs.get(k);
        if (v != null) data[k] = v;
      }

      // Metadatos útiles para debugging
      data['_exportedAt'] = DateTime.now().toIso8601String();
      data['_appBuild'] = APP_BUILD_CODE;

      _backupCtrl.text = const JsonEncoder.withIndent('  ').convert(data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Backup generado. Podés COPIAR o COMPARTIR.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generando backup: $e')),
        );
      }
    }
  }

  Future<void> _restaurarBackup() async {
    if (_backupBusy) return;

    setState(() {
      _backupBusy = true;
      _backupMsg = 'Restaurando backup...';
    });

    try {
      final raw = _backupCtrl.text.trim();
      if (raw.isEmpty) {
        setState(() {
          _backupBusy = false;
          _backupMsg = '⚠️ Pegá el backup JSON en el cuadro primero.';
        });
        return;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw 'Backup inválido (no es Map).';
      final keys = decoded['keys'];
      if (keys is! Map) throw 'Backup inválido: falta "keys".';

      final prefs = await SharedPreferences.getInstance();

      int applied = 0;
      for (final entry in keys.entries) {
        final k = '${entry.key}';
        final v = entry.value;

        if (k == K_STATE) {
          if (v is String) {
            await prefs.setString(k, v);
            applied++;
          }
          continue;
        }

        if (!k.startsWith('ro_')) continue;

        if (v is String) {
          await prefs.setString(k, v);
          applied++;
        } else if (v is int) {
          await prefs.setInt(k, v);
          applied++;
        } else if (v is double) {
          await prefs.setDouble(k, v);
          applied++;
        } else if (v is bool) {
          await prefs.setBool(k, v);
          applied++;
        } else if (v is List) {
          // Try list of strings
          final ls = v.map((e) => '$e').toList();
          await prefs.setStringList(k, ls);
          applied++;
        }
      }

      if (!mounted) return;
      setState(() {
        _backupBusy = false;
        _backupMsg =
            '✅ Backup restaurado ($applied keys). Reiniciá la app si no ves cambios.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _backupBusy = false;
        _backupMsg = '❌ Error restore: $e';
      });
    }
  }

  Widget _serverUrlsInfo() {
    return FutureBuilder<SharedPreferences>(
      future: SharedPreferences.getInstance(),
      builder: (context, snap) {
        final p = snap.data;
        final override = (p?.getString(K_BASE_OVERRIDE) ?? '').trim();
        final lastGood = (p?.getString(K_LAST_GOOD_BASE) ?? '').trim();
        final base = REMOTE_PAYWALL_BASE_URL.trim();

        String line(String label, String v) => '$label: ${v.isEmpty ? '-' : v}';

        final txt = [
          line('Base', base),
          line('Override', override),
          line('LastGood', lastGood),
        ].join('\n');

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            SelectableText(
              txt,
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: txt));
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('✅ URLs copiadas'),
                      ));
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copiar URLs'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.remove(K_LAST_GOOD_BASE);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(
                          content: Text('🧹 LastGood borrado'),
                        ));
                        setState(() {});
                      } catch (_) {}
                    },
                    icon: const Icon(Icons.cleaning_services),
                    label: const Text('Limpiar LastGood'),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  // ================== DIAGNÓSTICO RÁPIDO (1 BOTÓN) ==================
  bool _quickRunning = false;
  String _quickMsg = '';

  Future<void> _diagnosticoRapido() async {
    if (_quickRunning) return;

    setState(() {
      _quickRunning = true;
      _quickMsg = 'Ejecutando diagnóstico rápido...';
    });

    try {
      final me = _onlyDigits(widget.myPhone);
      final bases = await _candidateBasesAdmin();

      String? okBase;
      Map<String, dynamic>? healthJson;
      Map<String, dynamic>? registerJson;
      String? lastErr;

      // 1) Ping /health
      for (final base in bases) {
        try {
          final b =
              base.endsWith('/') ? base.substring(0, base.length - 1) : base;
          final uri = Uri.parse('$b/health');

          final client = HttpClient()
            ..connectionTimeout = const Duration(seconds: 4);
          try {
            final req = await client.getUrl(uri);
            final res = await req.close();
            final body = await res.transform(utf8.decoder).join();

            if (res.statusCode >= 200 && res.statusCode < 300) {
              okBase = base;
              try {
                final decoded = jsonDecode(body);
                if (decoded is Map<String, dynamic>) {
                  healthJson = decoded;
                } else {
                  healthJson = {'_raw': body};
                }
              } catch (_) {
                healthJson = {'_raw': body};
              }

              final prefs = await SharedPreferences.getInstance();
              await prefs.setString(K_LAST_GOOD_BASE, base);
              break;
            } else {
              lastErr = 'health HTTP ${res.statusCode}: $body';
            }
          } finally {
            client.close(force: true);
          }
        } catch (e) {
          lastErr = 'health error: $e';
        }
      }

      if (okBase == null) {
        if (!mounted) return;
        setState(() {
          _quickRunning = false;
          _quickMsg = '❌ HEALTH FAIL\n${lastErr ?? 'sin detalle'}';
        });
        return;
      }

      // 2) Test /register con tu número (si está vacío, solo reporta health OK)
      if (me.isNotEmpty) {
        try {
          final did = await RemotePaywallApi.getOrCreateDeviceId();
          final j = await _postJson(okBase!, 'register', {
            'phone': me,
            'deviceId': 'admin-quick-$did',
          });
          registerJson = j ?? {'error': 'sin respuesta'};
        } catch (e) {
          registerJson = {'error': '$e'};
        }
      } else {
        registerJson = {
          'warn': 'Tu teléfono no está cargado en prefs (widget.myPhone vacío).'
        };
      }

      final payload = <String, dynamic>{
        'base': okBase,
        'health': healthJson,
        'register_me': registerJson,
        'ts': DateTime.now().toIso8601String(),
      };

      final pretty = const JsonEncoder.withIndent('  ').convert(payload);

      if (!mounted) return;
      setState(() {
        _quickRunning = false;
        _quickMsg = '✅ DIAGNÓSTICO OK\n$pretty';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _quickRunning = false;
        _quickMsg = '❌ ERROR: $e';
      });
    }
  }

  Future<void> _copiarQuick() async {
    try {
      final txt = _quickMsg.trim();
      if (txt.isEmpty) return;
      await Clipboard.setData(ClipboardData(text: txt));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✅ Diagnóstico copiado'),
      ));
    } catch (_) {}
  }

  // ================== TEST ENDPOINTS (/register, /markPaid) ==================
  final TextEditingController _testPhoneCtrl = TextEditingController();
  bool _testing = false;
  String _testMsg = '';

  Future<List<String>> _candidateBasesAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    final override = (prefs.getString(K_BASE_OVERRIDE) ?? '').trim();
    final lastGood = (prefs.getString(K_LAST_GOOD_BASE) ?? '').trim();

    final bases = <String>[];
    void add(String s) {
      final v = s.trim();
      if (v.isEmpty) return;
      if (!bases.contains(v)) bases.add(v);
    }

    add(override);
    add(REMOTE_PAYWALL_BASE_URL);
    add(lastGood);
    for (final u in REMOTE_PAYWALL_FALLBACK_URLS) {
      add(u);
    }
    return bases;
  }

  Future<Map<String, dynamic>?> _postJson(
      String base, String path, Map<String, dynamic> payload) async {
    final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final uri = Uri.parse('$b/$path');

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client.postUrl(uri);
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode(payload)));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      return {'_raw': body, '_status': res.statusCode};
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _adminTestRegister() async {
    if (_testing) return;
    setState(() {
      _testing = true;
      _testMsg = 'Probando /register...';
    });

    try {
      final phone = _onlyDigits(_testPhoneCtrl.text);
      if (phone.isEmpty) {
        setState(() {
          _testing = false;
          _testMsg = '⚠️ Ingresá un número para test';
        });
        return;
      }

      final bases = await _candidateBasesAdmin();
      Map<String, dynamic>? lastErr;

      for (final base in bases) {
        try {
          final did = await RemotePaywallApi.getOrCreateDeviceId();
          final j = await _postJson(base, 'register', {
            'phone': phone,
            'deviceId': 'admin-test-$did',
          });
          if (j != null) {
            // si viene ok, guardamos last good
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(K_LAST_GOOD_BASE, base);

            final pretty = const JsonEncoder.withIndent('  ').convert(j);
            setState(() {
              _testing = false;
              _testMsg = '✅ /register OK ($base)\n$pretty';
            });
            return;
          }
        } catch (e) {
          lastErr = {'base': base, 'error': '$e'};
        }
      }

      setState(() {
        _testing = false;
        _testMsg =
            '❌ /register FAIL\n${const JsonEncoder.withIndent('  ').convert(lastErr ?? {
                  'error': 'sin detalle'
                })}';
      });
    } catch (e) {
      setState(() {
        _testing = false;
        _testMsg = '❌ ERROR: $e';
      });
    }
  }

  Future<void> _adminMarkPaid(bool paid) async {
    if (_testing) return;
    setState(() {
      _testing = true;
      _testMsg = paid
          ? 'Marcando pago (/markPaid)...'
          : 'Quitando pago (/markPaid)...';
    });

    try {
      final phone = _onlyDigits(_testPhoneCtrl.text);
      if (phone.isEmpty) {
        setState(() {
          _testing = false;
          _testMsg = '⚠️ Ingresá un número para marcar pago';
        });
        return;
      }

      final me = _onlyDigits(widget.myPhone);
      final bases = await _candidateBasesAdmin();
      Map<String, dynamic>? lastErr;

      for (final base in bases) {
        try {
          final j = await _postJson(base, 'markPaid', {
            'adminPhone': me,
            'phone': phone,
            'paid': paid,
          });
          if (j != null) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(K_LAST_GOOD_BASE, base);

            final pretty = const JsonEncoder.withIndent('  ').convert(j);
            setState(() {
              _testing = false;
              _testMsg = '✅ /markPaid OK ($base)\n$pretty';
            });
            return;
          }
        } catch (e) {
          lastErr = {'base': base, 'error': '$e'};
        }
      }

      setState(() {
        _testing = false;
        _testMsg =
            '❌ /markPaid FAIL\n${const JsonEncoder.withIndent('  ').convert(lastErr ?? {
                  'error': 'sin detalle'
                })}';
      });
    } catch (e) {
      setState(() {
        _testing = false;
        _testMsg = '❌ ERROR: $e';
      });
    }
  }

  // ================== PING /health ==================
  bool _pinging = false;
  String _pingMsg = '';

  Future<void> _pingHealth() async {
    if (_pinging) return;
    setState(() {
      _pinging = true;
      _pingMsg = 'Probando /health...';
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final override = (prefs.getString(K_BASE_OVERRIDE) ?? '').trim();
      final lastGood = (prefs.getString(K_LAST_GOOD_BASE) ?? '').trim();

      final bases = <String>[];
      void add(String s) {
        final v = s.trim();
        if (v.isEmpty) return;
        if (!bases.contains(v)) bases.add(v);
      }

      add(override);
      add(REMOTE_PAYWALL_BASE_URL);
      add(lastGood);
      for (final u in REMOTE_PAYWALL_FALLBACK_URLS) {
        add(u);
      }

      String? okBase;
      String? detail;

      for (final base in bases) {
        try {
          final b =
              base.endsWith('/') ? base.substring(0, base.length - 1) : base;
          final uri = Uri.parse('$b/health');

          final client = HttpClient()
            ..connectionTimeout = const Duration(seconds: 4);
          try {
            final req = await client.getUrl(uri);
            final res = await req.close();
            final body = await res.transform(utf8.decoder).join();

            if (res.statusCode >= 200 && res.statusCode < 300) {
              okBase = base;
              detail = body;
              // guardamos como última buena
              await prefs.setString(K_LAST_GOOD_BASE, base);
              break;
            } else {
              detail = 'HTTP ${res.statusCode}: $body';
            }
          } finally {
            client.close(force: true);
          }
        } catch (e) {
          detail = '$e';
        }
      }

      if (!mounted) return;
      setState(() {
        _pinging = false;
        if (okBase != null) {
          _pingMsg = '✅ OK ($okBase)';
        } else {
          _pingMsg = '❌ FAIL (${detail ?? 'sin detalle'})';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pinging = false;
        _pingMsg = '❌ ERROR: $e';
      });
    }
  }

  late List<String> whitelist;
  late List<String> admins;

  bool configFinal = false;
  bool _savingFinal = false;

  String nuevoWhitelist = '';
  String nuevoAdmin = '';

  // Paywall admin
  String payPhone = '';
  bool payPaid = true;
  GateStatus? payStatus;
  bool payBusy = false;

  @override
  void initState() {
    super.initState();
    _serverUrlCtrl.text = REMOTE_PAYWALL_BASE_URL;
    SharedPreferences.getInstance().then((p) {
      final v = p.getString(K_BASE_OVERRIDE);
      if (v != null && v.trim().isNotEmpty) {
        _serverUrlCtrl.text = v.trim();
      }
    });

    _loadConfigFinal();
    whitelist = List<String>.from(widget.initialWhitelist)
        .map(_onlyDigits)
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    admins = List<String>.from(widget.initialAdmins)
        .map(_onlyDigits)
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    // 🔒 Blindaje: aunque alguien fuerce la navegación al panel, NO entra si no es Admin o Fundador.
    final _me = _onlyDigits(widget.myPhone);
    final _allowed = (_me == FOUNDER_PHONE) || admins.contains(_me);
    if (!_allowed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                '⛔ Acceso denegado: Panel Admin solo para Admin/Fundador.'),
          ));
        } catch (_) {}
        Navigator.of(context).maybePop();
      });
      return;
    }

    // Fundador fijo
    final f = _onlyDigits(FOUNDER_PHONE);
    if (f.isNotEmpty) {
      if (!whitelist.contains(f)) whitelist.add(f);
      if (!admins.contains(f)) admins.add(f);
      whitelist = whitelist.toSet().toList()..sort();
      admins = admins.toSet().toList()..sort();
    }
  }

  Future<void> _loadConfigFinal() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getBool(K_CONFIG_FINAL) ?? false;
    if (mounted) setState(() => configFinal = v);
  }

  Future<void> _finalizarConfiguracion() async {
    if (_savingFinal) return;
    setState(() => _savingFinal = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(K_CONFIG_FINAL, true);
    if (mounted) {
      setState(() {
        configFinal = true;
        _savingFinal = false;
      });
    }
  }

  void _addWhitelist() {
    final n = _onlyDigits(nuevoWhitelist);
    if (n.isEmpty) return;
    if (!whitelist.contains(n)) whitelist.add(n);
    whitelist = whitelist.toSet().toList()..sort();
    nuevoWhitelist = '';
    setState(() {});
  }

  void _removeWhitelist(String n) {
    if (n == _onlyDigits(FOUNDER_PHONE)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No podés quitar al Fundador/Super Admin.')),
      );
      return;
    }
    if (n == _onlyDigits(widget.myPhone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No podés quitar tu propio número.')),
      );
      return;
    }
    whitelist.remove(n);
    // si sacan a alguien de whitelist, también lo sacamos de admins
    admins.remove(n);
    setState(() {});
  }

  void _addAdmin() {
    final n = _onlyDigits(nuevoAdmin);
    if (n.isEmpty) return;
    // regla: para ser admin debe estar en whitelist
    if (!whitelist.contains(n)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero agregalo a la whitelist.')),
      );
      return;
    }
    if (!admins.contains(n)) admins.add(n);
    admins = admins.toSet().toList()..sort();
    nuevoAdmin = '';
    setState(() {});
  }

  void _removeAdmin(String n) {
    // evitamos que te saques a vos mismo por accidente
    if (n == _onlyDigits(widget.myPhone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No podés quitarte a vos mismo de Admin.')),
      );
      return;
    }
    admins.remove(n);
    setState(() {});
  }

  Future<void> _importarPegadoWhitelist() async {
    String tmp = '';
    final res = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Importar whitelist (pegado)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Pegá números separados por comas/espacios/saltos.',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            TextField(
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: '5493456...\n5491144...\n...',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => tmp = v,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, tmp),
              child: const Text('Importar')),
        ],
      ),
    );

    if (res == null) return;

    final tokens = res
        .split(RegExp(r'[\s,;]+'))
        .map(_onlyDigits)
        .where((e) => e.isNotEmpty);
    for (final t in tokens) {
      if (!whitelist.contains(t)) whitelist.add(t);
    }
    whitelist = whitelist.toSet().toList()..sort();
    setState(() {});
  }

  Future<void> _resetAccessConfirm() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reset Acceso'),
        content: const Text(
          'Esto borra teléfono guardado y listas de whitelist/admins del teléfono.\n'
          'Vuelve a WHITELIST_INICIAL.\n\n¿Seguro?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('RESETEAR')),
        ],
      ),
    );

    if (ok != true) return;
    await widget.onResetAccess();
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _save() async {
    await widget.onSave(whitelist, admins);
    if (!mounted) return;
    Navigator.pop(context);
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
      );

  Future<void> _doMarkPaid() async {
    final n = _onlyDigits(payPhone);
    if (n.isEmpty) return;

    setState(() {
      payBusy = true;
      payStatus = null;
    });

    final st = await RemotePaywallApi.markPaid(
      phoneDigits: n,
      paid: payPaid,
      adminPhoneDigits: _onlyDigits(widget.myPhone),
    );

    if (st.ok) {
      await RemotePaywallApi.cacheStatus(n, st);
    }

    if (!mounted) return;
    setState(() {
      payStatus = st;
      payBusy = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(st.ok ? 'OK: ${st.message}' : 'ERROR: ${st.message}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin: Whitelist + Admins'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('GUARDAR',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Servidor (URL)',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  const Text(
                    'Si cambia la IP o salís de tu WiFi, podés cambiar la URL del server desde acá.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _serverUrlCtrl,
                    decoration: const InputDecoration(
                      labelText: 'URL del servidor',
                      hintText: 'http://192.168.100.41:8080',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final v = _serverUrlCtrl.text.trim();
                            await RemotePaywallApi.setBaseOverride(
                                v.isEmpty ? null : v);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context)
                                .showSnackBar(const SnackBar(
                              content: Text('✅ URL guardada'),
                            ));
                          },
                          icon: const Icon(Icons.save),
                          label: const Text('Guardar'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            await RemotePaywallApi.setBaseOverride(null);
                            _serverUrlCtrl.text = REMOTE_PAYWALL_BASE_URL;
                            if (!mounted) return;
                            ScaffoldMessenger.of(context)
                                .showSnackBar(const SnackBar(
                              content: Text('↩️ URL restablecida'),
                            ));
                          },
                          icon: const Icon(Icons.restore),
                          label: const Text('Reset'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _pinging ? null : () async => _pingHealth(),
                      icon: const Icon(Icons.network_check),
                      label: Text(_pinging ? 'Probando...' : 'Ping /health'),
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (_pingMsg.trim().isNotEmpty)
                    Text(
                      _pingMsg,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Diagnóstico rápido',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  const Text(
                    'Un botón: prueba /health y luego /register con TU número (si está).',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _quickRunning
                          ? null
                          : () async => _diagnosticoRapido(),
                      icon: const Icon(Icons.bolt),
                      label: Text(_quickRunning
                          ? 'Ejecutando...'
                          : 'Ejecutar diagnóstico'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _quickMsg.trim().isEmpty
                          ? null
                          : () async => _copiarQuick(),
                      icon: const Icon(Icons.copy),
                      label: const Text('Copiar resultado'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_quickMsg.trim().isNotEmpty)
                    SelectableText(_quickMsg,
                        style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Test endpoints',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  const Text(
                    'Usalo para verificar rápido /register y /markPaid sin salir de la app.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _testPhoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Teléfono de prueba',
                      hintText: '3435...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _testing
                              ? null
                              : () async => _adminTestRegister(),
                          icon: const Icon(Icons.play_arrow),
                          label: Text(_testing ? '...' : 'Test /register'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _testing
                              ? null
                              : () async => _adminMarkPaid(true),
                          icon: const Icon(Icons.verified),
                          label: const Text('Marcar pago'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed:
                          _testing ? null : () async => _adminMarkPaid(false),
                      icon: const Icon(Icons.block),
                      label: const Text('Quitar pago'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_testMsg.trim().isNotEmpty)
                    SelectableText(
                      _testMsg,
                      style: const TextStyle(fontSize: 12),
                    ),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Tu número (admin actual)',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text(_onlyDigits(widget.myPhone),
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  Text(
                      'Whitelist: ${whitelist.length} | Admins: ${admins.length == 0 ? "0 (bootstrap)" : admins.length}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _resetAccessConfirm,
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('RESET ACCESO (BORRA TODO LOCAL)'),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async => _resetSeguroServer(),
                      icon: const Icon(Icons.cleaning_services),
                      label: const Text('Reset seguro (solo server)'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          _sectionTitle('Whitelist'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                              labelText: 'Agregar a whitelist'),
                          onChanged: (v) => nuevoWhitelist = v,
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                          onPressed: _addWhitelist,
                          child: const Text('AGREGAR')),
                    ],
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                      onPressed: _importarPegadoWhitelist,
                      child: const Text('IMPORTAR PEGADO')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          ...whitelist.map((n) {
            final esAdmin = admins.isNotEmpty && admins.contains(n);
            return Card(
              child: ListTile(
                leading: Icon(esAdmin ? Icons.verified_user : Icons.person),
                title: Text(n,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(esAdmin ? 'Admin' : 'Usuario',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                trailing: IconButton(
                  tooltip: (n == _onlyDigits(widget.myPhone))
                      ? 'Fundador (no removible)'
                      : 'Quitar',
                  icon: Icon(
                    (n == _onlyDigits(widget.myPhone))
                        ? Icons.lock
                        : Icons.delete_outline,
                  ),
                  onPressed: (n == _onlyDigits(widget.myPhone))
                      ? null
                      : () => _removeWhitelist(n),
                ),
              ),
            );
          }).toList(),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Backup/Restore (texto)',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Servidor: ${REMOTE_PAYWALL_BASE_URL.trim().isNotEmpty ? REMOTE_PAYWALL_BASE_URL : '(no configurado)'}',
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _backupCtrl,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Pegar backup aquí (JSON)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _hacerBackup,
                          icon: const Icon(Icons.copy),
                          label: const Text('GENERAR'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _restaurarBackup,
                          icon: const Icon(Icons.paste),
                          label: const Text('RESTAURAR'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          _sectionTitle('Admins (lista)'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                      'Regla: para ser Admin, el número debe estar en whitelist.',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                              labelText: 'Agregar admin (número)'),
                          onChanged: (v) => nuevoAdmin = v,
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                          onPressed: _addAdmin, child: const Text('AGREGAR')),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                      admins.isEmpty
                          ? 'Admins: (vacío) → MODO BOOTSTRAP por whitelist'
                          : 'Admins: ${admins.length}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (admins.isNotEmpty)
            ...admins.map((n) => Card(
                  child: ListTile(
                    title: Text(n,
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(
                        n == _onlyDigits(widget.myPhone)
                            ? 'Vos (no removible)'
                            : 'Admin',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () => _removeAdmin(n),
                    ),
                  ),
                )),
          const SizedBox(height: 18),
          ElevatedButton(
            onPressed: _save,
            style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 56)),
            child: const Text('FINALIZAR CONFIGURACIÓN',
                style: TextStyle(fontWeight: FontWeight.w900)),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Paywall (500 gratis)',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Text(
                    USE_REMOTE_PAYWALL &&
                            REMOTE_PAYWALL_BASE_URL.trim().isNotEmpty
                        ? 'Remote: ON'
                        : 'Remote: OFF (pegá la URL en REMOTE_PAYWALL_BASE_URL)',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Teléfono a marcar (solo dígitos)',
                    ),
                    onChanged: (v) => setState(() => payPhone = v),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Marcar como PAGADO'),
                    value: payPaid,
                    onChanged: (v) => setState(() => payPaid = v),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: payBusy ? null : _doMarkPaid,
                    child: Text(payBusy ? 'Procesando...' : 'APLICAR'),
                  ),
                  if (payStatus != null) ...[
                    const SizedBox(height: 10),
                    Text('Estado: ${payStatus!.ok ? 'OK' : 'ERROR'}'),
                    Text(
                        'User#: ${payStatus!.userNumber ?? '-'} / FreeLimit: ${payStatus!.freeLimit}'),
                    Text(
                        'Paid: ${payStatus!.isPaid} / Paywall: ${payStatus!.paywallEnabled}'),
                    if (payStatus!.message.isNotEmpty) Text(payStatus!.message),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
// ======================================================================
// >>>>>>>>>>>> SEPARABLE: permission_wizard.dart (desde acá) <<<<<<<<<<<
// ======================================================================
// Wizard práctico para que el usuario deje TODO listo:
// - Ubicación (precisa)
// - Background location (si el sistema lo pide)
// - Notificaciones (Android 13+)
// - Optimización de batería (instrucciones + acceso a Ajustes)
// Guarda flag K_WIZARD_DONE para no molestar.
// ======================================================================

class PermissionWizardScreen extends StatefulWidget {
  const PermissionWizardScreen({super.key, this.onDone});

  final VoidCallback? onDone;

  @override
  State<PermissionWizardScreen> createState() => _PermissionWizardScreenState();
}

class _PermissionWizardScreenState extends State<PermissionWizardScreen> {
  bool _busy = false;
  String _status = '';

  Future<void> _setDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(K_WIZARD_DONE, true);
  }

  Future<void> _runAll() async {
    setState(() {
      _busy = true;
      _status = 'Solicitando permisos...';
    });

    // Helper: nunca quedarnos colgados esperando diálogos que el OS no muestra
    Future<T> _withTimeout<T>(Future<T> fut, {int seconds = 8}) async {
      return fut.timeout(Duration(seconds: seconds));
    }

    // 1) Notificaciones (Android 13+)
    try {
      final notif = await Permission.notification.status;
      if (!notif.isGranted) {
        await _withTimeout(Permission.notification.request(), seconds: 6);
      }
    } catch (_) {}

    // 2) Ubicación (EVITAR Geolocator.requestPermission(), que en algunos Samsung se cuelga sin popup)
    // Primero: verificar servicio de ubicación
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _status = 'Activá Ubicación/GPS (Ajustes) y volvé a intentar.';
          _busy = false;
        });
        return;
      }
    } catch (_) {}

    // Pedimos con permission_handler (más confiable para mostrar popup)
    try {
      var st = await Permission.location.status;
      if (!st.isGranted) {
        st = await _withTimeout(Permission.location.request(), seconds: 8);
      }

      // Si quedó denegado permanentemente, guiamos a Ajustes (sin loop)
      if (st.isPermanentlyDenied) {
        setState(() {
          _status =
              'Permiso de ubicación BLOQUEADO. Tocá "Abrir Ajustes" y permití Ubicación.';
          _busy = false;
        });
        return;
      }

      if (!st.isGranted) {
        setState(() {
          _status = 'Permiso de ubicación denegado. Sin eso la app no puede funcionar.';
          _busy = false;
        });
        return;
      }

      // Best-effort: si tu app requiere "Siempre", intentamos pedirlo.
      // En muchos Android esto NO muestra popup; por eso solo intentamos con timeout y sin colgar.
      final always = await Permission.locationAlways.status;
      if (!always.isGranted) {
        await _withTimeout(Permission.locationAlways.request(), seconds: 8);
      }
    } catch (_) {
      // Si algo falla, no dejamos colgado el wizard.
    }

    setState(() {
      _status = 'Listo. Revisá Ajustes si algo quedó pendiente.';
      _busy = false;
    });

    await _setDone();

    if (!mounted) return;
    widget.onDone?.call();

    if (widget.onDone == null) {
      final nav = Navigator.of(context);
      if (nav.canPop()) nav.pop();
    }
  }


  Widget _step(String title, String subtitle, {required Widget trailing}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle),
        trailing: trailing,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dejar la app lista (Wizard)'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _step(
              '1) Notificaciones',
              'Necesario para alarmas de proximidad (Android 13+).',
              trailing: ElevatedButton(
                onPressed: _busy
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        await Permission.notification.request();
                        setState(() => _busy = false);
                      },
                child: const Text('Permitir'),
              ),
            ),
            const SizedBox(height: 10),
            _step(
              '2) Ubicación precisa + Siempre',
              'Poné “Precisa” y, si te deja, “Permitir siempre”.',
              trailing: ElevatedButton(
                onPressed: _busy ? null : () async => openAppSettings(),
                child: const Text('Ajustes'),
              ),
            ),
            const SizedBox(height: 10),
            _step(
              '3) Ubicación del sistema',
              'Activá el GPS del teléfono si está apagado.',
              trailing: ElevatedButton(
                onPressed: _busy
                    ? null
                    : () async {
                        await Geolocator.openLocationSettings();
                      },
                child: const Text('GPS'),
              ),
            ),
            const SizedBox(height: 10),
            _step(
              '4) Batería (muy importante)',
              'Desactivá optimización de batería para que NO se corte el fondo.',
              trailing: ElevatedButton(
                onPressed: _busy ? null : () async => openAppSettings(),
                child: const Text('Ajustes'),
              ),
            ),
            const SizedBox(height: 10),
            if (_status.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_status,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: _busy ? null : _runAll,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: const Text('HACER TODO (RECOMENDADO)'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ======================================================================
// >>>>>>>>>>>> SEPARABLE: app_shell.dart (desde acá) <<<<<<<<<<<<<<<<<<<
// ======================================================================
// AppShell = "enchufe limpio" para mañana reemplazar por tu HOME real
// - Hoy devuelve HomeScreen (core)
// - Mañana podés devolver tu Navigator con tabs sin tocar AccessGate
// ======================================================================

class AppShell extends StatelessWidget {
  final bool isAdmin;
  final String myPhone;
  const AppShell({super.key, required this.isAdmin, required this.myPhone});

  Future<bool> _wizardDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(K_WIZARD_DONE) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _wizardDone(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final done = snap.data ?? false;
        if (!done) {
          return PermissionWizardScreen(
            onDone: () {
              // ✅ Cierre explícito del Wizard: vamos directo al HOME real.
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) =>
                      HomeScreen(isAdmin: isAdmin, myPhone: myPhone),
                ),
              );
            },
          );
        }

        return HomeScreen(isAdmin: isAdmin, myPhone: myPhone); // HOME real
      },
    );
  }
}

// ======================================================================
// >>>>>>>>>>>> SEPARABLE: home.dart (desde acá) <<<<<<<<<<<<<<<<<<<<<<<<
// ======================================================================
// HOME (Core)
// ======================================================================

class HomeScreen extends StatefulWidget {
  final bool isAdmin;
  final String myPhone;
  const HomeScreen({super.key, required this.isAdmin, required this.myPhone});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? phone;
  GateStatus? gate;

  // ================== NAVEGACIÓN (BOTTOM TABS) ==================
  int _tabIndex = 0;

  // Badge: auxilio activo para este usuario
  Stream<QuerySnapshot<Map<String, dynamic>>> _auxilioBadgeStream(String myPhoneDigits) {
    // Estados considerados "activo"
    return FirebaseFirestore.instance
        .collection(FS_AUXILIOS_COL)
        .where('requesterPhone', isEqualTo: myPhoneDigits)
        .where('status', whereIn: ['open', 'accepted', 'arrived', 'pending_confirm'])
        .limit(1)
        .snapshots();
  }

  Widget _buildMapaTab() {
    final markers = _markers();
    final activos = reportes.where((r) => r.activo).toList();
    final radioMetros = radioKm * 1000.0;

    final cercanos = <Reporte>[];
    for (final r in activos) {
      final d = _distanciaMetrosA(r);
      if (d != null && d <= radioMetros) {
        cercanos.add(r);
      }
    }
    cercanos.sort((a, b) => ((_distanciaMetrosA(a) ?? 999999).compareTo(_distanciaMetrosA(b) ?? 999999)));

    String distTxt(Reporte r) {
      final d = _distanciaMetrosA(r);
      if (d == null) return r.esGps ? 'Sin distancia' : 'A distancia';
      if (d < 1000) return '${d.round()} m';
      return '${(d / 1000).toStringAsFixed(1)} km';
    }

    Widget statCard({required IconData icon, required String title, required String value}) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 3)),
            ],
          ),
          child: Column(
            children: [
              Icon(icon, size: 20),
              const SizedBox(height: 6),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              const SizedBox(height: 2),
              Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Row(
            children: [
              statCard(icon: Icons.place_rounded, title: 'Activos', value: '${activos.length}'),
              const SizedBox(width: 8),
              statCard(icon: Icons.near_me_rounded, title: 'Cerca tuyo', value: '${cercanos.length}'),
              const SizedBox(width: 8),
              statCard(icon: Icons.tune_rounded, title: 'Radio', value: '${radioKm.toStringAsFixed(1)} km'),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: tracking && lastLat != null && lastLng != null ? Colors.green.shade50 : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  tracking && lastLat != null && lastLng != null ? 'GPS activo' : 'Sin posición',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: tracking && lastLat != null && lastLng != null ? Colors.green.shade800 : Colors.orange.shade900,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  activos.isEmpty ? 'Todavía no hay avisos activos.' : 'Tocá Mapa para ver mejor los avisos y tu zona.',
                  style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: const LatLng(-31.3929, -58.0209),
                  initialZoom: 14,
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                    subdomains: const ['a', 'b', 'c'],
                    userAgentPackageName: 'com.example.resistencia_operativos',
                  ),
                  MarkerLayer(markers: markers),
                ],
              ),
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 3)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Avisos cercanos', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 10),
              if (cercanos.isEmpty)
                Text(
                  tracking && lastLat != null && lastLng != null
                      ? 'No tenés avisos dentro de tu radio actual.'
                      : 'Activá el servicio para ordenar por cercanía real.',
                  style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700),
                )
              else
                ...cercanos.take(3).map((r) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colorPorTipo(r.tipo).withOpacity(.08),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Icon(iconPorTipo(r.tipo), color: colorPorTipo(r.tipo)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(tipoTexto(r.tipo), style: const TextStyle(fontWeight: FontWeight.w900)),
                                const SizedBox(height: 2),
                                Text(r.tituloCorto, maxLines: 2, overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(distTxt(r), style: const TextStyle(fontWeight: FontWeight.w900)),
                        ],
                      ),
                    )),
            ],
          ),
        ),
      ],
    );
  }

Widget _buildAuxilioTab() {
    final myPhoneDigits = _onlyDigits(widget.myPhone);

    // Streams principales
    Stream<QuerySnapshot<Map<String, dynamic>>> sActivosCerca() {
      // Por privacidad/rendimiento, lo ideal es filtrar por zona y/o radio.
      // MVP: mostramos los últimos auxilios OPEN.
      return FirebaseFirestore.instance
          .collection(FS_AUXILIOS_COL)
          .where('status', isEqualTo: 'open')
          .orderBy('createdAt', descending: true)
          .limit(25)
          .snapshots();
    }

    Stream<QuerySnapshot<Map<String, dynamic>>> sAceptados() {
      return FirebaseFirestore.instance
          .collection(FS_AUXILIOS_COL)
          .where('helperPhone', isEqualTo: myPhoneDigits)
          .where('status', whereIn: ['accepted', 'arrived', 'pending_confirm'])
          .orderBy('createdAt', descending: true)
          .limit(25)
          .snapshots();
    }

    Stream<QuerySnapshot<Map<String, dynamic>>> sMisPedidos() {
      return FirebaseFirestore.instance
          .collection(FS_AUXILIOS_COL)
          .where('requesterPhone', isEqualTo: myPhoneDigits)
          .where('status', whereIn: ['open', 'accepted', 'arrived', 'pending_confirm'])
          .orderBy('createdAt', descending: true)
          .limit(25)
          .snapshots();
    }

    Stream<QuerySnapshot<Map<String, dynamic>>> sHistorial() {
      // Historial simple: lo que yo pedí o acepté y ya terminó.
      // Para MVP, mostramos solo mis pedidos finalizados/cancelados/expirados/disputed.
      return FirebaseFirestore.instance
          .collection(FS_AUXILIOS_COL)
          .where('requesterPhone', isEqualTo: myPhoneDigits)
          .where('status', whereIn: ['resolved', 'cancelled', 'expired', 'disputed'])
          .orderBy('createdAt', descending: true)
          .limit(40)
          .snapshots();
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ===== Mini dashboard superior =====
        Card(
          elevation: 1.5,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('AUXILIO',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _kpiBox(
                        title: 'Puntos',
                        value: '$puntos',
                        icon: Icons.stars_rounded,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _kpiBox(
                        title: 'Créditos',
                        value: '$_creditosAuxilio',
                        icon: Icons.confirmation_number_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _estadoAuxilioWidget(myPhoneDigits),
                const SizedBox(height: 12),
                Row(
                  children: [
StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: sMisPedidos(),
                      builder: (context, snap) {
                        final docs = snap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                        if (docs.isNotEmpty) {
                          final activeDoc = docs.first;
                          final data = activeDoc.data();
                          final status = (data['status'] ?? 'open').toString();

                          String ctaLabel = 'VER AUXILIO EN CURSO';
                          String subtitle = 'Tenés un auxilio activo. Entrá al detalle para seguirlo.';
                          IconData ctaIcon = Icons.open_in_new_rounded;
                          Color ctaColor = Colors.blue;
                          bool showChatChip = false;

                          switch (status) {
                            case 'open':
                              ctaLabel = 'VER AUXILIO EN CURSO';
                              subtitle = 'Tu pedido ya fue enviado. Esperá que alguien lo tome o abrilo para ver novedades.';
                              ctaIcon = Icons.hourglass_top_rounded;
                              ctaColor = Colors.orange;
                              break;
                            case 'accepted':
                              ctaLabel = 'AYUDA EN CAMINO';
                              subtitle = 'Un ayudante aceptó tu auxilio. Podés abrir el detalle y usar el chat para coordinar.';
                              ctaIcon = Icons.directions_run_rounded;
                              ctaColor = Colors.blue;
                              showChatChip = true;
                              break;
                            case 'arrived':
                              ctaLabel = 'AYUDANTE EN EL LUGAR';
                              subtitle = 'El ayudante marcó llegada. Abrí el detalle para coordinar o revisar el chat.';
                              ctaIcon = Icons.place_rounded;
                              ctaColor = Colors.green;
                              showChatChip = true;
                              break;
                            case 'pending_confirm':
                              ctaLabel = 'CONFIRMAR AYUDA';
                              subtitle = 'Ya podés confirmar que te ayudaron. Entrá al detalle para cerrar el auxilio.';
                              ctaIcon = Icons.verified_user_rounded;
                              ctaColor = Colors.purple;
                              showChatChip = true;
                              break;
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: ctaColor.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: ctaColor.withOpacity(0.20)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(ctaIcon, color: ctaColor),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            ctaLabel,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 15,
                                              color: ctaColor,
                                            ),
                                          ),
                                        ),
                                        if (showChatChip)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius: BorderRadius.circular(999),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.chat_bubble_outline_rounded, size: 16),
                                                SizedBox(width: 6),
                                                Text(
                                                  'Chat activo',
                                                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      subtitle,
                                      style: const TextStyle(
                                        color: Colors.black87,
                                        fontWeight: FontWeight.w600,
                                        height: 1.25,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              _auxilioCard(
                                doc: activeDoc,
                                myPhoneDigits: myPhoneDigits,
                                mode: _AuxCardMode.miPedido,
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton.icon(
                                onPressed: () => _openAuxilioDetail(activeDoc.reference, myPhoneDigits),
                                icon: Icon(ctaIcon),
                                label: Text(
                                  ctaLabel,
                                  style: const TextStyle(fontWeight: FontWeight.w900),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: ctaColor,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size.fromHeight(52),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                minimumSize: const Size.fromHeight(52),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed: () => _pedirAuxilioFlow(myPhoneDigits),
                              icon: const Icon(Icons.sos),
                              label: const Text(
                                'PEDIR AUXILIO',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Si necesitás asistencia, tocá el botón y creá un auxilio nuevo. Si después alguien lo acepta, vas a poder seguir todo desde acá.',
                              style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w600),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  '“Cualquier acuerdo económico entre solicitante y ayudante es externo a la plataforma. '
                  'La aplicación no interviene ni se responsabiliza por transacciones privadas.”',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 14),

        // ===== Secciones =====
        _sectionTitle('Auxilios activos cercanos'),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: sActivosCerca(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final docs = snap.data?.docs ?? [];
            if (docs.isEmpty) return _emptyHint('No hay auxilios activos cerca.');

            final meLat = lastLat;
            final meLng = lastLng;

            final items = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            for (final d in docs) {
              final data = d.data();
              final requester = (data['requesterPhone'] ?? '').toString();
              if (requester == myPhoneDigits) continue; // no mostrar mis propios pedidos acá
              if ((data['status'] ?? 'open').toString() != 'open') continue;

              // Si tengo GPS, filtro por un radio razonable (10 km) para evitar ruido.
              if (meLat != null && meLng != null) {
                final rLat = (data['requesterLat'] as num?)?.toDouble();
                final rLng = (data['requesterLng'] as num?)?.toDouble();
                if (rLat != null && rLng != null) {
                  final dist = Geolocator.distanceBetween(meLat, meLng, rLat, rLng);
                  if (dist > 10000) continue; // 10 km
                }
              }
              items.add(d);
            }

            if (items.isEmpty) {
              return _emptyHint(meLat == null ? 'Activá GPS para ver auxilios cercanos.' : 'No hay auxilios dentro de tu radio.');
            }

            // Ordenar por distancia si hay GPS
            if (meLat != null && meLng != null) {
              items.sort((a, b) {
                double da = 1e18, db = 1e18;
                final al = (a.data()['requesterLat'] as num?)?.toDouble();
                final ag = (a.data()['requesterLng'] as num?)?.toDouble();
                final bl = (b.data()['requesterLat'] as num?)?.toDouble();
                final bg = (b.data()['requesterLng'] as num?)?.toDouble();
                if (al != null && ag != null) da = Geolocator.distanceBetween(meLat, meLng, al, ag);
                if (bl != null && bg != null) db = Geolocator.distanceBetween(meLat, meLng, bl, bg);
                return da.compareTo(db);
              });
            }

            return Column(
              children: items.take(15).map((d) => _auxilioCard(
                    doc: d,
                    myPhoneDigits: myPhoneDigits,
                    mode: _AuxCardMode.activoCerca,
                  )).toList(),
            );
          },
        ),

_sectionTitle('Auxilios aceptados'),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: sAceptados(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final docs = snap.data?.docs ?? [];
            if (docs.isEmpty) return _emptyHint('No tenés auxilios aceptados.');
            return Column(
              children: docs
                  .map((d) => _auxilioCard(
                        doc: d,
                        myPhoneDigits: myPhoneDigits,
                        mode: _AuxCardMode.aceptado,
                      ))
                  .toList(),
            );
          },
        ),

        const SizedBox(height: 14),

        _sectionTitle('Mis pedidos de auxilio'),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: sMisPedidos(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final docs = snap.data?.docs ?? [];
            if (docs.isEmpty) return _emptyHint('No tenés pedidos activos.');
            return Column(
              children: docs
                  .map((d) => _auxilioCard(
                        doc: d,
                        myPhoneDigits: myPhoneDigits,
                        mode: _AuxCardMode.miPedido,
                      ))
                  .toList(),
            );
          },
        ),

        const SizedBox(height: 14),

        _sectionTitle('Historial'),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: sHistorial(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final docs = snap.data?.docs ?? [];
            if (docs.isEmpty) return _emptyHint('Sin historial todavía.');
            return Column(
              children: docs
                  .map((d) => _auxilioCard(
                        doc: d,
                        myPhoneDigits: myPhoneDigits,
                        mode: _AuxCardMode.historial,
                      ))
                  .toList(),
            );
          },
        ),
      ],
    );
  }


  Widget _buildReportarTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'REPORTAR',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
                SizedBox(height: 8),
                Text(
                  'Elegí el tipo de aviso y cargalo rápido. Si tenés GPS activo, el reporte sale con ubicación real.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _reportQuickCard(
          title: 'Operativo',
          subtitle: 'Controles, alcoholemia y documentación',
          icon: Icons.local_police,
          color: Colors.red,
          onTap: reportarDialogo,
        ),
        _reportQuickCard(
          title: 'Calle cortada',
          subtitle: 'Cortes, desvíos y bloqueos',
          icon: Icons.block,
          color: Colors.blueGrey,
          onTap: reportarDialogo,
        ),
        _reportQuickCard(
          title: 'Accidente',
          subtitle: 'Choques, vehículos detenidos, riesgo',
          icon: Icons.car_crash,
          color: Colors.orange,
          onTap: reportarDialogo,
        ),
        _reportQuickCard(
          title: 'Manifestación',
          subtitle: 'Piquetes, marchas o concentración',
          icon: Icons.campaign,
          color: Colors.deepPurple,
          onTap: reportarDialogo,
        ),
        const SizedBox(height: 16),
        Card(
          color: Colors.blueGrey.shade50,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Consejos rápidos',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  tracking && lastLat != null && lastLng != null
                      ? 'GPS activo: el aviso se enviará con ubicación real.'
                      : 'Sin GPS activo: el aviso saldrá como reporte a distancia.',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Usá reportes reales. El sistema aplica controles anti-spam y validación comunitaria.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _reportQuickCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 10,
                  offset: Offset(0, 3),
                  color: Color(0x14000000),
                ),
              ],
              border: Border.all(color: color.withOpacity(.18)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: color.withOpacity(.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: color, size: 28),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: const TextStyle(
                                fontWeight: FontWeight.w900, fontSize: 16)),
                        const SizedBox(height: 2),
                        Text(subtitle,
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade700)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCuentaTab() {
    final myDigits = _onlyDigits(widget.myPhone);
    final isFounder = myDigits == _onlyDigits(FOUNDER_PHONE);

    Widget item({
      required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
      Color? color,
    }) {
      final c = color ?? Colors.blueGrey.shade700;
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: c.withOpacity(.12),
            child: Icon(icon, color: c),
          ),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: onTap,
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.blueGrey.shade100,
                child: Icon(Icons.person_rounded, color: Colors.blueGrey.shade800, size: 30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tu cuenta',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      myDigits.isEmpty ? 'Número no detectado' : myDigits,
                      style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _cuentaChip(isFounder ? 'Fundador' : (widget.isAdmin ? 'Admin' : 'Usuario')),
                        _cuentaChip('Puntos $puntos'),
                        _cuentaChip('Reputación $reputacion'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        item(
          icon: Icons.help_outline_rounded,
          title: 'Ayuda e información',
          subtitle: 'Sistema de puntos, alertas, validaciones y uso general.',
          onTap: abrirAyuda,
        ),
        if (widget.isAdmin)
          item(
            icon: Icons.settings_rounded,
            title: 'Configuración',
            subtitle: 'Reglas, whitelist, panel administrativo y ajustes internos.',
            onTap: abrirConfiguracion,
            color: Colors.indigo,
          ),
        if (widget.isAdmin)
          item(
            icon: Icons.history_rounded,
            title: 'Historial',
            subtitle: 'Revisar reportes, movimientos y actividad reciente.',
            onTap: abrirHistorial,
            color: Colors.deepOrange,
          ),
        item(
          icon: Icons.shield_rounded,
          title: 'Estado del servicio',
          subtitle: 'Servicio: $estadoServicio · GPS: $estadoGps',
          onTap: () {
            snack('Servicio: $estadoServicio · GPS: $estadoGps');
          },
          color: tracking ? Colors.green : Colors.red,
        ),
      ],
    );
  }


  // ================== ESTADO SERVIDOR / REVALIDAR ACCESO ==================
  Widget _buildServerStatusCard() {
    if (!USE_REMOTE_PAYWALL) return const SizedBox.shrink();

    final me = _onlyDigits(widget.myPhone);
    final isFounder = me == _onlyDigits(FOUNDER_PHONE);

    final st = gate; // GateStatus global/cacheado
    final ok = (st != null && st.ok);
    final paid = (st != null && st.isPaid);
    final reqPay = (st != null && st.requiresPayment);

    final statusText =
        (st == null) ? 'Sin estado (no validado)' : (ok ? 'OK' : 'NO OK');

    final detail = (st == null)
        ? ''
        : 'user# ${st.userNumber ?? '-'} · freeLimit ${st.freeLimit} · paid ${paid ? 'SI' : 'NO'} · requiresPayment ${reqPay ? 'SI' : 'NO'}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Estado del servidor',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text('Gate: $statusText'),
            if (detail.isNotEmpty) Text(detail),
            if (st != null && (st.message).trim().isNotEmpty)
              Text('Msg: ${st.message}'),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final pd = _onlyDigits(widget.myPhone);
                  if (pd.isEmpty) return;
                  try {
                    final fresh = await RemotePaywallApi.registerOrGetStatus(
                      phoneDigits: pd,
                    );
                    await RemotePaywallApi.cacheStatus(pd, fresh);
                    gate = fresh;
                  } catch (_) {}
                  if (!mounted) return;
                  setState(() {});
                },
                icon: const Icon(Icons.cloud_sync),
                label: const Text('Revalidar acceso'),
              ),
            ),
            if (!isFounder)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Tip: si el server se cae, el acceso se bloquea (por seguridad).',
                  style: TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool _trackingActive = false; // anti-spam: no reiniciar si ya esta activo

  // ===== Persistencia =====
  Timer? _saveDebounce;
  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 600), _saveState);
  }

  // ===== Locks anti doble-tap (estabilidad) =====
  bool _starting = false;
  bool _stopping = false;

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _saveState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'puntos': puntos,
        'reputacion': reputacion,
        'radioKm': radioKm,
        'modoAlerta': modoAlerta.name,
        'avisoSonido': avisoSonido.name,
        'avisarOperativos': avisarOperativos,
        'avisarAccidentes': avisarAccidentes,
        'avisarPiquetes': avisarPiquetes,
        'avisarCallesCortadas': avisarCallesCortadas,
        'reportes': reportes.map((e) => e.toMap()).toList(),

        // anti-spam memoria
        'lastReportTs': lastReportTs,
        'lastReportTipoTs': lastReportTipoTs,
        'rateWindow': rateWindow,

        // backup version
        'schema': 1,
      };
      await prefs.setString(K_STATE, jsonEncode(data));
    } catch (_) {}
  }

  Future<void> _loadState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(K_STATE);
      if (raw == null || raw.trim().isEmpty) return;

      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final rp = (decoded['reportes'] as List<dynamic>? ?? [])
          .map((e) => Reporte.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();

      setState(() {
        puntos = (decoded['puntos'] as num?)?.toInt() ?? 0;
        reputacion = (decoded['reputacion'] as num?)?.toInt() ?? 50;

        radioKm = (decoded['radioKm'] as num?)?.toDouble() ?? 1.5;

        final ma = decoded['modoAlerta'] as String?;
        modoAlerta = AlertaModo.values.firstWhere(
          (e) => e.name == ma,
          orElse: () => AlertaModo.unaSolaVez,
        );

        final as = decoded['avisoSonido'] as String?;
        avisoSonido = AvisoSonido.values.firstWhere(
          (e) => e.name == as,
          orElse: () => AvisoSonido.silencioso,
        );

        avisarOperativos = (decoded['avisarOperativos'] as bool?) ?? true;
        avisarAccidentes = (decoded['avisarAccidentes'] as bool?) ?? true;
        avisarPiquetes = (decoded['avisarPiquetes'] as bool?) ?? true;
        avisarCallesCortadas =
            (decoded['avisarCallesCortadas'] as bool?) ?? true;

        reportes
          ..clear()
          ..addAll(rp);

        // anti-spam
        lastReportTs = (decoded['lastReportTs'] as num?)?.toInt() ?? 0;
        lastReportTipoTs = Map<String, int>.from((decoded['lastReportTipoTs']
                    as Map?)
                ?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())) ??
            {});
        rateWindow = (decoded['rateWindow'] as List?)
                ?.map((e) => (e as num).toInt())
                .toList() ??
            [];
      });

      _limpiarVencidos();
    } catch (_) {}
  }

  // ===== PUNTOS / REPUTACION =====
  int puntos = 0;
  int reputacion = 50;
  int _creditosAuxilio = 0;

  void sumarPuntos(int v) {
    setState(() {
      puntos += v;
      reputacion = (reputacion + 1).clamp(0, 100);
    });
    _scheduleSave();
  }

  Future<void> _incPointsFS(String phoneDigits, int deltaPoints, {int deltaRep = 0}) async {
    try {
      final ref = FirebaseFirestore.instance.collection(FS_USERS_COL).doc(phoneDigits);
      await ref.set({
        'phone': phoneDigits,
        'points': FieldValue.increment(deltaPoints),
        if (deltaRep != 0) 'reputation': FieldValue.increment(deltaRep),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _incAuxCreditsFS(String phoneDigits, int deltaCredits) async {
    try {
      final ref = FirebaseFirestore.instance.collection(FS_USERS_COL).doc(phoneDigits);
      await ref.set({
        'phone': phoneDigits,
        'auxCredits': FieldValue.increment(deltaCredits),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  // ===== GPS =====
  bool tracking = false;
  String estadoServicio = 'Detenido';
  String estadoGps = 'GPS apagado';
  double? lastLat;
  double? lastLng;
  DateTime? lastFixAt;

  StreamSubscription<Position>? sub;
  Timer? _timerLimpieza;
  Timer? _gpsWatchdog;

  // ===== REPORTES =====
  final List<Reporte> reportes = [];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _reportesSub;

  // ===== PROXIMIDAD =====
  double radioKm = 1.5;
  AlertaModo modoAlerta = AlertaModo.unaSolaVez;
  AvisoSonido avisoSonido = AvisoSonido.silencioso;

  bool avisarOperativos = true;
  bool avisarAccidentes = true;
  bool avisarPiquetes = true;
  bool avisarCallesCortadas = true;

  final Map<String, int> _ultimaAlertaPorReporte = {};
  int _nextNotifId = 2000;

// ===== Throttle de notificaciones (evita spam) =====
  final Map<String, DateTime> _notiLastAt = {};
  DateTime? _lastGpsStreamRestartAt;

  // validar
  final Map<String, int> _ultimaValidacionPorReporte = {};

  final Distance _distance = const Distance();

  // ===== Anti-spam (A) memoria en runtime =====
  int lastReportTs = 0;
  Map<String, int> lastReportTipoTs = {};
  List<int> rateWindow = [];

  // ================== INIT ==================
  @override
  void initState() {
    super.initState();
    phone = widget.myPhone;
    if (USE_REMOTE_PAYWALL) {
      RemotePaywallApi.loadCachedStatus(_onlyDigits(widget.myPhone)).then((st) {
        if (!mounted) return;
        setState(() => gate = st);
      });
    }
    _loadState();
    _subscribeReportesFS();
  }


  // ================== REPORTES FIRESTORE ==================
  void _upsertReporteLocal(Reporte r) {
    final i = reportes.indexWhere((e) => e.id == r.id);
    if (i >= 0) {
      reportes[i] = r;
    } else {
      reportes.insert(0, r);
    }
  }

  void _subscribeReportesFS() {
    try {
      _reportesSub?.cancel();
      _reportesSub = FirebaseFirestore.instance
          .collection(FS_REPORTES_COL)
          .orderBy('fechaMs', descending: true)
          .limit(300)
          .snapshots()
          .listen((snap) {
        if (!mounted) return;
        bool changed = false;
        for (final doc in snap.docs) {
          try {
            final data = doc.data();
            final map = Map<String, dynamic>.from(data);
            map['id'] = (map['id'] as String?) ?? doc.id;
            final r = Reporte.fromMap(map);
            final idx = reportes.indexWhere((e) => e.id == r.id);
            if (idx >= 0) {
              reportes[idx] = r;
            } else {
              reportes.insert(0, r);
            }
            changed = true;
          } catch (_) {}
        }
        if (changed) {
          setState(() {});
          _scheduleSave();
        }
      });
    } catch (_) {
      // Firebase no configurado o colección todavía vacía/indisponible.
    }
  }

  Future<void> _pushReporteFS(Reporte r) async {
    try {
      if (Firebase.apps.isEmpty) return;
      await FirebaseFirestore.instance.collection(FS_REPORTES_COL).doc(r.id).set({
        ...r.toMap(),
        'id': r.id,
        'fechaMs': r.fecha.millisecondsSinceEpoch,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'sourcePhone': _onlyDigits(widget.myPhone),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _syncReporteEstadoFS(Reporte r) async {
    try {
      if (Firebase.apps.isEmpty) return;
      await FirebaseFirestore.instance.collection(FS_REPORTES_COL).doc(r.id).set({
        'id': r.id,
        'estado': r.estado.name,
        'validaciones': r.validaciones,
        'puntosAcreditados': r.puntosAcreditados,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  // ================== UI HELPERS ==================
  void snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text(msg, style: const TextStyle(fontWeight: FontWeight.w800))),
    );
  }

  // ================== NOTIFICAR ==================
  Future<void> _notificar(
      {required String titulo,
      required String body,
      String? throttleKey,
      Duration minInterval = const Duration(minutes: 5)}) async {
    final channelId = (avisoSonido == AvisoSonido.silencioso)
        ? CH_SILENCIO
        : (avisoSonido == AvisoSonido.vibracion)
            ? CH_VIBRA
            : CH_ALARMA;

// Throttle opcional por clave (ej: 'gps_restart')
    if (throttleKey != null) {
      final now = DateTime.now();
      final last = _notiLastAt[throttleKey];
      if (last != null && now.difference(last) < minInterval) {
        return; // evitamos spam
      }
      _notiLastAt[throttleKey] = now;
    }

    final androidDetails = AndroidNotificationDetails(
      channelId,
      (avisoSonido == AvisoSonido.silencioso)
          ? 'Avisos de Proximidad (Silencioso)'
          : 'Avisos de Proximidad (Alarma)',
      channelDescription: 'Avisos cuando estás cerca',
      importance: (avisoSonido == AvisoSonido.silencioso)
          ? Importance.high
          : Importance.max,
      priority: (avisoSonido == AvisoSonido.silencioso)
          ? Priority.high
          : Priority.max,
      playSound: avisoSonido == AvisoSonido.alarma,
      enableVibration: (avisoSonido == AvisoSonido.alarma) ||
          (avisoSonido == AvisoSonido.vibracion),
      silent: avisoSonido == AvisoSonido.silencioso,
    );

    _nextNotifId++;
    if (_nextNotifId > 9999) _nextNotifId = 2001;

    await _noti.show(_nextNotifId, titulo, body,
        NotificationDetails(android: androidDetails));
  }

  bool _tipoHabilitado(ReporteTipo t) {
    switch (t) {
      case ReporteTipo.operativo:
        return avisarOperativos;
      case ReporteTipo.accidente:
        return avisarAccidentes;
      case ReporteTipo.piquete:
        return avisarPiquetes;
      case ReporteTipo.calleCortada:
        return avisarCallesCortadas;
    }
  }

  // ================== PERMISOS ==================
  Future<bool> _asegurarPermisos() async {
    final notif = await Permission.notification.status;
    if (!notif.isGranted) {
      final req = await Permission.notification.request();
      if (!req.isGranted) {
        setState(() => estadoGps = 'Permití notificaciones');
        return false;
      }
    }

    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      setState(() => estadoGps = 'Activá ubicación del teléfono');
      return false;
    }

    LocationPermission p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }

    if (p == LocationPermission.denied) {
      setState(() => estadoGps = 'Permiso ubicación denegado');
      return false;
    }
    if (p == LocationPermission.deniedForever) {
      setState(
          () => estadoGps = 'Permiso bloqueado (Ajustes > Apps > Permisos)');
      return false;
    }
    return true;
  }

  // ================== STREAM SETTINGS ==================
  LocationSettings _settings() {
    return AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
      intervalDuration: const Duration(seconds: 3),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'Resistencia',
        notificationText: 'Alertas de proximidad activas',
        enableWakeLock: true,
        setOngoing: true,
      ),
    );
  }

  // ================== WATCHDOG ==================
  void _startGpsWatchdog() {
    _gpsWatchdog?.cancel();
    _gpsWatchdog = Timer.periodic(const Duration(milliseconds: GPS_WATCHDOG_MS),
        (_) async {
      if (!tracking) return;
      // Si ya teníamos fix pero se clavó (sin updates) reiniciamos stream + aviso
      if (lastFixAt != null) {
        final age = DateTime.now().difference(lastFixAt!);
        if (age.inSeconds >= 25) {
          final now = DateTime.now();
// Evita reinicios en bucle: como máximo 1 reinicio cada 2 minutos.
          if (_lastGpsStreamRestartAt != null &&
              now.difference(_lastGpsStreamRestartAt!) <
                  const Duration(minutes: 2)) {
            // Solo actualizamos estado una vez cada tanto para no spamear UI
            if (estadoGps != 'GPS: sin updates → esperando (cooldown)') {
              setState(
                  () => estadoGps = 'GPS: sin updates → esperando (cooldown)');
            }
            return;
          }
          _lastGpsStreamRestartAt = now;
          setState(() => estadoGps =
              'GPS: sin updates (${age.inSeconds}s) → reiniciando...');
          try {
            await sub?.cancel();
          } catch (_) {}
          try {
            sub = Geolocator.getPositionStream(locationSettings: _settings())
                .listen(
              (pos) async {
                setState(() {
                  lastLat = pos.latitude;
                  lastLng = pos.longitude;
                  lastFixAt = DateTime.now();
                  estadoGps = 'GPS activo ✔';
                });
                await _chequearProximidad(pos.latitude, pos.longitude);
              },
              onError: (e) async {
                await _stopTotal(gpsMsg: 'GPS error (reinicio): $e');
              },
            );
            await _notificar(
              titulo: 'GPS reiniciado',
              body: 'Se reactivó el seguimiento en segundo plano.',
              throttleKey: 'gps_restart',
              minInterval: const Duration(minutes: 15),
            );
          } catch (e) {
            setState(() => estadoGps = 'GPS: reinicio falló ($e)');
          }
          return;
        }
      }

      // si nunca tuvimos fix, hacemos fallback
      if (lastFixAt != null) return;

      try {
        setState(() => estadoGps = 'GPS: esperando fix... (fallback)');
        final p = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 12),
        );
        setState(() {
          lastLat = p.latitude;
          lastLng = p.longitude;
          lastFixAt = DateTime.now();
          estadoGps = 'GPS activo ✔ (fallback)';
        });
        await _chequearProximidad(p.latitude, p.longitude);
      } catch (e) {
        setState(() => estadoGps = 'GPS no responde: $e');
      }
    });
  }

  Future<void> _stopTotal({String? gpsMsg}) async {
    try {
      await sub?.cancel();
    } catch (_) {}
    sub = null;

    _timerLimpieza?.cancel();
    _timerLimpieza = null;

    _gpsWatchdog?.cancel();
    _gpsWatchdog = null;

    if (!mounted) return;
    setState(() {
      tracking = false;
      estadoServicio = 'Detenido';
      estadoGps = gpsMsg ?? 'GPS apagado';
      lastLat = null;
      lastLng = null;
      lastFixAt = null;
    });
  }

// ================== INICIAR / DETENER ==================
  Future<void> iniciar() async {
    // Anti doble-tap / anti duplicación
    if (_starting) return;
    if (tracking) {
      _toast('El servicio ya está activo');
      return;
    }
    _starting = true;
    try {
      final ok = await _asegurarPermisos();
      if (!ok) return;

      // Asegura que no queden streams/timers previos colgados
      try {
        await sub?.cancel();
      } catch (_) {}
      sub = null;

      _timerLimpieza?.cancel();
      _timerLimpieza = null;

      _gpsWatchdog?.cancel();
      _gpsWatchdog = null;

      setState(() {
        tracking = true;
        estadoServicio = 'Activo';
        estadoGps = 'Iniciando GPS...';
        lastFixAt = null;
      });

      _timerLimpieza = Timer.periodic(
        const Duration(seconds: 10),
        (_) => _limpiarVencidos(),
      );

      _startGpsWatchdog();

      sub = Geolocator.getPositionStream(locationSettings: _settings()).listen(
        (pos) async {
          setState(() {
            lastLat = pos.latitude;
            lastLng = pos.longitude;
            lastFixAt = DateTime.now();
            estadoGps = 'GPS activo ✔';
          });
          await _chequearProximidad(pos.latitude, pos.longitude);
        },
        onError: (e) async {
          await _stopTotal(gpsMsg: 'Error GPS: $e');
        },
      );
    } finally {
      _starting = false;
    }
  }

  Future<void> detener() async {
    // Anti doble-tap / anti duplicación
    if (_stopping) return;
    if (!tracking) return;
    _stopping = true;
    try {
      await _stopTotal();
    } finally {
      _stopping = false;
    }
  }

  // ================== LIMPIEZA VENCIDOS ==================
  void _limpiarVencidos() {
    if (reportes.isEmpty) return;
    bool cambio = false;

    for (final r in reportes) {
      if (r.estado == ReporteEstado.falso) continue;
      if (r.estado == ReporteEstado.cerrado) continue;
      if (r.vencido &&
          r.estado != ReporteEstado.expirado &&
          r.estado != ReporteEstado.validado) {
        r.estado = ReporteEstado.expirado;
        cambio = true;
      }
    }

    if (cambio && mounted) {
      setState(() {});
      _scheduleSave();
    }
  }

  Future<void> limpiarExpiradosManual() async {
    final before = reportes.length;
    reportes.removeWhere((r) => r.estado == ReporteEstado.expirado);
    final removed = before - reportes.length;
    setState(() {});
    _scheduleSave();
    snack('🧹 Expirados eliminados: $removed');
  }

  // ================== PROXIMIDAD ==================
  Future<void> _chequearProximidad(double lat, double lng) async {
    if (reportes.isEmpty) return;

    final radioMetros = radioKm * 1000.0;
    final now = DateTime.now().millisecondsSinceEpoch;

    Reporte? mejor;
    double? mejorDist;

    for (final r in reportes) {
      if (!r.esGps) continue;
      if (!r.activo) continue;
      if (!_tipoHabilitado(r.tipo)) continue;

      final m = _distance.as(
        LengthUnit.Meter,
        LatLng(lat, lng),
        LatLng(r.lat!, r.lng!),
      );

      if (m <= radioMetros) {
        if (mejorDist == null || m < mejorDist) {
          mejorDist = m;
          mejor = r;
        }
      }
    }

    if (mejor == null || mejorDist == null) return;

    final ultima = _ultimaAlertaPorReporte[mejor.id] ?? 0;

    if (modoAlerta == AlertaModo.unaSolaVez) {
      if (ultima != 0) return;
      _ultimaAlertaPorReporte[mejor.id] = now;
    } else {
      if (now - ultima < 30000) return;
      _ultimaAlertaPorReporte[mejor.id] = now;
    }

    final km = (mejorDist / 1000).toStringAsFixed(2);
    snack('📍 Cerca ($km km) — ${mejor.tituloCorto}');
    await _notificar(titulo: '📍 Cerca ($km km)', body: mejor.tituloCorto);
  }

  // ================== ANTI-SPAM (A) ==================
  bool _antiSpamCheck({
    required ReporteTipo tipo,
    required bool hasGps,
    required double? lat,
    required double? lng,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;

    // rate-limit
    rateWindow = rateWindow.where((t) => now - t <= RL_WINDOW_MS).toList();
    if (rateWindow.length >= RL_MAX_REPORTES) {
      final faltan = ((RL_WINDOW_MS - (now - rateWindow.first)) / 1000).ceil();
      snack('⛔ Límite de reportes alcanzado. Esperá ~${faltan}s.');
      return false;
    }

    // cooldown por tipo
    final lastTipo = lastReportTipoTs[tipo.name] ?? 0;
    final cd = (tipo == ReporteTipo.operativo) ? CD_OPERATIVO_MS : CD_OTROS_MS;
    if (lastTipo != 0 && now - lastTipo < cd) {
      final faltan = ((cd - (now - lastTipo)) / 1000).ceil();
      snack('⏳ Cooldown ${tipoTexto(tipo)}: esperá ${faltan}s.');
      return false;
    }

    // anti-duplicado GPS
    if (hasGps && lat != null && lng != null) {
      for (final r in reportes) {
        if (!r.esGps) continue;
        if (r.tipo != tipo) continue;
        final dt = now - r.fecha.millisecondsSinceEpoch;
        if (dt > DUP_WINDOW_MS) continue;

        final m = _distance.as(
          LengthUnit.Meter,
          LatLng(lat, lng),
          LatLng(r.lat!, r.lng!),
        );
        if (m <= DUP_METROS) {
          snack(
              '⛔ Duplicado: ya hay un ${tipoTexto(tipo)} cerca (${m.round()}m).');
          return false;
        }
      }
    }

    // pasa: registra
    rateWindow.add(now);
    lastReportTipoTs[tipo.name] = now;
    lastReportTs = now;
    _scheduleSave();
    return true;
  }

  // ================== REPORTAR ==================
  Future<void> reportarDialogo() async {
    ReporteTipo tipo = ReporteTipo.operativo;
    String vehiculo = 'autos';
    String control = 'alcoholemia';
    String fuerza = 'transito';

    final r = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            final hasGps = tracking && lastLat != null && lastLng != null;

            InputDecoration deco(String label) {
              return InputDecoration(
                labelText: label,
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              );
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              actionsPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              title: const Text(
                'Nuevo reporte',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<ReporteTipo>(
                        value: tipo,
                        decoration: deco('Tipo de aviso'),
                        borderRadius: BorderRadius.circular(14),
                        items: const [
                          DropdownMenuItem(value: ReporteTipo.operativo, child: Text('Operativo')),
                          DropdownMenuItem(value: ReporteTipo.accidente, child: Text('Accidente')),
                          DropdownMenuItem(value: ReporteTipo.piquete, child: Text('Manifestación')),
                          DropdownMenuItem(value: ReporteTipo.calleCortada, child: Text('Calle cortada')),
                        ],
                        onChanged: (v) => setStateDialog(() {
                          tipo = v ?? ReporteTipo.operativo;
                        }),
                      ),
                      const SizedBox(height: 12),
                      if (tipo == ReporteTipo.operativo) ...[
                        DropdownButtonFormField<String>(
                          value: vehiculo,
                          decoration: deco('Vehículos alcanzados'),
                          borderRadius: BorderRadius.circular(14),
                          items: const [
                            DropdownMenuItem(value: 'autos', child: Text('Autos')),
                            DropdownMenuItem(value: 'motos', child: Text('Motos')),
                            DropdownMenuItem(value: 'ambos', child: Text('Autos y motos')),
                          ],
                          onChanged: (v) => setStateDialog(() {
                            vehiculo = v ?? 'autos';
                          }),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: control,
                          decoration: deco('Tipo de control'),
                          borderRadius: BorderRadius.circular(14),
                          items: const [
                            DropdownMenuItem(value: 'alcoholemia', child: Text('Alcoholemia')),
                            DropdownMenuItem(value: 'documentacion', child: Text('Control de documentación')),
                          ],
                          onChanged: (v) => setStateDialog(() {
                            control = v ?? 'alcoholemia';
                          }),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: fuerza,
                          decoration: deco('Fuerza interviniente'),
                          borderRadius: BorderRadius.circular(14),
                          items: const [
                            DropdownMenuItem(value: 'transito', child: Text('Tránsito')),
                            DropdownMenuItem(value: 'policia', child: Text('Policía')),
                          ],
                          onChanged: (v) => setStateDialog(() {
                            fuerza = v ?? 'transito';
                          }),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.orange.shade100),
                          ),
                          child: const Text(
                            '⚠ Los operativos con GPS quedan pendientes de validación comunitaria.',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: hasGps ? Colors.green.shade50 : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: hasGps ? Colors.green.shade100 : Colors.red.shade100,
                          ),
                        ),
                        child: Text(
                          hasGps
                              ? '📍 Se enviará con ubicación GPS.'
                              : '📍 Se enviará como aviso a distancia (sin GPS activo).',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: hasGps ? Colors.green.shade800 : Colors.red.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx, {
                      'tipo': tipo,
                      'vehiculo': vehiculo,
                      'control': control,
                      'fuerza': fuerza,
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text(
                    'Enviar reporte',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (r == null) return;

    final tipoSel = (r['tipo'] as ReporteTipo?) ?? ReporteTipo.operativo;
    final vehiculoSel = (r['vehiculo'] as String?) ?? 'autos';
    final controlSel = (r['control'] as String?) ?? 'alcoholemia';
    final fuerzaSel = (r['fuerza'] as String?) ?? 'transito';

    final hasGps = tracking && lastLat != null && lastLng != null;
    if (!_antiSpamCheck(
      tipo: tipoSel,
      hasGps: hasGps,
      lat: hasGps ? lastLat : null,
      lng: hasGps ? lastLng : null,
    )) {
      return;
    }

    final nuevo = Reporte(
      fecha: DateTime.now(),
      tipo: tipoSel,
      vehiculo: vehiculoSel,
      control: controlSel,
      fuerza: fuerzaSel,
      lat: hasGps ? lastLat : null,
      lng: hasGps ? lastLng : null,
    );

    reportes.insert(0, nuevo);
    _pushReporteFS(nuevo);
    setState(() {});

    if (tipoSel != ReporteTipo.operativo) {
      switch (tipoSel) {
        case ReporteTipo.accidente:
          sumarPuntos(P_AVISO_ACCIDENTE);
          snack('✅ Accidente reportado (+$P_AVISO_ACCIDENTE pts)');
          break;
        case ReporteTipo.piquete:
          sumarPuntos(P_AVISO_PIQUETE);
          snack('✅ Manifestación reportada (+$P_AVISO_PIQUETE pts)');
          break;
        case ReporteTipo.calleCortada:
          sumarPuntos(P_AVISO_CALLE_CORTADA);
          snack('✅ Calle cortada reportada (+$P_AVISO_CALLE_CORTADA pts)');
          break;
        case ReporteTipo.operativo:
          break;
      }
      nuevo.puntosAcreditados = true;
    } else {
      if (nuevo.esGps) {
        snack('✅ Operativo enviado (PENDIENTE hasta 3 validaciones)');
      } else {
        sumarPuntos(P_OPERATIVO_VALIDADO_DISTANCIA);
        nuevo.puntosAcreditados = true;
        snack('✅ Operativo a distancia (+$P_OPERATIVO_VALIDADO_DISTANCIA pts)');
      }
    }

    _scheduleSave();
  }

  double? _distanciaMetrosA(Reporte r) {
    if (!r.esGps) return null;
    if (lastLat == null || lastLng == null) return null;
    return _distance.as(
      LengthUnit.Meter,
      LatLng(lastLat!, lastLng!),
      LatLng(r.lat!, r.lng!),
    );
  }

  // ================== VALIDAR REAL ==================
  void validar(Reporte r) {
    if (r.tipo != ReporteTipo.operativo) return;
    if (!r.esGps) return;
    if (r.estado != ReporteEstado.pendiente) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _ultimaValidacionPorReporte[r.id] ?? 0;
    if (now - last < VALIDACION_COOLDOWN_MS) {
      snack('⏳ Esperá unos segundos para validar de nuevo.');
      return;
    }

    if (!tracking || lastLat == null || lastLng == null) {
      snack('⚠ Debés tener el GPS activo para validar.');
      return;
    }

    final metros = _distanciaMetrosA(r);
    if (metros == null) {
      snack('⚠ No se pudo calcular distancia.');
      return;
    }

    if (metros > VALIDACION_MAX_METROS) {
      snack(
          '❌ Estás lejos (${metros.round()} m). Para validar: ≤${VALIDACION_MAX_METROS.round()}m.');
      return;
    }

    _ultimaValidacionPorReporte[r.id] = now;

    r.validaciones += 1;
    sumarPuntos(P_VALIDAR_APORTE);

    if (r.validaciones >= 3) {
      r.estado = ReporteEstado.validado;
      if (!r.puntosAcreditados) {
        sumarPuntos(P_OPERATIVO_VALIDADO_GPS);
        r.puntosAcreditados = true;
        snack('✅ Operativo VALIDADO (+$P_OPERATIVO_VALIDADO_GPS pts)');
      } else {
        snack('✅ Operativo VALIDADO');
      }
    } else {
      snack('✔ Validación ${r.validaciones}/3 (+$P_VALIDAR_APORTE pts)');
    }

    setState(() {});
    _scheduleSave();
    _syncReporteEstadoFS(r);
  }

  // ================== FALSO ==================
  void marcarFalso(Reporte r) {
    if (r.estado == ReporteEstado.falso) return;
    r.estado = ReporteEstado.falso;
    snack('❌ Marcado como FALSO (instantáneo)');
    setState(() {});
    _scheduleSave();
    _syncReporteEstadoFS(r);
  }

  // ================== YA NO HAY (cierro sin “falso”) ==================
  void cerrarOperativo(Reporte r) {
    if (r.estado == ReporteEstado.cerrado) return;
    r.estado = ReporteEstado.cerrado;
    sumarPuntos(P_YA_NO_HAY_OPERATIVO);
    snack('✅ Marcado como "YA NO HAY" (+$P_YA_NO_HAY_OPERATIVO pts)');
    setState(() {});
    _scheduleSave();
    _syncReporteEstadoFS(r);
  }

  // ================== MAPA ==================
  
  // ================== AUXILIO (MVP COMPLETO) ==================

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(t,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
      );

  Widget _emptyHint(String t) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 10),
        child: Text(t, style: const TextStyle(color: Colors.black54)),
      );

  Widget _kpiBox({required String title, required String value, required IconData icon}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.black87),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Muestra un estado simple (derivado de Firestore) para el mini-dashboard.
  Widget _estadoAuxilioWidget(String myPhoneDigits) {
    final q = FirebaseFirestore.instance
        .collection(FS_AUXILIOS_COL)
        .where('requesterPhone', isEqualTo: myPhoneDigits)
        .where('status', whereIn: ['open', 'accepted', 'arrived', 'pending_confirm'])
        .orderBy('createdAt', descending: true)
        .limit(1);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        final doc = (snap.data?.docs.isNotEmpty ?? false) ? snap.data!.docs.first : null;
        final status = (doc?.data()['status'] ?? 'none') as String;

        String label;
        IconData ic;
        Color c;
        switch (status) {
          case 'open':
            label = 'Estado: esperando ayuda';
            ic = Icons.hourglass_bottom_rounded;
            c = Colors.orange;
            break;
          case 'accepted':
            label = 'Estado: un ayudante está en camino';
            ic = Icons.directions_run_rounded;
            c = Colors.blue;
            break;
          case 'arrived':
            label = 'Estado: ayudante llegó';
            ic = Icons.place_rounded;
            c = Colors.green;
            break;
          case 'pending_confirm':
            label = 'Estado: pendiente confirmación';
            ic = Icons.verified_user_rounded;
            c = Colors.purple;
            break;
          default:
            label = 'Estado: sin auxilio activo';
            ic = Icons.check_circle_outline_rounded;
            c = Colors.grey;
        }

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: c.withOpacity(0.10),
          ),
          child: Row(
            children: [
              Icon(ic, color: c),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: c)),
              ),
              if (doc != null)
                TextButton(
                  onPressed: () => _openAuxilioDetail(doc.reference, myPhoneDigits),
                  child: const Text('VER'),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<Position?> _getCurrentPosSafe() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return null;
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _pedirAuxilioFlow(String myPhoneDigits) async {
    // Regla: descuenta puntos al pedir; si no alcanza, consume crédito de auxilio (si tiene).
    const int costoPuntos = 400;

    if (puntos < costoPuntos && _creditosAuxilio <= 0) {
      _toast('No tenés puntos suficientes ni créditos de auxilio.');
      return;
    }

    final descCtrl = TextEditingController();
    final needsCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Pedir auxilio'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  controller: descCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '¿Qué te pasó? (obligatorio)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: needsCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: '¿Qué necesitás? (opcional)',
                    hintText: 'Ej: llave 10, cables, nafta…',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () {
                final d = descCtrl.text.trim();
                if (d.isEmpty) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('Crear'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    // Bloqueo anti-duplicado: un mismo solicitante no puede tener
    // más de un auxilio activo al mismo tiempo.
    try {
      final dup = await FirebaseFirestore.instance
          .collection(FS_AUXILIOS_COL)
          .where('requesterPhone', isEqualTo: myPhoneDigits)
          .where('status', whereIn: ['open', 'accepted', 'arrived', 'pending_confirm'])
          .limit(1)
          .get();

      if (dup.docs.isNotEmpty) {
        _toast('Ya tenés un auxilio activo. Cerralo o finalizalo antes de crear otro.');
        await _openAuxilioDetail(dup.docs.first.reference, myPhoneDigits);
        return;
      }
    } catch (_) {
      _toast('No se pudo validar si ya tenés un auxilio activo. Reintentá.');
      return;
    }

    // ✅ Descuento -400 (y/o consumo de Crédito de Auxilio) se hace SERVER-SIDE (Cloud Function).
    // El cliente NO debe escribir points/auxCredits para evitar fraude y PERMISSION_DENIED con Rules estrictas.
    final bool usedCredit = (puntos < costoPuntos && _creditosAuxilio > 0);

    final pos = await _getCurrentPosSafe();
    final now = DateTime.now();
    final expires = now.add(const Duration(minutes: 30));

    final data = <String, dynamic>{
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
      'debitPoints': costoPuntos,
      'debitType': usedCredit ? 'credit' : 'points',
      'expiresAt': Timestamp.fromDate(expires),
      'requesterPhone': myPhoneDigits,
      'requesterDesc': descCtrl.text.trim(),
      'needs': needsCtrl.text.trim().isEmpty
          ? []
          : needsCtrl.text
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList(),
      'requesterLat': pos?.latitude,
      'requesterLng': pos?.longitude,
      'helperPhone': null,
      'helperLat': null,
      'helperLng': null,
      'acceptedAt': null,
      'arrivedAt': null,
      'finishedAt': null,
      'requesterConfirmAt': null,

      // Cobro al solicitante: lo ejecuta Cloud Function (server-side)
      'requesterCharged': false,
      'requesterChargedPts': null,
      'requesterChargedAt': null,
      'chargeMode': usedCredit ? 'credit' : 'points',

      // Acreditación al ayudante: solo Admin (panel) para evitar fraude
      'credited': false,
      'creditedAt': null,
      'creditedBy': null,
      'creditReward': null,
      'creditBonus': null,
'logs': [
        {
          't': Timestamp.fromDate(now),
          'by': myPhoneDigits,
          'ev': 'create',
          'msg': 'Auxilio creado',
        }
      ],
    };

    try {
      final ref = await FirebaseFirestore.instance.collection(FS_AUXILIOS_COL).add(data);
      _toast('Auxilio creado.');
      await _openAuxilioDetail(ref, myPhoneDigits);
    } catch (e) {
      _toast('Error creando auxilio.');
      // No hay rollback local: el cobro lo hace el servidor al crear el auxilio.
    }
  }

  Future<void> _openAuxilioDetail(DocumentReference<Map<String, dynamic>> ref, String myPhoneDigits) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AuxilioDetailScreen(
          auxRef: ref,
          myPhoneDigits: myPhoneDigits,
          isAdmin: widget.isAdmin,
          getPos: _getCurrentPosSafe,
          onToast: _toast,
        ),
      ),
    );
  }

  Widget _auxilioCard({
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required String myPhoneDigits,
    required _AuxCardMode mode,
  }) {
    final d = doc.data();
    final status = (d['status'] ?? 'open').toString();
    final requester = (d['requesterPhone'] ?? '').toString();
    final helper = (d['helperPhone'] ?? '').toString();
    final desc = (d['requesterDesc'] ?? '').toString();
    final needs = (d['needs'] is List) ? (d['needs'] as List).join(', ') : '';
    final createdAt = (d['createdAt'] is Timestamp) ? (d['createdAt'] as Timestamp).toDate() : null;

    String badge = status;
    Color badgeColor = Colors.grey;
    switch (status) {
      case 'open':
        badgeColor = Colors.orange;
        badge = 'ACTIVO';
        break;
      case 'accepted':
        badgeColor = Colors.blue;
        badge = 'EN CAMINO';
        break;
      case 'arrived':
        badgeColor = Colors.green;
        badge = 'LLEGÓ';
        break;
      case 'pending_confirm':
        badgeColor = Colors.purple;
        badge = 'PEND. CONF.';
        break;
      case 'resolved':
        badgeColor = Colors.green;
        badge = 'FINALIZADO';
        break;
      case 'cancelled':
        badgeColor = Colors.red;
        badge = 'CANCELADO';
        break;
      case 'expired':
        badgeColor = Colors.grey;
        badge = 'EXPIRADO';
        break;
      case 'disputed':
        badgeColor = Colors.red;
        badge = 'REVISIÓN';
        break;
    }

    final title = (mode == _AuxCardMode.activoCerca)
        ? 'Auxilio cercano'
        : (mode == _AuxCardMode.aceptado)
            ? 'Aceptado por vos'
            : (mode == _AuxCardMode.miPedido)
                ? 'Tu pedido'
                : 'Historial';

    return Card(
      elevation: 1.5,
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openAuxilioDetail(doc.reference, myPhoneDigits),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: badgeColor.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(badge,
                        style: TextStyle(
                            fontWeight: FontWeight.w900, color: badgeColor)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(desc.isEmpty ? '(Sin descripción)' : desc,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              if (needs.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('Necesita: $needs',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.black54)),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('Solicitante: $requester',
                      style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  const SizedBox(width: 10),
                  if (helper.isNotEmpty)
                    Text('Ayudante: $helper',
                        style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  const Spacer(),
                  if (createdAt != null)
                    Text(
                      '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }


List<Marker> _markers() {
    return reportes
        .where((e) => e.esGps && e.activo)
        .map((r) => Marker(
              point: LatLng(r.lat!, r.lng!),
              width: 46,
              height: 46,
              child: Icon(iconPorTipo(r.tipo),
                  color: colorPorTipo(r.tipo), size: 42),
            ))
        .toList();
  }

  // ================== BORRAR TODO ==================
  Future<void> borrarTodo() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Borrar todo'),
        content: const Text(
            'Esto borra reportes, puntos y configuración guardada.\n\n¿Seguro?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('BORRAR')),
        ],
      ),
    );

    if (ok != true) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(K_STATE);

    setState(() {
      puntos = 0;
      reputacion = 50;

      radioKm = 1.5;
      modoAlerta = AlertaModo.unaSolaVez;
      avisoSonido = AvisoSonido.silencioso;

      avisarOperativos = true;
      avisarAccidentes = true;
      avisarPiquetes = true;
      avisarCallesCortadas = true;

      reportes.clear();

      lastReportTs = 0;
      lastReportTipoTs = {};
      rateWindow = [];
    });

    snack('🧹 Todo borrado');
  }

  // ================== BACKUP / RESTORE (BONUS) ==================
  Future<Map<String, dynamic>> _exportBackupJson() async {
    // asegura que lo que exportamos esté guardado (mejor esfuerzo)
    await _saveState();

    // state
    final prefs = await SharedPreferences.getInstance();
    final st = prefs.getString(K_STATE);
    final ac = prefs.getString(K_ACCESS);

    return {
      'app': 'resistencia_operativos',
      'exportedAt': DateTime.now().toIso8601String(),
      'K_STATE': st,
      'K_ACCESS': ac,
    };
  }

  Future<void> exportarBackupCompartir() async {
    try {
      final backup = await _exportBackupJson();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/backup_resistencia.json');
      await file.writeAsString(jsonEncode(backup), flush: true);
      await Share.shareXFiles([XFile(file.path)],
          text: 'Backup Resistencia (JSON)');
    } catch (e) {
      snack('Error exportando backup: $e');
    }
  }

  Future<void> importarBackupPegado() async {
    String tmp = '';
    final res = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Importar backup (pegado)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Pegá el JSON del backup.\n'
              'Se restauran: estado + access.\n'
              'Tip: hacelo con la app detenida.',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            TextField(
              maxLines: 10,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '{ "app": "...", "K_STATE": "...", ... }',
              ),
              onChanged: (v) => tmp = v,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, tmp),
              child: const Text('IMPORTAR')),
        ],
      ),
    );

    if (res == null) return;

    try {
      final decoded = jsonDecode(res) as Map<String, dynamic>;
      if ((decoded['app'] as String?) != 'resistencia_operativos') {
        snack('⛔ No parece un backup válido.');
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final st = decoded['K_STATE'] as String?;
      final ac = decoded['K_ACCESS'] as String?;

      if (st != null) await prefs.setString(K_STATE, st);
      if (ac != null) await prefs.setString(K_ACCESS, ac);

      // recarga state a memoria
      await _loadState();
      snack('✅ Backup importado');
    } catch (e) {
      snack('Error importando backup: $e');
    }
  }

  @override
  void dispose() {
    sub?.cancel();
    _reportesSub?.cancel();
    _timerLimpieza?.cancel();
    _gpsWatchdog?.cancel();
    _saveDebounce?.cancel();
    super.dispose();
  }

  // ================== NAV ==================
  Future<void> abrirConfiguracion() async {
    final res = await Navigator.push<_SettingsResult>(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          isAdmin: widget.isAdmin,
          myPhone: widget.myPhone,
          radioKm: radioKm,
          modoAlerta: modoAlerta,
          avisoSonido: avisoSonido,
          avisarOperativos: avisarOperativos,
          avisarAccidentes: avisarAccidentes,
          avisarPiquetes: avisarPiquetes,
          avisarCallesCortadas: avisarCallesCortadas,
        ),
      ),
    );

    if (res == null) return;

    setState(() {
      radioKm = res.radioKm;
      modoAlerta = res.modoAlerta;
      avisoSonido = res.avisoSonido;
      avisarOperativos = res.avisarOperativos;
      avisarAccidentes = res.avisarAccidentes;
      avisarPiquetes = res.avisarPiquetes;
      avisarCallesCortadas = res.avisarCallesCortadas;
    });

    snack('✅ Configuración guardada');
    _scheduleSave();
  }

  void abrirMapa() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MapScreen(
          markers: _markers(),
          puntos: puntos,
          reputacion: reputacion,
          radioKm: radioKm,
        ),
      ),
    );
  }

  void abrirHistorial() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HistorialScreen(
          reportes: reportes,
          lastLat: lastLat,
          lastLng: lastLng,
        ),
      ),
    );
  }

  void abrirAyuda() {
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const HelpScreen()));
  }

  void abrirGpsDebug() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GpsDebugScreen(
          tracking: tracking,
          estadoGps: estadoGps,
          lastLat: lastLat,
          lastLng: lastLng,
          lastFixAt: lastFixAt,
          antiSpam: _antiSpamDebug(),
        ),
      ),
    );
  }

  void abrirBiblia() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BibliaScreen(
          texto: generarBibliaTexto(
            radioKm: radioKm,
            modoAlerta: modoAlerta,
            avisoSonido: avisoSonido,
            avisarOperativos: avisarOperativos,
            avisarAccidentes: avisarAccidentes,
            avisarPiquetes: avisarPiquetes,
            avisarCallesCortadas: avisarCallesCortadas,
          ),
        ),
      ),
    );
  }

  String _antiSpamDebug() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rate = rateWindow.where((t) => now - t <= RL_WINDOW_MS).length;
    final lastOp = lastReportTipoTs[ReporteTipo.operativo.name] ?? 0;
    final lastOt = lastReportTipoTs[ReporteTipo.accidente.name] ?? 0;
    return [
      'rateWindow: $rate / $RL_MAX_REPORTES en ${(RL_WINDOW_MS / 1000).round()}s',
      'last operativo: ${lastOp == 0 ? '-' : ((now - lastOp) / 1000).floor()}s ago',
      'last otros: ${lastOt == 0 ? '-' : ((now - lastOt) / 1000).floor()}s ago',
      'dup: ${DUP_METROS.round()}m / ${(DUP_WINDOW_MS / 1000).round()}s',
      'cooldown op: ${(CD_OPERATIVO_MS / 1000).round()}s | otros: ${(CD_OTROS_MS / 1000).round()}s',
    ].join('\n');
  }

  // ================== UI ==================
  @override
  Widget build(BuildContext context) {
    final myDigits = _onlyDigits(widget.myPhone);

    Color tabColor(int i) {
      switch (i) {
        case 0:
          return Colors.blue.shade700;
        case 1:
          return Colors.teal.shade700;
        case 2:
          return Colors.red.shade700;
        case 3:
          return Colors.indigo.shade700;
        default:
          return Colors.grey.shade800;
      }
    }

    String tabTitle(int i) {
      switch (i) {
        case 0:
          return 'Inicio';
        case 1:
          return 'Mapa';
        case 2:
          return 'Auxilio';
        case 3:
          return 'Reportar';
        case 4:
          return 'Cuenta';
        default:
          return 'Resistencia';
      }
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _auxilioBadgeStream(myDigits),
      builder: (context, snapBadge) {
        final hasAuxilioActive = (snapBadge.data?.docs.isNotEmpty ?? false);
        final accent = tabColor(_tabIndex);

        return Scaffold(
          backgroundColor: const Color(0xFFF5F7FB),
          appBar: AppBar(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            elevation: 0,
            titleSpacing: 16,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Resistencia',
                  style: TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
                Text(
                  tabTitle(_tabIndex),
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            actions: [
              if (widget.isAdmin)
                IconButton(
                  onPressed: abrirHistorial,
                  icon: const Icon(Icons.history_rounded),
                  tooltip: 'Historial',
                ),
              if (widget.isAdmin)
                IconButton(
                  onPressed: abrirConfiguracion,
                  icon: const Icon(Icons.settings_rounded),
                  tooltip: 'Configuración',
                ),
              IconButton(
                onPressed: abrirAyuda,
                icon: const Icon(Icons.help_outline_rounded),
                tooltip: 'Ayuda',
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: IndexedStack(
            index: _tabIndex,
            children: [
              _homeBody(),
              _buildMapaTab(),
              _buildAuxilioTab(),
              _buildReportarTab(),
              _buildCuentaTab(),
            ],
          ),
          floatingActionButton: (_tabIndex == 1)
              ? FloatingActionButton.extended(
                  backgroundColor: Colors.red.shade700,
                  icon: const Icon(Icons.sos_rounded, color: Colors.white),
                  label: const Text(
                    'AUXILIO',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  onPressed: () {
                    setState(() => _tabIndex = 2);
                  },
                )
              : null,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tabIndex,
            onDestinationSelected: (i) => setState(() => _tabIndex = i),
            backgroundColor: Colors.white,
            indicatorColor: accent.withOpacity(.14),
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Inicio',
              ),
              const NavigationDestination(
                icon: Icon(Icons.map_outlined),
                selectedIcon: Icon(Icons.map_rounded),
                label: 'Mapa',
              ),
              NavigationDestination(
                label: 'Auxilio',
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.volunteer_activism_outlined),
                    if (hasAuxilioActive)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
                selectedIcon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.volunteer_activism_rounded),
                    if (hasAuxilioActive)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const NavigationDestination(
                icon: Icon(Icons.add_alert_outlined),
                selectedIcon: Icon(Icons.add_alert_rounded),
                label: 'Reportar',
              ),
              const NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: 'Cuenta',
              ),
            ],
          ),
        );
      },
    );
  }

  int _alertasCercaCount() {
    if (lastLat == null || lastLng == null) return 0;
    final radioMetros = radioKm * 1000.0;
    int c = 0;
    for (final r in reportes) {
      if (!r.activo || !r.esGps || !_tipoHabilitado(r.tipo)) continue;
      final d = _distanciaMetrosA(r);
      if (d != null && d <= radioMetros) c++;
    }
    return c;
  }

  String _alertaCercanaTexto() {
    if (lastLat == null || lastLng == null) return 'Activá el servicio para detectar avisos cercanos.';
    final radioMetros = radioKm * 1000.0;
    Reporte? mejor;
    double? mejorDist;
    for (final r in reportes) {
      if (!r.activo || !r.esGps || !_tipoHabilitado(r.tipo)) continue;
      final d = _distanciaMetrosA(r);
      if (d != null && d <= radioMetros) {
        if (mejorDist == null || d < mejorDist) {
          mejorDist = d;
          mejor = r;
        }
      }
    }
    if (mejor == null || mejorDist == null) return 'No tenés alertas activas dentro de tu radio.';
    final dist = mejorDist < 1000 ? '${mejorDist.round()} m' : '${(mejorDist / 1000).toStringAsFixed(1)} km';
    return 'Más cercano: ${tipoTexto(mejor.tipo)} • $dist';
  }

  String _resumenActivosPorTipo() {
    final activos = reportes.where((r) => r.activo).toList();
    if (activos.isEmpty) return 'Sin avisos activos por ahora.';
    final ops = activos.where((r) => r.tipo == ReporteTipo.operativo).length;
    final acc = activos.where((r) => r.tipo == ReporteTipo.accidente).length;
    final piq = activos.where((r) => r.tipo == ReporteTipo.piquete).length;
    final cc = activos.where((r) => r.tipo == ReporteTipo.calleCortada).length;
    return 'Operativos: $ops • Accidentes: $acc • Manifestaciones: $piq • Calles cortadas: $cc';
  }

Widget _homeBody() {
    final alerts = _alertasCercaCount();
    final activeText = tracking ? 'Servicio activo' : 'Servicio detenido';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              colors: tracking
                  ? [Colors.green.shade700, Colors.green.shade500]
                  : [Colors.grey.shade900, Colors.grey.shade700],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Resistencia',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  activeText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'GPS: $estadoGps',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Estado general: $estadoServicio',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (lastFixAt != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Último fix: ${hhmm(lastFixAt!)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _homeStatCard(
                icon: Icons.notifications_active_rounded,
                title: 'Alertas cerca',
                value: '$alerts',
                subtitle: alerts > 0 ? 'Dentro de tu radio' : 'Sin alertas cercanas',
                accent: alerts > 0 ? Colors.orange : Colors.blueGrey,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _homeStatCard(
                icon: Icons.stars_rounded,
                title: 'Tus puntos',
                value: '$puntos',
                subtitle: 'Reputación $reputacion/100',
                accent: Colors.blue,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Resumen operativo',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
                const SizedBox(height: 10),
                _infoLine(Icons.radar_rounded, 'Radio actual', '${radioKm.toStringAsFixed(1)} km'),
                const SizedBox(height: 8),
                _infoLine(Icons.warning_amber_rounded, 'Alertas', _alertaCercanaTexto()),
                const SizedBox(height: 8),
                _infoLine(Icons.list_alt_rounded, 'Reportes activos', _resumenActivosPorTipo()),
                const SizedBox(height: 8),
                _infoLine(Icons.verified_user_rounded, 'Validación', 'Máximo ${VALIDACION_MAX_METROS.round()} m'),
                const SizedBox(height: 8),
                _infoLine(Icons.shield_rounded, 'Protección', 'Cooldown + rate-limit + anti-duplicado'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 56,
          child: ElevatedButton.icon(
            onPressed: tracking ? detener : iniciar,
            icon: Icon(tracking ? Icons.stop_circle_outlined : Icons.play_arrow_rounded),
            style: ElevatedButton.styleFrom(
              backgroundColor: tracking ? Colors.red : Colors.green,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            label: Text(
              tracking ? 'DETENER SERVICIO' : 'INICIAR SERVICIO',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 54,
          child: ElevatedButton.icon(
            onPressed: reportarDialogo,
            icon: const Icon(Icons.add_location_alt_rounded),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            label: const Text(
              'REPORTAR',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 54,
          child: OutlinedButton.icon(
            onPressed: () => setState(() => _tabIndex = 2),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red.shade700,
              side: BorderSide(color: Colors.red.shade200, width: 1.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            icon: const Icon(Icons.sos_rounded),
            label: const Text(
              'IR A AUXILIO',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
            ),
          ),
        ),
        const SizedBox(height: 18),
        if (reportes.where((r) => r.estado != ReporteEstado.expirado).isNotEmpty) ...[
          const Text('Últimos avisos', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 8),
          ...reportes.where((r) => r.estado != ReporteEstado.expirado).take(5).map(_reporteTile),
        ],
      ],
    );
  }




  Widget _cuentaChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.blueGrey.shade100),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.blueGrey.shade800,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
  Widget _homeStatCard({
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 26),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoLine(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade700),
        const SizedBox(width: 10),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(color: Colors.black87),
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                TextSpan(
                  text: value,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _badgeEstado(Reporte r) {
    String txt = '';
    Color bg = Colors.grey.shade300;

    switch (r.estado) {
      case ReporteEstado.pendiente:
        txt = 'PENDIENTE ${r.validaciones}/3';
        bg = Colors.amber.shade200;
        break;
      case ReporteEstado.validado:
        txt = 'VALIDADO';
        bg = Colors.green.shade200;
        break;
      case ReporteEstado.falso:
        txt = 'FALSO';
        bg = Colors.red.shade200;
        break;
      case ReporteEstado.expirado:
        txt = 'EXPIRADO';
        bg = Colors.grey.shade300;
        break;
      case ReporteEstado.cerrado:
        txt = 'CERRADO';
        bg = Colors.blueGrey.shade200;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
      child: Text(txt, style: const TextStyle(fontWeight: FontWeight.w900)),
    );
  }

  Widget _reporteTile(Reporte r) {
    final vence = hhmm(r.venceEn);
    final gpsTxt = r.esGps ? 'GPS ✔' : 'A distancia';
    final dist = _distanciaMetrosA(r);
    final distTxt = (dist != null) ? ' | Dist: ${dist.round()}m' : '';
    final subt = '$gpsTxt | Vence: $vence$distTxt';

    return Card(
      child: ListTile(
        leading: Icon(iconPorTipo(r.tipo), color: colorPorTipo(r.tipo)),
        title: Text(r.tituloCorto,
            style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(
          (r.tipo == ReporteTipo.operativo && r.esGps)
              ? '$subt | Validaciones: ${r.validaciones}/3'
              : subt,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _badgeEstado(r),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (r.tipo == ReporteTipo.operativo &&
                    r.esGps &&
                    r.estado == ReporteEstado.pendiente)
                  IconButton(
                    icon: const Icon(Icons.check_circle),
                    onPressed: () => validar(r),
                    tooltip: 'Validar (≤${VALIDACION_MAX_METROS.round()}m)',
                  ),
                if (r.tipo == ReporteTipo.operativo &&
                    r.estado != ReporteEstado.falso &&
                    r.estado != ReporteEstado.expirado &&
                    r.estado != ReporteEstado.cerrado)
                  IconButton(
                    icon: const Icon(Icons.done_all),
                    onPressed: () => cerrarOperativo(r),
                    tooltip: 'Ya no hay (cierra)',
                  ),
                if (r.estado != ReporteEstado.falso &&
                    r.estado != ReporteEstado.expirado &&
                    r.estado != ReporteEstado.cerrado)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => marcarFalso(r),
                    tooltip: 'Marcar falso',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ======================================================================
// >>>>>>>>>>>> SEPARABLE: settings_screen.dart (desde acá) <<<<<<<<<<<<<<
// ======================================================================
// SETTINGS
// ======================================================================

class _SettingsResult {
  final double radioKm;
  final AlertaModo modoAlerta;
  final AvisoSonido avisoSonido;

  final bool avisarOperativos;
  final bool avisarAccidentes;
  final bool avisarPiquetes;
  final bool avisarCallesCortadas;

  _SettingsResult({
    required this.radioKm,
    required this.modoAlerta,
    required this.avisoSonido,
    required this.avisarOperativos,
    required this.avisarAccidentes,
    required this.avisarPiquetes,
    required this.avisarCallesCortadas,
  });
}

class SettingsScreen extends StatefulWidget {
  final bool isAdmin;
  final String myPhone;
  final double radioKm;
  final AlertaModo modoAlerta;
  final AvisoSonido avisoSonido;

  final bool avisarOperativos;
  final bool avisarAccidentes;
  final bool avisarPiquetes;
  final bool avisarCallesCortadas;

  const SettingsScreen({
    super.key,
    required this.isAdmin,
    required this.myPhone,
    required this.radioKm,
    required this.modoAlerta,
    required this.avisoSonido,
    required this.avisarOperativos,
    required this.avisarAccidentes,
    required this.avisarPiquetes,
    required this.avisarCallesCortadas,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late double radioKm;
  late AlertaModo modoAlerta;
  late AvisoSonido avisoSonido;

  late bool avisarOperativos;
  late bool avisarAccidentes;
  late bool avisarPiquetes;
  late bool avisarCallesCortadas;

  @override
  void initState() {
    super.initState();
    radioKm = widget.radioKm;
    modoAlerta = widget.modoAlerta;
    avisoSonido = widget.avisoSonido;

    avisarOperativos = widget.avisarOperativos;
    avisarAccidentes = widget.avisarAccidentes;
    avisarPiquetes = widget.avisarPiquetes;
    avisarCallesCortadas = widget.avisarCallesCortadas;
  }

  Future<void> _probarAviso() async {
    final channelId = (avisoSonido == AvisoSonido.silencioso)
        ? CH_SILENCIO
        : (avisoSonido == AvisoSonido.vibracion)
            ? CH_VIBRA
            : CH_ALARMA;

    final androidDetails = AndroidNotificationDetails(
      channelId,
      (avisoSonido == AvisoSonido.silencioso)
          ? 'Avisos de Proximidad (Silencioso)'
          : 'Avisos de Proximidad (Alarma)',
      channelDescription: 'Aviso de prueba',
      importance: (avisoSonido == AvisoSonido.silencioso)
          ? Importance.high
          : Importance.max,
      priority: (avisoSonido == AvisoSonido.silencioso)
          ? Priority.high
          : Priority.max,
      playSound: avisoSonido == AvisoSonido.alarma,
      enableVibration: avisoSonido == AvisoSonido.alarma,
      silent: avisoSonido == AvisoSonido.silencioso,
    );

    await _noti.show(
      9999,
      '✅ Prueba de aviso',
      (avisoSonido == AvisoSonido.silencioso)
          ? 'Esto NO debe sonar ni vibrar.'
          : 'Esto DEBERÍA sonar y vibrar.',
      NotificationDetails(android: androidDetails),
    );
  }

  Widget _switchRow(String t, bool v, void Function(bool) onChanged) {
    return SwitchListTile(
      value: v,
      onChanged: onChanged,
      title: Text(t, style: const TextStyle(fontWeight: FontWeight.w800)),
      dense: true,
    );
  }

  void _guardar() {
    Navigator.pop(
      context,
      _SettingsResult(
        radioKm: radioKm,
        modoAlerta: modoAlerta,
        avisoSonido: avisoSonido,
        avisarOperativos: avisarOperativos,
        avisarAccidentes: avisarAccidentes,
        avisarPiquetes: avisarPiquetes,
        avisarCallesCortadas: avisarCallesCortadas,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final radioMetros = (radioKm * 1000).round();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración'),
        actions: [
          TextButton(
            onPressed: _guardar,
            child: const Text('GUARDAR',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.isAdmin)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('🛡️ Admin',
                        style: TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    const Text('Administradores + whitelist',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final prefs = await SharedPreferences.getInstance();
                          final raw = prefs.getString(K_ACCESS);
                          final data = raw == null
                              ? <String, dynamic>{}
                              : (jsonDecode(raw) as Map<String, dynamic>);
                          final wl = (data['whitelist'] as List<dynamic>? ?? [])
                              .map((e) => e.toString())
                              .toList();
                          final ad = (data['admins'] as List<dynamic>? ?? [])
                              .map((e) => e.toString())
                              .toList();

                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AdminPanelScreen(
                                initialWhitelist: wl,
                                initialAdmins: ad,
                                myPhone: _onlyDigits(widget.myPhone),
                                onSave: (newWhitelist, newAdmins) async {
                                  await prefs.setString(
                                    K_ACCESS,
                                    jsonEncode({
                                      'whitelist': newWhitelist,
                                      'admins': newAdmins,
                                      'phone': _onlyDigits(widget.myPhone),
                                      'allowed': true,
                                    }),
                                  );
                                },
                                onResetAccess: () async {
                                  await prefs.remove(K_ACCESS);
                                },
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.admin_panel_settings),
                        label: const Text('ABRIR PANEL ADMIN (WHITELIST)'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (widget.isAdmin) const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('📍 Proximidad',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Text(
                      'Radio: ${radioKm.toStringAsFixed(1)} km ($radioMetros m)',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  Slider(
                    value: radioKm,
                    min: 1,
                    max: 10,
                    divisions: 18,
                    label: '${radioKm.toStringAsFixed(1)} km',
                    onChanged: (v) =>
                        setState(() => radioKm = (v * 2).round() / 2),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🔊 Sonido',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  RadioListTile<AvisoSonido>(
                    value: AvisoSonido.silencioso,
                    groupValue: avisoSonido,
                    onChanged: (v) => setState(() => avisoSonido = v!),
                    title: const Text('Silencioso (solo visual)'),
                    dense: true,
                  ),
                  RadioListTile<AvisoSonido>(
                    value: AvisoSonido.alarma,
                    groupValue: avisoSonido,
                    onChanged: (v) => setState(() => avisoSonido = v!),
                    title: const Text('Con alarma (sonido + vibración)'),
                    dense: true,
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                      onPressed: _probarAviso,
                      child: const Text('PROBAR AVISO')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('⏱ Frecuencia',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  RadioListTile<AlertaModo>(
                    value: AlertaModo.unaSolaVez,
                    groupValue: modoAlerta,
                    onChanged: (v) => setState(() => modoAlerta = v!),
                    title: const Text('Avisar solo una vez (por reporte)'),
                    dense: true,
                  ),
                  RadioListTile<AlertaModo>(
                    value: AlertaModo.repetirCada30s,
                    groupValue: modoAlerta,
                    onChanged: (v) => setState(() => modoAlerta = v!),
                    title: const Text('Avisar cada 30s dentro del radio'),
                    dense: true,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🎯 Tipos que disparan proximidad',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  _switchRow('Operativos', avisarOperativos,
                      (v) => setState(() => avisarOperativos = v)),
                  _switchRow('Accidentes', avisarAccidentes,
                      (v) => setState(() => avisarAccidentes = v)),
                  _switchRow('Piquetes/Manifestaciones', avisarPiquetes,
                      (v) => setState(() => avisarPiquetes = v)),
                  _switchRow('Calles cortadas', avisarCallesCortadas,
                      (v) => setState(() => avisarCallesCortadas = v)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton(
              onPressed: _guardar, child: const Text('GUARDAR Y VOLVER')),
        ],
      ),
    );
  }
}

// ======================================================================
// >>>>>>>>>>>> SEPARABLE: map_screen.dart (desde acá) <<<<<<<<<<<<<<<<<<<
// ======================================================================
// MAP
// ======================================================================

class MapScreen extends StatelessWidget {
  final List<Marker> markers;
  final int puntos;
  final int reputacion;
  final double radioKm;

  const MapScreen({
    super.key,
    required this.markers,
    required this.puntos,
    required this.reputacion,
    required this.radioKm,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mapa')),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: const LatLng(-31.3929, -58.0209),
                initialZoom: 14,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                  userAgentPackageName: 'com.example.resistencia_operativos',
                ),
                MarkerLayer(markers: markers),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Puntos: $puntos | Reputación: $reputacion | Pins: ${markers.length} | Radio: ${radioKm.toStringAsFixed(1)} km',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

// ======================================================================
// >>>>>>>>>>>> SEPARABLE: historial_screen.dart (desde acá) <<<<<<<<<<<<
// ======================================================================
// HISTORIAL
// ======================================================================

class HistorialScreen extends StatelessWidget {
  final List<Reporte> reportes;
  final double? lastLat;
  final double? lastLng;

  const HistorialScreen({
    super.key,
    required this.reportes,
    required this.lastLat,
    required this.lastLng,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historial')),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: reportes.length,
        itemBuilder: (_, i) {
          final r = reportes[i];
          return Card(
            child: ListTile(
              leading: Icon(iconPorTipo(r.tipo)),
              title: Text(r.tituloCorto,
                  style: const TextStyle(fontWeight: FontWeight.w900)),
              subtitle: Text(
                  '${tipoTexto(r.tipo)} | ${hhmm(r.fecha)} | ${r.esGps ? 'GPS' : 'A distancia'} | ${estadoTexto(r.estado)}'),
            ),
          );
        },
      ),
    );
  }
}

// ======================================================================
// >>>>>>>>>>>> SEPARABLE: help_screen.dart (desde acá) <<<<<<<<<<<<<<<<<<
// ======================================================================
// AYUDA
// ======================================================================

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  Widget _card(String title, String body, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 16)),
                  const SizedBox(height: 6),
                  Text(body,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ayuda / Información')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card(
              '🔒 Acceso privado',
              'La app funciona por invitación. Un Admin agrega tu número a la whitelist.',
              Icons.lock),
          _card(
              '🛡 Anti-spam',
              'La app limita reportes por tiempo, aplica cooldown por tipo y bloquea duplicados cercanos.',
              Icons.shield),
          _card(
              '📍 Proximidad',
              'Con servicio ACTIVO, avisa dentro del radio configurado.',
              Icons.radar),
          _card(
              '👥 Validación',
              'Para validar un operativo GPS tenés que estar cerca (≤300m). Se valida con 3 confirmaciones.',
              Icons.groups),
          _card(
              '✅ Ya no hay',
              'Marca el operativo como cerrado (no es "falso").',
              Icons.done_all),
          _card(
              '📄 Biblia',
              'Incluye reglas y configuración, se puede copiar o compartir como TXT.',
              Icons.description),
          _card(
              '❌ Marcar falso',
              'Instantáneo. El reporte deja de contar como activo.',
              Icons.close),
          _card(
              '💾 Backup',
              'Podés exportar/importar backup JSON desde el Home.',
              Icons.backup),
        ],
      ),
    );
  }
}

// ======================================================================
// >>>>>>>>>>>> SEPARABLE: gps_debug_screen.dart (desde acá) <<<<<<<<<<<<
// ======================================================================
// GPS DEBUG
// ======================================================================

class GpsDebugScreen extends StatefulWidget {
  final bool tracking;
  final String estadoGps;
  final double? lastLat;
  final double? lastLng;
  final DateTime? lastFixAt;
  final String antiSpam;

  const GpsDebugScreen({
    super.key,
    required this.tracking,
    required this.estadoGps,
    required this.lastLat,
    required this.lastLng,
    required this.lastFixAt,
    required this.antiSpam,
  });

  @override
  State<GpsDebugScreen> createState() => _GpsDebugScreenState();
}

class _GpsDebugScreenState extends State<GpsDebugScreen> {
  String info = 'Cargando...';

  Future<void> _refresh() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      final perm = await Geolocator.checkPermission();
      final acc = await Geolocator.getLocationAccuracy();
      final notif = await Permission.notification.status;
      final pos = await Geolocator.getLastKnownPosition();

      setState(() {
        info = [
          'tracking: ${widget.tracking}',
          'estadoGps: ${widget.estadoGps}',
          'serviceEnabled: $serviceEnabled',
          'permission: $perm',
          'accuracySetting: $acc',
          'notifPermission: $notif',
          'lastLat/Lng: ${widget.lastLat}, ${widget.lastLng}',
          'lastFixAt: ${widget.lastFixAt}',
          'lastKnownPosition: ${pos?.latitude}, ${pos?.longitude} (ts: ${pos?.timestamp})',
          '',
          'ANTI-SPAM:',
          widget.antiSpam,
        ].join('\n');
      });
    } catch (e) {
      setState(() => info = 'Error: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GPS DEBUG'),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SelectableText(info,
            style: const TextStyle(fontFamily: 'monospace')),
      ),
    );
  }
}

// ======================================================================
// >>>>>>>>>>>> SEPARABLE: biblia_screen.dart (desde acá) <<<<<<<<<<<<<<<
// ======================================================================
// B) BIBLIA (texto + copiar + compartir)
// ======================================================================

String generarBibliaTexto({
  required double radioKm,
  required AlertaModo modoAlerta,
  required AvisoSonido avisoSonido,
  required bool avisarOperativos,
  required bool avisarAccidentes,
  required bool avisarPiquetes,
  required bool avisarCallesCortadas,
}) {
  final sb = StringBuffer();

  sb.writeln(
      '================ RESISTENCIA OPERATIVOS — BIBLIA ================');
  sb.writeln('Versión: MVP privada');
  sb.writeln('');
  sb.writeln('1) OBJETIVO');
  sb.writeln(
      '- App comunitaria para reportar operativos/avisos y alertar por proximidad.');
  sb.writeln('- Modelo cerrado (solo por invitación / whitelist).');
  sb.writeln('');
  sb.writeln('2) ACCESO PRIVADO (Whitelist)');
  sb.writeln('- Para entrar, el usuario ingresa su número.');
  sb.writeln('- Si está en la whitelist, la app habilita el acceso.');
  sb.writeln('- Admin gestiona whitelist con PIN.');
  sb.writeln('');
  sb.writeln('3) HOME');
  sb.writeln('- Muestra estado Servicio (Activo/Detenido) y estado GPS.');
  sb.writeln('- Botón INICIAR/DETENER: activa el monitoreo en segundo plano.');
  sb.writeln('- Botón REPORTAR: crea un reporte.');
  sb.writeln('');
  sb.writeln('4) TIPOS DE REPORTE Y DURACIÓN');
  sb.writeln('- Operativo: 60 min');
  sb.writeln('- Accidente: 30 min');
  sb.writeln('- Piquete/Manifestación: 30 min');
  sb.writeln('- Calle cortada: 12 horas');
  sb.writeln('');
  sb.writeln('5) OPERATIVOS GPS Y VALIDACIÓN');
  sb.writeln('- Si el operativo se crea con GPS: queda PENDIENTE.');
  sb.writeln('- Requiere 3 validaciones para pasar a VALIDADO.');
  sb.writeln(
      '- Para VALIDAR: el validador debe estar a <= ${VALIDACION_MAX_METROS.round()}m.');
  sb.writeln(
      '- Cooldown validar: ${(VALIDACION_COOLDOWN_MS / 1000).round()}s por reporte.');
  sb.writeln('');
  sb.writeln('6) PUNTOS');
  sb.writeln(
      '- Operativo GPS validado: +$P_OPERATIVO_VALIDADO_GPS pts (se acredita al validarse).');
  sb.writeln(
      '- Operativo a distancia (sin GPS): +$P_OPERATIVO_VALIDADO_DISTANCIA pts (inmediato).');
  sb.writeln('- Cada validación aportada: +$P_VALIDAR_APORTE pts.');
  sb.writeln('- Accidente: +$P_AVISO_ACCIDENTE pts.');
  sb.writeln('- Piquete: +$P_AVISO_PIQUETE pts.');
  sb.writeln('- Calle cortada: +$P_AVISO_CALLE_CORTADA pts.');
  sb.writeln('- "Ya no hay": +$P_YA_NO_HAY_OPERATIVO pts.');
  sb.writeln('');
  sb.writeln('7) PROXIMIDAD (ALERTAS)');
  sb.writeln('- Radio actual: ${radioKm.toStringAsFixed(1)} km.');
  sb.writeln(
      '- Frecuencia: ${modoAlerta == AlertaModo.unaSolaVez ? "una sola vez por reporte" : "cada 30s dentro del radio"}');
  sb.writeln(
      '- Sonido: ${avisoSonido == AvisoSonido.silencioso ? "silencioso" : "alarma"}');
  sb.writeln('- Disparadores activos: '
          '${avisarOperativos ? "Operativos " : ""}'
          '${avisarAccidentes ? "Accidentes " : ""}'
          '${avisarPiquetes ? "Piquetes " : ""}'
          '${avisarCallesCortadas ? "CallesCortadas " : ""}'
      .trim());
  sb.writeln('');
  sb.writeln('8) ANTI-SPAM');
  sb.writeln(
      '- Rate-limit: max $RL_MAX_REPORTES reportes cada ${(RL_WINDOW_MS / 1000).round()}s.');
  sb.writeln(
      '- Cooldown por tipo: Operativo ${(CD_OPERATIVO_MS / 1000).round()}s | Otros ${(CD_OTROS_MS / 1000).round()}s.');
  sb.writeln(
      '- Anti-duplicado: bloquea mismo tipo si existe otro dentro de ${DUP_METROS.round()}m en ${(DUP_WINDOW_MS / 1000).round()}s.');
  sb.writeln('');
  sb.writeln('9) MARCAR FALSO');
  sb.writeln(
      '- Instantáneo: el reporte pasa a FALSO y deja de considerarse activo.');
  sb.writeln('');
  sb.writeln('10) PERSISTENCIA');
  sb.writeln('- Se guardan puntos, settings y reportes en el teléfono.');
  sb.writeln('- Se guarda whitelist + teléfono.');
  sb.writeln('- Backup export/import JSON desde Home.');
  sb.writeln(
      '==================================================================');

  return sb.toString();
}

class BibliaScreen extends StatelessWidget {
  final String texto;
  const BibliaScreen({super.key, required this.texto});

  Future<void> _copiar(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: texto));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ Biblia copiada')),
    );
  }

  Future<void> _compartir(BuildContext context) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/biblia_resistencia.txt');
      await file.writeAsString(texto, flush: true);
      await Share.shareXFiles([XFile(file.path)],
          text: 'Biblia — Resistencia');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al compartir: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Biblia'),
        actions: [
          IconButton(
              onPressed: () => _copiar(context),
              icon: const Icon(Icons.copy),
              tooltip: 'Copiar'),
          IconButton(
              onPressed: () => _compartir(context),
              icon: const Icon(Icons.share),
              tooltip: 'Compartir TXT'),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              child: SelectableText(
                texto,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ================== AUXILIO: ENUM UI ==================
enum _AuxCardMode { activoCerca, aceptado, miPedido, historial }

// ================== AUXILIO: DETALLE / ACTIVO ==================
class AuxilioDetailScreen extends StatefulWidget {
  final DocumentReference<Map<String, dynamic>> auxRef;
  final String myPhoneDigits;
  final bool isAdmin;
  final Future<Position?> Function() getPos;
  final void Function(String) onToast;

  const AuxilioDetailScreen({
    super.key,
    required this.auxRef,
    required this.myPhoneDigits,
    required this.isAdmin,
    required this.getPos,
    required this.onToast,
  });

  @override
  State<AuxilioDetailScreen> createState() => _AuxilioDetailScreenState();
}

class _AuxilioDetailScreenState extends State<AuxilioDetailScreen> {
  final MapController _map = MapController();
  final TextEditingController _chatCtrl = TextEditingController();

  bool _busy = false;

  @override
  void dispose() {
    _chatCtrl.dispose();
    super.dispose();
  }

  bool _isRequester(Map<String, dynamic> d) =>
      (d['requesterPhone'] ?? '').toString() == widget.myPhoneDigits;

  bool _isHelper(Map<String, dynamic> d) =>
      (d['helperPhone'] ?? '').toString() == widget.myPhoneDigits;

  Future<void> _appendLog(DocumentReference<Map<String, dynamic>> ref, String ev, String msg) async {
    try {
      await ref.update({
        'logs': FieldValue.arrayUnion([
          {
            't': Timestamp.now(),
            'by': widget.myPhoneDigits,
            'ev': ev,
            'msg': msg,
          }
        ])
      });
    } catch (_) {}
  }

  Future<void> _accept(Map<String, dynamic> d) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final pos = await widget.getPos();
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(widget.auxRef);
        final cur = snap.data() ?? {};
        final status = (cur['status'] ?? 'open').toString();
        final helperPhone = (cur['helperPhone'] ?? '').toString();
        if (status != 'open') throw Exception('No está open');
        if (helperPhone.isNotEmpty) throw Exception('Ya fue aceptado');

        tx.update(widget.auxRef, {
          'status': 'accepted',
          'helperPhone': widget.myPhoneDigits,
          'helperLat': pos?.latitude,
          'helperLng': pos?.longitude,
          'acceptedAt': FieldValue.serverTimestamp(),
        });
      });
      await _appendLog(widget.auxRef, 'accept', 'Auxilio aceptado');
      widget.onToast('Aceptado.');
    } catch (_) {
      widget.onToast('No se pudo aceptar (ya lo tomó otro).');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _arrived(Map<String, dynamic> d) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final pos = await widget.getPos();
      final rLat = (d['requesterLat'] as num?)?.toDouble();
      final rLng = (d['requesterLng'] as num?)?.toDouble();

      if (pos == null || rLat == null || rLng == null) {
        widget.onToast('No se pudo validar GPS.');
        return;
      }

      final dist = Geolocator.distanceBetween(pos.latitude, pos.longitude, rLat, rLng);
      if (dist > AUX_LLEGADA_RADIO_M) {
        widget.onToast('Tenés que estar dentro de ${AUX_LLEGADA_RADIO_M.round()} m para marcar LLEGUÉ. (${dist.round()} m)');
        return;
      }

      // Bonus rapidez: si llega dentro de AUX_BONUS_VENTANA_MIN desde acceptedAt
      final acceptedAt = (d['acceptedAt'] is Timestamp) ? (d['acceptedAt'] as Timestamp).toDate() : null;
      final withinBonus = (acceptedAt != null) && DateTime.now().difference(acceptedAt).inMinutes <= AUX_BONUS_VENTANA_MIN;

      await widget.auxRef.update({
        'status': 'arrived',
        'helperLat': pos.latitude,
        'helperLng': pos.longitude,
        'arrivedAt': FieldValue.serverTimestamp(),
        'arrivedDistanceM': dist,
        'arrivedOk': true,
        'arrivedWithinBonus': withinBonus,
      });
      await _appendLog(widget.auxRef, 'arrived', 'Ayudante llegó (${dist.round()} m)');
      widget.onToast('Marcado como LLEGUÉ.');
    } catch (_) {
      widget.onToast('Error al marcar llegada.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish(Map<String, dynamic> d) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final pos = await widget.getPos();

      final arrivedAt = (d['arrivedAt'] is Timestamp) ? (d['arrivedAt'] as Timestamp).toDate() : null;
      if (arrivedAt == null) {
        widget.onToast('Primero marcá LLEGUÉ.');
        return;
      }
      final staySeconds = DateTime.now().difference(arrivedAt).inSeconds;
      if (staySeconds < AUX_PERMANENCIA_MIN_S) {
        final faltan = AUX_PERMANENCIA_MIN_S - staySeconds;
        widget.onToast('Falta permanencia: ${faltan}s (mínimo ${AUX_PERMANENCIA_MIN_S}s).');
        return;
      }

      await widget.auxRef.update({
        'status': 'pending_confirm',
        'helperLat': pos?.latitude,
        'helperLng': pos?.longitude,
        'finishedAt': FieldValue.serverTimestamp(),
        'helperStaySeconds': staySeconds,
      });
      await _appendLog(widget.auxRef, 'finish', 'Ayudante finalizó (perm ${staySeconds}s)');
      widget.onToast('Finalizado. Esperando confirmación.');
    } catch (_) {
      widget.onToast('Error al finalizar.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmResolved(Map<String, dynamic> d) async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final helperPhone = _onlyDigits((d['helperPhone'] ?? '').toString());
      if (helperPhone.isEmpty) {
        widget.onToast('No hay ayudante asignado.');
        return;
      }

      int bonus = 0;
      try {
        final created = d['createdAt'];
        final arrived = d['arrivedAt'];
        if (created is Timestamp && arrived is Timestamp) {
          final diffMin = arrived.toDate().difference(created.toDate()).inMinutes;
          if (diffMin >= 0 && diffMin <= AUX_BONUS_VENTANA_MIN) {
            bonus = AUX_BONUS_RAPIDEZ_PTS;
          }
        }
      } catch (_) {}

      final reward = AUX_COMPLETADO_PTS + bonus;

      await FirebaseFirestore.instance.runTransaction((tx) async {
        final auxSnap = await tx.get(widget.auxRef);
        final cur = auxSnap.data() ?? <String, dynamic>{};
        final status = (cur['status'] ?? '').toString();

        if (status != 'pending_confirm') {
          throw Exception('No está en pending_confirm');
        }

        final alreadyCredited = (cur['credited'] == true);
        if (alreadyCredited) {
          throw Exception('Ya fue acreditado.');
        }

        // IMPORTANTE:
        // Acá NO sumamos puntos al ayudante.
        // Solo dejamos el auxilio resuelto y listo para acreditación ADMIN.
        tx.update(widget.auxRef, {
          'status': 'resolved',
          'requesterConfirmAt': FieldValue.serverTimestamp(),
          'rewardPoints': reward,
          'rewardBonus': bonus,
        });
      });

      await _appendLog(
        widget.auxRef,
        'confirm',
        'Solicitante confirmó. Pendiente de acreditación admin (+$reward, bonus $bonus)',
      );

      widget.onToast('Confirmado. Quedó pendiente de acreditación.');
    } catch (e) {
      widget.onToast('Error al confirmar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel(Map<String, dynamic> d) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final status = (d['status'] ?? 'open').toString();
      final helperPhone = (d['helperPhone'] ?? '').toString();
      final isHelper = _isHelper(d);

      await FirebaseFirestore.instance.runTransaction((tx) async {
        final auxSnap = await tx.get(widget.auxRef);
        final cur = auxSnap.data() ?? <String, dynamic>{};
        final curStatus = (cur['status'] ?? 'open').toString();

        // cancelar
        tx.update(widget.auxRef, {'status': 'cancelled'});

        // Penalización solo si cancela el ayudante y ya había aceptado (injustificado)
        if (isHelper && (curStatus == 'accepted' || curStatus == 'arrived' || curStatus == 'pending_confirm') && helperPhone.isNotEmpty) {
          final hRef = FirebaseFirestore.instance.collection(FS_USERS_COL).doc(helperPhone);
          tx.set(hRef, {
            'phone': helperPhone,
            'points': FieldValue.increment(AUX_CANCELACION_INJUST_PTS),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          tx.update(widget.auxRef, {
            'cancelBy': helperPhone,
            'cancelPenalty': AUX_CANCELACION_INJUST_PTS,
          });
        }
      });

      await _appendLog(widget.auxRef, 'cancel', isHelper ? 'Ayudante canceló (posible penalización)' : 'Solicitante canceló');
      widget.onToast('Cancelado.');
    } catch (_) {
      widget.onToast('Error al cancelar.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: widget.auxRef.snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final data = snap.data!.data() ?? {};
        final status = (data['status'] ?? 'open').toString();

        final requesterPhone = (data['requesterPhone'] ?? '').toString();
        final helperPhone = (data['helperPhone'] ?? '').toString();

        final desc = (data['requesterDesc'] ?? '').toString();
        final needsList = (data['needs'] is List) ? (data['needs'] as List).map((e) => e.toString()).toList() : <String>[];

        final rLat = (data['requesterLat'] as num?)?.toDouble();
        final rLng = (data['requesterLng'] as num?)?.toDouble();
        final hLat = (data['helperLat'] as num?)?.toDouble();
        final hLng = (data['helperLng'] as num?)?.toDouble();

        final isRequester = _isRequester(data);
        final isHelper = _isHelper(data);

        final points = <Marker>[];
        LatLng center = const LatLng(-31.3929, -58.0209);

        if (rLat != null && rLng != null) {
          final p = LatLng(rLat, rLng);
          center = p;
          points.add(Marker(
            point: p,
            width: 44,
            height: 44,
            child: const Icon(Icons.person_pin_circle_rounded, size: 44, color: Colors.red),
          ));
        }

        if (hLat != null && hLng != null) {
          final p = LatLng(hLat, hLng);
          center = p;
          points.add(Marker(
            point: p,
            width: 40,
            height: 40,
            child: const Icon(Icons.directions_run_rounded, size: 40, color: Colors.blue),
          ));
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Auxilio activo'),
          ),
          body: Column(
            children: [
              // ===== 60% mapa =====
              Expanded(
                flex: 6,
                child: FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: 15,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                      subdomains: const ['a', 'b', 'c'],
                      userAgentPackageName: 'com.resistencia.operativos',
                    ),
                    MarkerLayer(markers: points),
                  ],
                ),
              ),

              // ===== 40% panel inferior =====
              Expanded(
                flex: 4,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        blurRadius: 12,
                        offset: const Offset(0, -2),
                        color: Colors.black.withOpacity(0.08),
                      )
                    ],
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _statusLabel(status),
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                              ),
                            ),
                            if (_busy) const SizedBox(width: 8),
                            if (_busy) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('Solicitante: $requesterPhone', style: const TextStyle(color: Colors.black54)),
                        if (helperPhone.isNotEmpty)
                          Text('Ayudante: $helperPhone', style: const TextStyle(color: Colors.black54)),
                        const SizedBox(height: 10),
                        Text(desc.isEmpty ? '(Sin descripción)' : desc,
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                        if (needsList.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: needsList.take(10).map((e) => Chip(label: Text(e))).toList(),
                          ),
                        ],
                        const SizedBox(height: 14),

                        // Botones dinámicos
                        _actionButtons(
                          status: status,
                          isRequester: isRequester,
                          isHelper: isHelper,
                          hasHelper: helperPhone.isNotEmpty,
                          onAccept: () => _accept(data),
                          onArrived: () => _arrived(data),
                          onFinish: () => _finish(data),
                          onConfirm: () => _confirmResolved(data),
                          onCancel: () => _cancel(data),
                        ),
                        _buildChatSection(data, status, isRequester, isHelper),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'open':
        return 'Esperando ayuda';
      case 'accepted':
        return 'Ayudante en camino';
      case 'arrived':
        return 'Ayudante llegó';
      case 'pending_confirm':
        return 'Pendiente confirmación';
      case 'resolved':
        return 'Finalizado';
      case 'cancelled':
        return 'Cancelado';
      case 'expired':
        return 'Expirado';
      case 'disputed':
        return 'En revisión';
      default:
        return s;
    }
  }

  Widget _actionButtons({
    required String status,
    required bool isRequester,
    required bool isHelper,
    required bool hasHelper,
    required VoidCallback onAccept,
    required VoidCallback onArrived,
    required VoidCallback onFinish,
    required VoidCallback onConfirm,
    required VoidCallback onCancel,
  }) {
    // Reglas:
    // - Si está open y no sos requester: podés aceptar.
    // - Si sos helper y está accepted: "Llegué".
    // - Si sos helper y está arrived: "Finalizar" (queda pending_confirm).
    // - Si sos requester y está pending_confirm: "Confirmar".
    // - requester puede cancelar en open/accepted (si aún no resolvió).
    final buttons = <Widget>[];

    if (status == 'open' && !isRequester) {
      buttons.add(Expanded(
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: onAccept,
          icon: const Icon(Icons.handshake_rounded),
          label: const Text('ACEPTAR'),
        ),
      ));
    }

    if (isHelper && status == 'accepted') {
      buttons.add(Expanded(
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: onArrived,
          icon: const Icon(Icons.place_rounded),
          label: const Text('LLEGUÉ'),
        ),
      ));
    }

    if (isHelper && status == 'arrived') {
      buttons.add(Expanded(
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.purple,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: onFinish,
          icon: const Icon(Icons.done_all_rounded),
          label: const Text('FINALIZAR'),
        ),
      ));
    }

    if (isRequester && status == 'pending_confirm') {
      buttons.add(Expanded(
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.purple,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: onConfirm,
          icon: const Icon(Icons.verified_rounded),
          label: const Text('CONFIRMAR'),
        ),
      ));
    }

    if (isRequester && (status == 'open' || status == 'accepted')) {
      buttons.add(const SizedBox(width: 10));
      buttons.add(Expanded(
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: onCancel,
          icon: const Icon(Icons.close_rounded),
          label: const Text('CANCELAR'),
        ),
      ));
    }

    if (buttons.isEmpty) {
      return const Text('Sin acciones disponibles para tu rol/estado.',
          style: TextStyle(color: Colors.black54));
    }

    return Row(children: buttons);
  }
}

// ================== RANKING SCREEN (MVP) ==================
// MVP: muestra tu zona + mes actual y lee un leaderboard precalculado en Firestore.
// Estructura sugerida:
// leaderboards/{zoneKey}_{yyyymm}
//   - zoneKey, monthKey, updatedAt, totalActive, topCount
// leaderboards/{zoneKey}_{yyyymm}/entries/{phone10}
//   - phone10, pointsMonth, rank, updatedAt
class RankingScreen extends StatefulWidget {
  final String myPhone;
  final bool isAdmin;
  const RankingScreen({super.key, required this.myPhone, required this.isAdmin});

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> {
  String _zoneKey = 'AR-ER-CONCORDIA';
  String _monthKey = '';
  bool _loading = true;
  String? _err;

  Map<String, dynamic>? _meta;
  List<Map<String, dynamic>> _entries = [];
  Map<String, dynamic>? _me;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _monthKey = '${now.year}${now.month.toString().padLeft(2, '0')}';
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });

    try {
      // 1) cargar config/app para zoneKeyDefault (MVP)
      final cfg = await FirebaseFirestore.instance
          .collection(FS_CONFIG_COL)
          .doc(FS_CONFIG_DOC)
          .get();

      final m = cfg.data();
      final zk = (m?[CFG_ZONE_KEY_DEFAULT] as String?)?.trim();
      if (zk != null && zk.isNotEmpty) _zoneKey = zk;

      // 2) leer leaderboard del mes
      final boardId = '${_zoneKey}_$_monthKey';
      final boardRef = FirebaseFirestore.instance
          .collection(FS_LEADERBOARDS_COL)
          .doc(boardId);

      final boardSnap = await boardRef.get();
      _meta = boardSnap.data();

      final q = await boardRef
          .collection('entries')
          .orderBy('rank')
          .limit(50)
          .get();

      _entries = q.docs.map((d) {
        final data = d.data();
        return {
          'id': d.id,
          ...data,
        };
      }).toList();

      // 3) mi entrada (si existe)
      final meSnap = await boardRef.collection('entries').doc(widget.myPhone).get();
      _me = meSnap.data();

      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _err = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ranking'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _err != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('No se pudo cargar',
                            style: TextStyle(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 8),
                        Text(_err!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _load,
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Zona: $_zoneKey',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900, fontSize: 16)),
                            const SizedBox(height: 6),
                            Text('Mes: $_monthKey',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 6),
                            Text(
                              'Top 3% por zona (MVP).',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.grey.shade700),
                            ),
                            if (_meta == null) ...[
                              const SizedBox(height: 10),
                              const Text(
                                'Todavía no hay leaderboard generado para este mes.',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Un Admin/Función de backend debe generarlo. (Lo dejamos listo para el paso 1–5).',
                                style: TextStyle(color: Colors.grey.shade700),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_me != null) Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            const Icon(Icons.person),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Tu ranking: #${_me?['rank'] ?? '-'} • Puntos mes: ${_me?['pointsMonth'] ?? '-'}',
                                style: const TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text('Top 50', style: TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 10),
                    ..._entries.map((e) {
                      final r = e['rank'] ?? '-';
                      final pts = e['pointsMonth'] ?? '-';
                      final id = e['phone10'] ?? e['id'];
                      final me = (id == widget.myPhone);
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text('$r'),
                          ),
                          title: Text(
                            me ? 'Vos ($id)' : '$id',
                            style: TextStyle(
                              fontWeight: me ? FontWeight.w900 : FontWeight.w700,
                            ),
                          ),
                          trailing: Text(
                            '$pts pts',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 24),
                  ],
                ),
    );
  }
}
