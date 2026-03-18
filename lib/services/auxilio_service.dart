import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/app_constants.dart';
import '../models/auxilio.dart';

class AuxilioService {
  final FirebaseFirestore _fs;
  AuxilioService([FirebaseFirestore? firestore]) : _fs = firestore ?? FirebaseFirestore.instance;

  Stream<List<Auxilio>> watchAuxilios() {
    return _fs.collection(AppConstants.fsAuxiliosCol).orderBy('createdAt', descending: true).limit(100).snapshots().map(
      (snap) => snap.docs.map((d) => Auxilio.fromDoc(d.id, d.data())).toList(),
    );
  }

  Future<void> requestAuxilio({required String phone, required String note}) async {
    await _fs.collection(AppConstants.fsAuxiliosCol).add({
      'requestedBy': phone,
      'acceptedBy': null,
      'status': 'requested',
      'note': note,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> acceptAuxilio({required String id, required String helperPhone}) async {
    await _fs.collection(AppConstants.fsAuxiliosCol).doc(id).set({
      'acceptedBy': helperPhone,
      'status': 'accepted',
    }, SetOptions(merge: true));
  }

  Future<void> completeAuxilio(String id) async {
    await _fs.collection(AppConstants.fsAuxiliosCol).doc(id).set({
      'status': 'completed',
      'completedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
