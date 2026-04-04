class ClinicMembership {
  final String id;
  final String userId;
  final String clinicId;
  final String clinicName; // resolved separately
  final String role; // 'admin' or 'secretary'
  final String status; // 'approved' or 'pending'
  final DateTime joinedAt;

  ClinicMembership({
    required this.id,
    required this.userId,
    required this.clinicId,
    this.clinicName = '',
    required this.role,
    required this.status,
    required this.joinedAt,
  });

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';

  factory ClinicMembership.fromMap(Map<String, dynamic> data, String id) {
    return ClinicMembership(
      id: id,
      userId: data['userId'] ?? '',
      clinicId: data['clinicId'] ?? '',
      clinicName: data['clinicName'] ?? '',
      role: data['role'] ?? 'secretary',
      status: data['status'] ?? 'pending',
      joinedAt: data['joinedAt'] != null
          ? (DateTime.tryParse(data['joinedAt'].toString()) ?? DateTime.now())
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'clinicId': clinicId,
      'role': role,
      'status': status,
      'joinedAt': joinedAt,
    };
  }
}
