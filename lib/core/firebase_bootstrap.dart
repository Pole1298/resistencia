import 'package:firebase_core/firebase_core.dart';

class FirebaseBootstrap {
  static Future<void> initSafe() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
    } catch (_) {
      // La pantalla de acceso informa si Firebase no quedó listo.
    }
  }
}
