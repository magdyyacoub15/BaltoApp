class ClinicGroup {
  final String id;
  final String name;
  final String clinicCode; // Required for joining
  final DateTime createdAt;
  final DateTime? lastShiftReset;
  final DateTime? subscriptionEndDate;
  final bool isTrial;

  final String? address;
  final String? phone;
  final String? specialization;
  final String? doctorName;

  ClinicGroup({
    required this.id,
    required this.name,
    required this.clinicCode,
    required this.createdAt,
    this.lastShiftReset,
    this.subscriptionEndDate,
    this.isTrial = false,
    this.address,
    this.phone,
    this.specialization,
    this.doctorName,
  });

  factory ClinicGroup.fromMap(Map<String, dynamic> data, String id) {
    return ClinicGroup(
      id: id,
      name: data['name'] ?? '',
      clinicCode: data['clinicCode'] ?? '',
      createdAt: data['createdAt'] != null
          ? DateTime.tryParse(data['createdAt'].toString())?.toUtc() ?? DateTime.now().toUtc()
          : DateTime.now().toUtc(),
      lastShiftReset: data['lastShiftReset'] != null
          ? DateTime.tryParse(data['lastShiftReset'].toString())?.toUtc()
          : null,
      subscriptionEndDate: data['subscriptionEndDate'] != null
          ? DateTime.tryParse(data['subscriptionEndDate'].toString())?.toUtc()
          : null,
      isTrial: data['isTrial'] ?? false,
      address: data['address'],
      phone: data['phone'],
      specialization: data['specialization'],
      doctorName: data['doctorName'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'clinicCode': clinicCode,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'lastShiftReset': lastShiftReset?.toUtc().toIso8601String(),
      'subscriptionEndDate': subscriptionEndDate?.toUtc().toIso8601String(),
      'isTrial': isTrial,
      'address': address,
      'phone': phone,
      'specialization': specialization,
      'doctorName': doctorName,
    };
  }
}
