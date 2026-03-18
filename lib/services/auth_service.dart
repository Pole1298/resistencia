import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  AuthService._();
  static final AuthService _instance = AuthService._();
  factory AuthService() => _instance;

  final FirebaseAuth _fa = FirebaseAuth.instance;

  User? get currentUser => _fa.currentUser;

  String _digitsOnly(String input) {
    return input.replaceAll(RegExp(r'\D'), '');
  }

  /// Normaliza números AR a E.164 para Firebase.
  /// Acepta por ejemplo:
  /// 3435064401
  /// 03435064401
  /// 5493435064401
  /// +5493435064401
  String _normalizeArPhone(String raw) {
    String d = _digitsOnly(raw);

    if (d.isEmpty) {
      throw FirebaseAuthException(
        code: 'invalid-phone-number',
        message: 'Número vacío.',
      );
    }

    if (d.startsWith('549') && d.length >= 12) {
      return '+$d';
    }

    if (d.startsWith('54') && d.length >= 11) {
      if (!d.startsWith('549')) {
        d = '549${d.substring(2)}';
      }
      return '+$d';
    }

    if (d.startsWith('0')) {
      d = d.substring(1);
    }

    if (d.length < 10) {
      throw FirebaseAuthException(
        code: 'invalid-phone-number',
        message: 'Número incompleto.',
      );
    }

    return '+549$d';
  }

  String _friendlyError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-phone-number':
        return 'El número no es válido.';
      case 'too-many-requests':
        return 'Demasiados intentos. Esperá unos minutos antes de volver a pedir el código.';
      case 'quota-exceeded':
        return 'Se alcanzó el límite de envíos de SMS por ahora. Intentá más tarde.';
      case 'network-request-failed':
        return 'Falló la conexión de red. Revisá internet e intentá otra vez.';
      case 'captcha-check-failed':
        return 'Falló la validación de seguridad del dispositivo.';
      case 'app-not-authorized':
        return 'La app no está autorizada para usar autenticación por teléfono.';
      case 'invalid-app-credential':
        return 'La credencial de la app es inválida. Revisá Firebase / Play Integrity.';
      case 'missing-client-identifier':
        return 'Falta identificación del cliente para la verificación.';
      case 'session-expired':
        return 'La sesión del código expiró. Pedí uno nuevo.';
      case 'invalid-verification-code':
        return 'El código ingresado es incorrecto.';
      case 'invalid-verification-id':
        return 'La sesión de verificación es inválida. Pedí otro código.';
      default:
        return e.message?.trim().isNotEmpty == true
            ? e.message!.trim()
            : 'Error de autenticación: ${e.code}';
    }
  }

  Future<void> verifyPhoneNumber({
    required String localPhone,
    required void Function(String verificationId) onCodeSent,
    required void Function(String message) onFailed,
    required Future<void> Function(User user) onAutoVerified,
  }) async {
    final String phoneNumber;

    try {
      phoneNumber = _normalizeArPhone(localPhone);
    } on FirebaseAuthException catch (e) {
      onFailed(_friendlyError(e));
      return;
    } catch (_) {
      onFailed('No se pudo interpretar el número de teléfono.');
      return;
    }

    bool finished = false;

    try {
      await _fa.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: const Duration(seconds: 60),

        verificationCompleted: (PhoneAuthCredential credential) async {
          if (finished) return;
          finished = true;

          try {
            final cred = await _fa.signInWithCredential(credential);
            final user = cred.user;
            if (user == null) {
              onFailed('No se pudo completar la validación automática.');
              return;
            }
            await onAutoVerified(user);
          } on FirebaseAuthException catch (e) {
            onFailed(_friendlyError(e));
          } catch (_) {
            onFailed('Falló la validación automática del teléfono.');
          }
        },

        verificationFailed: (FirebaseAuthException e) {
          if (finished) return;
          finished = true;
          onFailed(_friendlyError(e));
        },

        codeSent: (String verificationId, int? resendToken) {
          if (finished) return;
          finished = true;
          onCodeSent(verificationId);
        },

        codeAutoRetrievalTimeout: (String verificationId) {
          // No hacemos nada acá a propósito.
          // La pantalla ya conserva verificationId cuando llega codeSent.
        },
      );
    } on FirebaseAuthException catch (e) {
      onFailed(_friendlyError(e));
    } catch (e) {
      onFailed('Error inesperado al pedir el código: $e');
    }
  }

  Future<User> signInWithCode({
    required String verificationId,
    required String smsCode,
  }) async {
    final code = smsCode.trim();

    if (verificationId.trim().isEmpty) {
      throw FirebaseAuthException(
        code: 'invalid-verification-id',
        message: 'Verification ID vacío.',
      );
    }

    if (code.isEmpty) {
      throw FirebaseAuthException(
        code: 'invalid-verification-code',
        message: 'Código vacío.',
      );
    }

    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: code,
    );

    final result = await _fa.signInWithCredential(credential);
    final user = result.user;

    if (user == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'No se pudo obtener el usuario autenticado.',
      );
    }

    return user;
  }

  Future<void> signOut() async {
    await _fa.signOut();
  }
}