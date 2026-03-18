import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/reporte.dart';

class ReportesService {
  ReportesService({
    FirebaseFirestore? firestore,
    this.collectionPath = 'reportes',
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final String collectionPath;

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection(collectionPath);

  Stream<List<Reporte>> watchReportes({int limit = 300}) {
    return _col
        .orderBy('fechaMs', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) {
      return snap.docs.map((d) {
        final map = Map<String, dynamic>.from(d.data());
        map['id'] = (map['id'] as String?) ?? d.id;
        return Reporte.fromMap(map);
      }).toList();
    });
  }

  Future<List<Reporte>> fetchReportes({int limit = 300}) async {
    final snap = await _col
        .orderBy('fechaMs', descending: true)
        .limit(limit)
        .get();

    return snap.docs.map((d) {
      final map = Map<String, dynamic>.from(d.data());
      map['id'] = (map['id'] as String?) ?? d.id;
      return Reporte.fromMap(map);
    }).toList();
  }

  Future<void> saveReporte(
    Reporte reporte, {
    String? sourcePhone,
  }) async {
    await _col.doc(reporte.id).set({
      ...reporte.toMap(),
      'id': reporte.id,
      'fechaMs': reporte.fecha.millisecondsSinceEpoch,
      'updatedAt': FieldValue.serverTimestamp(),
      if (sourcePhone != null && sourcePhone.trim().isNotEmpty)
        'sourcePhone': sourcePhone.trim(),
    }, SetOptions(merge: true));
  }

  Future<void> createReporte(
    Reporte reporte, {
    String? sourcePhone,
  }) async {
    await _col.doc(reporte.id).set({
      ...reporte.toMap(),
      'id': reporte.id,
      'fechaMs': reporte.fecha.millisecondsSinceEpoch,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      if (sourcePhone != null && sourcePhone.trim().isNotEmpty)
        'sourcePhone': sourcePhone.trim(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteReporte(String reporteId) async {
    await _col.doc(reporteId).delete();
  }

  Future<Reporte?> getReporte(String reporteId) async {
    final doc = await _col.doc(reporteId).get();
    if (!doc.exists) return null;

    final map = Map<String, dynamic>.from(doc.data() ?? <String, dynamic>{});
    map['id'] = (map['id'] as String?) ?? doc.id;
    return Reporte.fromMap(map);
  }
}