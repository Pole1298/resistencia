import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  final String phone;
  final int? userNumber;
  final String role;
  final bool enabled;
  final bool suspended;
  final int points;
  final int reputation;
  final int auxCredits;
  final DateTime? paidUntil;

  const AppUser({
    required this.phone,
    required this.userNumber,
    required this.role,
    required this.enabled,
    required this.suspended,
    required this.points,
    required this.reputation,
    required this.auxCredits,
    required this.paidUntil,
  });

  factory AppUser.fromMap(String phone, Map<String, dynamic> data) {
    DateTime? readTs(dynamic v) => v is Timestamp ? v.toDate() : null;
    return AppUser(
      phone: phone,
      userNumber: (data['userNumber'] as num?)?.toInt(),
      role: (data['role'] as String?) ?? 'usuario',
      enabled: (data['enabled'] as bool?) ?? true,
      suspended: (data['suspended'] as bool?) ?? false,
      points: (data['points'] as num?)?.toInt() ?? 0,
      reputation: (data['reputation'] as num?)?.toInt() ?? 0,
      auxCredits: (data['auxCredits'] as num?)?.toInt() ?? 0,
      paidUntil: readTs(data['paidUntil']),
    );
  }
}
