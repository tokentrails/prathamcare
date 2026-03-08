class AdminDoctor {
  const AdminDoctor({
    required this.doctorId,
    required this.firstName,
    required this.middleName,
    required this.lastName,
    required this.fullName,
    required this.email,
    required this.phoneNumber,
    required this.gender,
    required this.dateOfBirth,
    required this.registrationNumber,
    required this.specialization,
    required this.qualifications,
    required this.yearsExperience,
    required this.languagesSpoken,
    required this.clinicName,
    required this.addressLine1,
    required this.addressLine2,
    required this.city,
    required this.district,
    required this.state,
    required this.pincode,
    required this.inPerson,
    required this.telemedicine,
    required this.availabilitySummary,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.cognitoSub = '',
    this.createdBy = '',
    this.updatedBy = '',
  });

  final String doctorId;
  final String cognitoSub;
  final String firstName;
  final String middleName;
  final String lastName;
  final String fullName;
  final String email;
  final String phoneNumber;
  final String gender;
  final String dateOfBirth;
  final String registrationNumber;
  final String specialization;
  final String qualifications;
  final int yearsExperience;
  final List<String> languagesSpoken;
  final String clinicName;
  final String addressLine1;
  final String addressLine2;
  final String city;
  final String district;
  final String state;
  final String pincode;
  final bool inPerson;
  final bool telemedicine;
  final Object? availabilitySummary;
  final bool isActive;
  final String createdBy;
  final String updatedBy;
  final String createdAt;
  final String updatedAt;

  factory AdminDoctor.fromJson(Map<String, dynamic> json) {
    final consultation = json['consultation_mode'];
    final mode = consultation is Map<String, dynamic> ? consultation : <String, dynamic>{};
    final langsRaw = json['languages_spoken'];
    final langs = <String>[];
    if (langsRaw is List) {
      for (final item in langsRaw) {
        if (item is String && item.trim().isNotEmpty) {
          langs.add(item.trim());
        }
      }
    }
    return AdminDoctor(
      doctorId: '${json['doctor_id'] ?? ''}',
      cognitoSub: '${json['cognito_sub'] ?? ''}',
      firstName: '${json['first_name'] ?? ''}',
      middleName: '${json['middle_name'] ?? ''}',
      lastName: '${json['last_name'] ?? ''}',
      fullName: '${json['full_name'] ?? ''}',
      email: '${json['email'] ?? ''}',
      phoneNumber: '${json['phone_number'] ?? ''}',
      gender: '${json['gender'] ?? ''}',
      dateOfBirth: '${json['date_of_birth'] ?? ''}',
      registrationNumber: '${json['registration_number'] ?? ''}',
      specialization: '${json['specialization'] ?? ''}',
      qualifications: '${json['qualifications'] ?? ''}',
      yearsExperience: (json['years_experience'] as num?)?.toInt() ?? 0,
      languagesSpoken: langs,
      clinicName: '${json['clinic_name'] ?? ''}',
      addressLine1: '${json['address_line1'] ?? ''}',
      addressLine2: '${json['address_line2'] ?? ''}',
      city: '${json['city'] ?? ''}',
      district: '${json['district'] ?? ''}',
      state: '${json['state'] ?? ''}',
      pincode: '${json['pincode'] ?? ''}',
      inPerson: mode['in_person'] == true,
      telemedicine: mode['telemedicine'] == true,
      availabilitySummary: json['availability_summary'],
      isActive: json['is_active'] == true,
      createdBy: '${json['created_by'] ?? ''}',
      updatedBy: '${json['updated_by'] ?? ''}',
      createdAt: '${json['created_at'] ?? ''}',
      updatedAt: '${json['updated_at'] ?? ''}',
    );
  }
}
