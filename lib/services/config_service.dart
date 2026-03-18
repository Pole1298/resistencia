import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/app_constants.dart';

class ConfigService {
  final FirebaseFirestore _fs;
  ConfigService([FirebaseFirestore? firestore]) : _fs = firestore ?? FirebaseFirestore.instance;

  Future<Map<String, dynamic>> load() async {
    final snap = await _fs.collection(AppConstants.fsConfigCol).doc(AppConstants.fsConfigDoc).get();
    return snap.data() ?? <String, dynamic>{};
  }
}
