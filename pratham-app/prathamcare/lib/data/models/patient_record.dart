class PatientRecord {
  const PatientRecord({
    required this.patientId,
    required this.fullName,
    required this.gender,
    this.dateOfBirth,
    this.ageYears,
    this.phoneNumber,
    this.abhaNumber,
    this.villageOrWard,
    this.district,
    this.state,
    this.addressLine1,
    this.pincode,
  });

  final String patientId;
  final String fullName;
  final String gender;
  final String? dateOfBirth;
  final int? ageYears;
  final String? phoneNumber;
  final String? abhaNumber;
  final String? villageOrWard;
  final String? district;
  final String? state;
  final String? addressLine1;
  final String? pincode;

  factory PatientRecord.fromJson(Map<String, dynamic> json) {
    return PatientRecord(
      patientId: '${json['patient_id'] ?? ''}',
      fullName: '${json['full_name'] ?? json['name'] ?? ''}',
      gender: '${json['gender'] ?? 'unknown'}',
      dateOfBirth: _asNullableString(json['date_of_birth']),
      ageYears: _asNullableInt(json['age_years']),
      phoneNumber: _asNullableString(json['phone_number']),
      abhaNumber: _asNullableString(json['abha_number']),
      villageOrWard: _asNullableString(json['village_or_ward']),
      district: _asNullableString(json['district']),
      state: _asNullableString(json['state']),
      addressLine1: _asNullableString(json['address_line1']),
      pincode: _asNullableString(json['pincode']),
    );
  }

  static String? _asNullableString(dynamic v) {
    final s = '$v'.trim();
    if (s.isEmpty || s == 'null') {
      return null;
    }
    return s;
  }

  static int? _asNullableInt(dynamic v) {
    if (v is int) {
      return v;
    }
    final parsed = int.tryParse('$v');
    return parsed;
  }
}
