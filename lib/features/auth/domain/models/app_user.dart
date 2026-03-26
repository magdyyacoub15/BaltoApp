class AppUser {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String clinicId;
  final String role; // 'admin' or 'secretary'
  final bool isApproved;
  final bool canViewAccounts;
  final bool canViewPatients;

  AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.clinicId,
    required this.role,
    this.isApproved = false,
    this.canViewAccounts = true,
    this.canViewPatients = true,
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
      canViewAccounts: data['canViewAccounts'] ?? true,
      canViewPatients: data['canViewPatients'] ?? true,
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
      'canViewAccounts': canViewAccounts,
      'canViewPatients': canViewPatients,
    };
  }

  AppUser copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    String? clinicId,
    String? role,
    bool? isApproved,
    bool? canViewAccounts,
    bool? canViewPatients,
  }) {
    return AppUser(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      clinicId: clinicId ?? this.clinicId,
      role: role ?? this.role,
      isApproved: isApproved ?? this.isApproved,
      canViewAccounts: canViewAccounts ?? this.canViewAccounts,
      canViewPatients: canViewPatients ?? this.canViewPatients,
    );
  }
}
