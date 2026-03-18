import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/app_constants.dart';
import '../core/formatters.dart';

class AdminService {
  final FirebaseFirestore _fs;
  AdminService([FirebaseFirestore? firestore]) : _fs = firestore ?? FirebaseFirestore.instance;

  Future<void> addToWhitelist(String phone, {String role = 'usuario'}) async {
    final p = normalizeArPhone(phone);
    if (p.length != 10) throw Exception('Número inválido');
    await _fs.collection(AppConstants.fsWhitelistCol).doc(p).set({
      'phone': p,
      'role': role,
      'enabled': true,
      'suspended': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _fs.collection(AppConstants.fsUsersCol).doc(p).set({
      'phone': p,
      'enabled': true,
      'suspended': false,
      'role': role,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setAdmin(String phone, {required bool value}) async {
    final p = normalizeArPhone(phone);
    if (p.length != 10) throw Exception('Número inválido');
    if (p == AppConstants.founderPhone && !value) {
      throw Exception('El fundador no puede perder permisos de Super Admin.');
    }

    if (value) {
      await _fs.collection(AppConstants.fsAdminsCol).doc(p).set({
        'phone': p,
        'role': p == AppConstants.founderPhone ? 'founder' : 'admin',
        'enabled': true,
        'suspended': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await _fs.collection(AppConstants.fsUsersCol).doc(p).set({
        'role': p == AppConstants.founderPhone ? 'founder' : 'admin',
        'enabled': true,
        'suspended': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else {
      await _fs.collection(AppConstants.fsAdminsCol).doc(p).delete();
      await _fs.collection(AppConstants.fsUsersCol).doc(p).set({
        'role': 'usuario',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Future<void> setWhitelistEnabled(String phone, bool enabled) async {
    final p = normalizeArPhone(phone);
    if (p == AppConstants.founderPhone && !enabled) {
      throw Exception('El fundador no puede ser deshabilitado.');
    }
    await _fs.collection(AppConstants.fsWhitelistCol).doc(p).set({'enabled': enabled, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    await _fs.collection(AppConstants.fsUsersCol).doc(p).set({'enabled': enabled, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  }

  Future<void> setSuspended(String phone, bool suspended) async {
    final p = normalizeArPhone(phone);
    if (p == AppConstants.founderPhone && suspended) {
      throw Exception('El fundador no puede ser suspendido.');
    }
    await _fs.collection(AppConstants.fsWhitelistCol).doc(p).set({'suspended': suspended, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    await _fs.collection(AppConstants.fsAdminsCol).doc(p).set({'suspended': suspended, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    await _fs.collection(AppConstants.fsUsersCol).doc(p).set({'suspended': suspended, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>> loadConfig() async {
    final snap = await _fs.collection(AppConstants.fsConfigCol).doc(AppConstants.fsConfigDoc).get();
    return snap.data() ?? <String, dynamic>{};
  }

  Future<void> saveConfig({
    required int freeLimit,
    required int monthlyPriceArs,
    required int subscriptionDays,
    required bool payEnabled,
    required String payAlias,
    required String payCbu,
    required String payHolder,
    required String payNote,
  }) async {
    await _fs.collection(AppConstants.fsConfigCol).doc(AppConstants.fsConfigDoc).set({
      'freeLimit': freeLimit,
      'monthlyPriceArs': monthlyPriceArs,
      'subscriptionDays': subscriptionDays,
      'payEnabled': payEnabled,
      'payAlias': payAlias.trim(),
      'payCbu': payCbu.trim(),
      'payHolder': payHolder.trim(),
      'payNote': payNote.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> bootstrapFounder() async {
    final p = AppConstants.founderPhone;
    await _fs.collection(AppConstants.fsWhitelistCol).doc(p).set({
      'phone': p,
      'role': 'founder',
      'enabled': true,
      'suspended': false,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _fs.collection(AppConstants.fsAdminsCol).doc(p).set({
      'phone': p,
      'role': 'founder',
      'enabled': true,
      'suspended': false,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _fs.collection(AppConstants.fsUsersCol).doc(p).set({
      'phone': p,
      'role': 'founder',
      'enabled': true,
      'suspended': false,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
