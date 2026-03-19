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
          ? (data['createdAt'] as dynamic).toDate()
          : DateTime.now(),
      lastShiftReset: data['lastShiftReset'] != null
          ? (data['lastShiftReset'] as dynamic).toDate()
          : null,
      subscriptionEndDate: data['subscriptionEndDate'] != null
          ? (data['subscriptionEndDate'] as dynamic).toDate()
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
      'createdAt': createdAt,
      'lastShiftReset': lastShiftReset,
      'subscriptionEndDate': subscriptionEndDate,
      'isTrial': isTrial,
      'address': address,
      'phone': phone,
      'specialization': specialization,
      'doctorName': doctorName,
    };
  }
}
