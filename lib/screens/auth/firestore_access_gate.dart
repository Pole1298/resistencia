import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/app_access_state.dart';
import '../../services/access_service.dart';
import '../../services/auth_service.dart';
import '../../widgets/info_card.dart';
import '../boot/boot_gate_screen.dart';
import 'blocked_screen.dart';
import 'paywall_screen.dart';

class FirestoreAccessGate extends StatefulWidget {
  const FirestoreAccessGate({super.key});

  @override
  State<FirestoreAccessGate> createState() => _FirestoreAccessGateState();
}

class _FirestoreAccessGateState extends State<FirestoreAccessGate> {
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _codeCtrl = TextEditingController();

  final AuthService _auth = AuthService();
  final AccessService _access = AccessService();

  bool _sending = false;
  bool _verifying = false;

  String? _verificationId;
  String? _error;
  AppAccessState? _state;

  int _cooldownSeconds = 0;
  bool _temporarilyLocked = false;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_bootstrap);
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final current = _auth.currentUser;
    if (current != null) {
      await _resolve(current);
    }
  }

  Future<void> _resolve(User user) async {
    try {
      final state = await _access.resolveAccess(user: user);
      if (!mounted) return;
      setState(() => _state = state);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  void _startCooldown(int seconds) {
    _cooldownTimer?.cancel();

    setState(() {
      _cooldownSeconds = seconds;
    });

    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_cooldownSeconds <= 1) {
        timer.cancel();
        setState(() {
          _cooldownSeconds = 0;
        });
      } else {
        setState(() {
          _cooldownSeconds--;
        });
      }
    });
  }

  String _normalizeErrorMessage(String msg) {
    final m = msg.toLowerCase();

    if (m.contains('too-many-requests') ||
        m.contains('too many requests') ||
        m.contains('demasiados intentos') ||
        m.contains('too-many')) {
      _temporarilyLocked = true;
      _startCooldown(120);
      return 'Demasiados intentos. Esperá unos minutos antes de pedir otro código.';
    }

    if (m.contains('invalid-phone-number')) {
      return 'El número no es válido. Revisalo e intentá de nuevo.';
    }

    if (m.contains('network-request-failed')) {
      return 'Falló la conexión. Revisá internet e intentá otra vez.';
    }

    if (m.contains('session-expired')) {
      return 'El código venció. Pedí uno nuevo.';
    }

    if (m.contains('invalid-verification-code')) {
      return 'El código ingresado es incorrecto.';
    }

    if (m.contains('invalid-verification-id')) {
      return 'La sesión de verificación no es válida. Pedí un código nuevo.';
    }

    if (m.contains('quota-exceeded')) {
      _startCooldown(180);
      return 'Se alcanzó el límite de envíos por ahora. Intentá más tarde.';
    }

    return msg;
  }

  Future<void> _sendCode() async {
    if (_sending || _cooldownSeconds > 0) return;

    if (_temporarilyLocked) {
      setState(() {
        _error = 'La verificación está temporalmente bloqueada. Esperá y volvé a intentar.';
      });
      return;
    }

    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) {
      setState(() => _error = 'Ingresá tu número de teléfono.');
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      await _auth.verifyPhoneNumber(
        localPhone: phone,
        onCodeSent: (id) {
          if (!mounted) return;
          setState(() => _verificationId = id);
          _startCooldown(60);
        },
        onFailed: (msg) {
          if (!mounted) return;
          setState(() => _error = _normalizeErrorMessage(msg));
        },
        onAutoVerified: (user) async {
          await _resolve(user);
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _normalizeErrorMessage('$e'));
    } finally {
      if (!mounted) return;
      setState(() => _sending = false);
    }
  }

  Future<void> _verifyCode() async {
    if (_verifying) return;

    if ((_verificationId ?? '').isEmpty) {
      setState(() => _error = 'Primero pedí el código.');
      return;
    }

    final code = _codeCtrl.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Ingresá el código SMS.');
      return;
    }

    setState(() {
      _verifying = true;
      _error = null;
    });

    try {
      final user = await _auth.signInWithCode(
        verificationId: _verificationId!,
        smsCode: code,
      );
      await _resolve(user);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _normalizeErrorMessage('$e'));
    } finally {
      if (!mounted) return;
      setState(() => _verifying = false);
    }
  }

  void _resetVerificationFlow() {
    _cooldownTimer?.cancel();
    setState(() {
      _verificationId = null;
      _error = null;
      _codeCtrl.clear();
      _cooldownSeconds = 0;
      _temporarilyLocked = false;
      _sending = false;
      _verifying = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final current = _auth.currentUser;
    final s = _state;

    if (current != null && s != null && s.allowed && !s.requiresPayment) {
      return BootGateScreen(
        isAdmin: s.isAdmin,
        myPhone: s.phoneDigits10,
      );
    }

    if (current != null && s != null && s.requiresPayment) {
      return PaywallScreen(
        phoneDigits10: s.phoneDigits10,
        freeLimit: s.freeLimit,
        userNumber: s.userNumber,
        monthlyPriceArs: s.priceMonthly,
        subscriptionDays: s.subscriptionDays,
        payAlias: s.payAlias,
        payCbu: s.payCbu,
        payHolder: s.payHolder,
        payNote: s.payNote,
        onRetry: () async {
          final user = _auth.currentUser;
          if (user != null) {
            await _resolve(user);
          }
        },
      );
    }

    if (current != null && s != null && !s.allowed) {
      return BlockedScreen(
        allowed: s.allowed,
        requiresPayment: s.requiresPayment,
        userNumber: s.userNumber,
        freeLimit: s.freeLimit,
        priceMonthly: s.priceMonthly,
        diagnosis: s.diagnosis,
        onRetry: () async {
          final user = _auth.currentUser;
          if (user != null) {
            await _resolve(user);
          }
        },
        onLogout: () async {
          await _auth.signOut();
          if (!mounted) return;
          setState(() {
            _state = null;
            _verificationId = null;
            _error = null;
            _phoneCtrl.clear();
            _codeCtrl.clear();
            _cooldownSeconds = 0;
            _temporarilyLocked = false;
          });
        },
      );
    }

    final waitingCode = (_verificationId ?? '').isNotEmpty;
    final sendDisabled = _sending || _cooldownSeconds > 0 || _temporarilyLocked;
    final verifyDisabled = _verifying;

    return Scaffold(
      appBar: AppBar(title: const Text('Acceso')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0F172A), Color(0xFF1D4ED8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ingreso seguro',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  waitingCode
                      ? 'Ingresá el código SMS para validar tu acceso en Resistencia.'
                      : 'Usá tu número real. La app toma el teléfono autenticado desde Firebase y lo valida con Firestore.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.86),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          InfoCard(
            title: waitingCode ? 'Código de verificación' : 'Número de teléfono',
            subtitle: waitingCode
                ? 'Escribí el código recibido por SMS'
                : 'Ingresá 10 dígitos, sin +54',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!waitingCode) ...[
                  TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    enabled: !_sending && !_verifying,
                    decoration: const InputDecoration(
                      labelText: 'Número',
                      hintText: 'Ej: 3435064401',
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: sendDisabled ? null : _sendCode,
                    icon: const Icon(Icons.sms_rounded),
                    label: Text(
                      _cooldownSeconds > 0
                          ? 'Reenviar en $_cooldownSeconds s'
                          : (_sending ? 'Enviando...' : 'Enviar código'),
                    ),
                  ),
                ] else ...[
                  TextField(
                    controller: _codeCtrl,
                    keyboardType: TextInputType.number,
                    enabled: !_verifying,
                    decoration: const InputDecoration(
                      labelText: 'Código',
                      hintText: 'Ingresá el SMS recibido',
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: verifyDisabled ? null : _verifyCode,
                    icon: const Icon(Icons.verified_user_rounded),
                    label: Text(_verifying ? 'Verificando...' : 'Verificar y entrar'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _resetVerificationFlow,
                    child: const Text('Cambiar número'),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: Color(0xFF991B1B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          const InfoCard(
            title: 'Base de acceso',
            subtitle: 'Pensada para una operación seria',
            child: Text(
              'La app valida número, invitación, rol, estado del usuario y, si corresponde, acceso con pago. El teléfono autenticado se usa como identidad real para evitar errores y valores fijos.',
            ),
          ),
        ],
      ),
    );
  }
}
