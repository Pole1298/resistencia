class AccessDiagnosis {
  final String phoneDigits10;
  final bool whitelistByDoc;
  final bool whitelistByField;
  final bool adminByDoc;
  final bool adminByField;
  final bool enabled;
  final bool suspended;
  final String role;
  final bool requiresPayment;
  final bool isPaid;
  final int? userNumber;
  final String reason;

  const AccessDiagnosis({
    required this.phoneDigits10,
    required this.whitelistByDoc,
    required this.whitelistByField,
    required this.adminByDoc,
    required this.adminByField,
    required this.enabled,
    required this.suspended,
    required this.role,
    required this.requiresPayment,
    required this.isPaid,
    required this.userNumber,
    required this.reason,
  });
}
