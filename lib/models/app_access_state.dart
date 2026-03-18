import 'access_diagnosis.dart';

class AppAccessState {
  final bool allowed;
  final bool isAdmin;
  final bool requiresPayment;
  final int freeLimit;
  final int priceMonthly;
  final int subscriptionDays;
  final int? userNumber;
  final String payAlias;
  final String payCbu;
  final String payHolder;
  final String payNote;
  final String phoneDigits10;
  final AccessDiagnosis? diagnosis;

  const AppAccessState({
    required this.allowed,
    required this.isAdmin,
    required this.requiresPayment,
    required this.freeLimit,
    required this.priceMonthly,
    required this.subscriptionDays,
    required this.userNumber,
    required this.payAlias,
    required this.payCbu,
    required this.payHolder,
    required this.payNote,
    required this.phoneDigits10,
    required this.diagnosis,
  });
}
