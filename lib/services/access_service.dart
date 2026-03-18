import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/app_constants.dart';
import '../core/formatters.dart';
import '../models/access_diagnosis.dart';
import '../models/app_access_state.dart';

class AccessService {
  final FirebaseFirestore _fs;
  AccessService([FirebaseFirestore? firestore]) : _fs = firestore ?? FirebaseFirestore.instance;

  Future<AppAccessState> resolveAccess({required User user}) async {
    final phone = normalizeArPhone(user.phoneNumber ?? '');
    if (phone.length != 10) {
      throw Exception('No se pudo leer tu número autenticado desde Firebase.');
    }

    final founder = phone == AppConstants.founderPhone;

    try {
      final cfgSnap = await _fs.collection(AppConstants.fsConfigCol).doc(AppConstants.fsConfigDoc).get();
      final cfg = cfgSnap.data() ?? <String, dynamic>{};
      final freeLimit = (cfg['freeLimit'] as num?)?.toInt() ?? AppConstants.defaultFreeLimit;
      final priceMonthly = (cfg['monthlyPriceArs'] as num?)?.toInt() ?? AppConstants.defaultPriceMonthly;
      final subscriptionDays = (cfg['subscriptionDays'] as num?)?.toInt() ?? AppConstants.defaultSubscriptionDays;
      final payEnabled = (cfg['payEnabled'] as bool?) ?? true;

      if (founder) {
        await _ensureFounderBootstrap(phone);
      }

      final wlDoc = await _fs.collection(AppConstants.fsWhitelistCol).doc(phone).get();
      final adDoc = await _fs.collection(AppConstants.fsAdminsCol).doc(phone).get();
      final wlField = await _fs.collection(AppConstants.fsWhitelistCol).where('phone', isEqualTo: phone).limit(1).get();
      final adField = await _fs.collection(AppConstants.fsAdminsCol).where('phone', isEqualTo: phone).limit(1).get();

      final whitelistByDoc = wlDoc.exists;
      final whitelistByField = wlField.docs.isNotEmpty;
      final adminByDoc = adDoc.exists;
      final adminByField = adField.docs.isNotEmpty;

      final sourceData = founder
          ? <String, dynamic>{'enabled': true, 'suspended': false, 'role': 'founder'}
          : whitelistByDoc
              ? (wlDoc.data() ?? <String, dynamic>{})
              : whitelistByField
                  ? wlField.docs.first.data()
                  : adminByDoc
                      ? (adDoc.data() ?? <String, dynamic>{})
                      : adminByField
                          ? adField.docs.first.data()
                          : <String, dynamic>{};

      final userRef = _fs.collection(AppConstants.fsUsersCol).doc(phone);
      final userSnap = await userRef.get();
      if (!userSnap.exists) {
        await userRef.set({
          'phone': phone,
          'createdAt': FieldValue.serverTimestamp(),
          'lastLoginAt': FieldValue.serverTimestamp(),
          'points': 0,
          'reputation': 0,
          'auxCredits': 0,
          'enabled': true,
          'suspended': false,
          'role': founder ? 'founder' : 'usuario',
        }, SetOptions(merge: true));
      } else {
        await userRef.set({
          'phone': phone,
          'lastLoginAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      final cfgRef = _fs.collection(AppConstants.fsConfigCol).doc(AppConstants.fsConfigDoc);
      final freshUserSnap = await userRef.get();
      if ((freshUserSnap.data()?['userNumber']) == null) {
        await _fs.runTransaction((tx) async {
          final c = await tx.get(cfgRef);
          final current = (c.data()?['nextUserNumber'] as num?)?.toInt() ?? 0;
          final next = current + 1;
          tx.set(cfgRef, {'nextUserNumber': next}, SetOptions(merge: true));
          tx.set(userRef, {'userNumber': next}, SetOptions(merge: true));
        });
      }

      final userData = (await userRef.get()).data() ?? <String, dynamic>{};
      final userNumber = (userData['userNumber'] as num?)?.toInt();
      final paidUntil = userData['paidUntil'];
      final isPaid = paidUntil is Timestamp ? paidUntil.toDate().isAfter(DateTime.now()) : false;

      final enabled = founder ? true : ((sourceData['enabled'] as bool?) ?? (userData['enabled'] as bool?) ?? true);
      final suspended = founder ? false : ((sourceData['suspended'] as bool?) ?? (userData['suspended'] as bool?) ?? false);
      final role = founder
          ? 'founder'
          : ((sourceData['role'] as String?) ?? (userData['role'] as String?) ?? (adminByDoc || adminByField ? 'admin' : 'usuario'));
      final allowedByList = founder || whitelistByDoc || whitelistByField || adminByDoc || adminByField;
      final isAdmin = founder || adminByDoc || adminByField || role == 'admin' || role == 'founder';
      final requiresPayment = payEnabled && !isAdmin && userNumber != null && userNumber > freeLimit && !isPaid;

      var allowed = allowedByList && enabled && !suspended;
      var reason = 'OK';
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
        reason = 'Suscripción requerida';
      }

      return AppAccessState(
        allowed: allowed,
        isAdmin: isAdmin,
        requiresPayment: requiresPayment,
        freeLimit: freeLimit,
        priceMonthly: priceMonthly,
        subscriptionDays: subscriptionDays,
        userNumber: userNumber,
        payAlias: (cfg['payAlias'] as String?) ?? '',
        payCbu: (cfg['payCbu'] as String?) ?? '',
        payHolder: (cfg['payHolder'] as String?) ?? '',
        payNote: (cfg['payNote'] as String?) ?? '',
        phoneDigits10: phone,
        diagnosis: AccessDiagnosis(
          phoneDigits10: phone,
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
        ),
      );
    } catch (e) {
      if (!founder) rethrow;
      return AppAccessState(
        allowed: true,
        isAdmin: true,
        requiresPayment: false,
        freeLimit: AppConstants.defaultFreeLimit,
        priceMonthly: AppConstants.defaultPriceMonthly,
        subscriptionDays: AppConstants.defaultSubscriptionDays,
        userNumber: null,
        payAlias: '',
        payCbu: '',
        payHolder: '',
        payNote: '',
        phoneDigits10: phone,
        diagnosis: AccessDiagnosis(
          phoneDigits10: phone,
          whitelistByDoc: true,
          whitelistByField: false,
          adminByDoc: true,
          adminByField: false,
          enabled: true,
          suspended: false,
          role: 'founder',
          requiresPayment: false,
          isPaid: true,
          userNumber: null,
          reason: 'Fallback fundador por falla remota: $e',
        ),
      );
    }
  }

  Future<void> _ensureFounderBootstrap(String phone) async {
    await _fs.collection(AppConstants.fsWhitelistCol).doc(phone).set({
      'phone': phone,
      'role': 'founder',
      'enabled': true,
      'suspended': false,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _fs.collection(AppConstants.fsAdminsCol).doc(phone).set({
      'phone': phone,
      'role': 'founder',
      'enabled': true,
      'suspended': false,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
