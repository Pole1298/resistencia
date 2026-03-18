import 'package:cloud_firestore/cloud_firestore.dart';

class Auxilio {
  final String id;
  final String requestedBy;
  final String? acceptedBy;
  final String status;
  final String note;
  final DateTime? createdAt;

  const Auxilio({
    required this.id,
    required this.requestedBy,
    required this.acceptedBy,
    required this.status,
    required this.note,
    required this.createdAt,
  });

  factory Auxilio.fromDoc(String id, Map<String, dynamic> data) {
    return Auxilio(
      id: id,
      requestedBy: (data['requestedBy'] as String?) ?? '',
      acceptedBy: data['acceptedBy'] as String?,
      status: (data['status'] as String?) ?? 'requested',
      note: (data['note'] as String?) ?? '',
      createdAt: data['createdAt'] is Timestamp ? (data['createdAt'] as Timestamp).toDate() : null,
    );
  }
}
