import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/app_constants.dart';
import '../models/app_user.dart';

class UsersService {
  final FirebaseFirestore _fs;
  UsersService([FirebaseFirestore? firestore]) : _fs = firestore ?? FirebaseFirestore.instance;

  Stream<AppUser?> watchUser(String phone) {
    return _fs.collection(AppConstants.fsUsersCol).doc(phone).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return AppUser.fromMap(snap.id, snap.data()!);
    });
  }

  Future<AppUser?> fetchUser(String phone) async {
    final snap = await _fs.collection(AppConstants.fsUsersCol).doc(phone).get();
    if (!snap.exists || snap.data() == null) return null;
    return AppUser.fromMap(snap.id, snap.data()!);
  }
}
