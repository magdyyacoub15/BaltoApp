class AppUser {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String clinicId;
  final String role; // 'admin' or 'secretary'
  final bool isApproved;

  AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.clinicId,
    required this.role,
    this.isApproved = false,
  });

  bool get isAdmin => role == 'admin';

  factory AppUser.fromMap(Map<String, dynamic> data, String id) {
    return AppUser(
      id: id,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      phone: data['phone'] ?? '',
      clinicId: data['clinicId'] ?? '',
      role: data['role'] ?? 'secretary',
      isApproved: data['isApproved'] ?? (data['role'] == 'admin'),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'phone': phone,
      'clinicId': clinicId,
      'role': role,
      'isApproved': isApproved,
    };
  }
}
