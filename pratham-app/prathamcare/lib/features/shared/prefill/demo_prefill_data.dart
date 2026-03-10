class DemoLoginPrefill {
  const DemoLoginPrefill({required this.username, required this.password});

  final String username;
  final String password;
}

class DemoPatientPrefill {
  const DemoPatientPrefill({
    required this.firstName,
    required this.middleName,
    required this.lastName,
    required this.gender,
    required this.phoneNumber,
    required this.dateOfBirth,
    required this.ageYears,
    required this.abhaNumber,
    required this.abhaAddress,
    required this.email,
    required this.addressLine1,
    required this.addressLine2,
    required this.villageOrWard,
    required this.gramPanchayat,
    required this.blockOrTaluk,
    required this.district,
    required this.state,
    required this.pincode,
    required this.landmark,
  });

  final String firstName;
  final String middleName;
  final String lastName;
  final String gender;
  final String phoneNumber;
  final String dateOfBirth;
  final String ageYears;
  final String abhaNumber;
  final String abhaAddress;
  final String email;
  final String addressLine1;
  final String addressLine2;
  final String villageOrWard;
  final String gramPanchayat;
  final String blockOrTaluk;
  final String district;
  final String state;
  final String pincode;
  final String landmark;
}

class DemoPublicAppointmentPrefill {
  const DemoPublicAppointmentPrefill({
    required this.fullName,
    required this.phone,
    required this.email,
    required this.abhaId,
    required this.reasonCode,
    required this.reasonText,
    required this.timeSlot,
    required this.addressLine1,
    required this.addressLine2,
    required this.villageOrWard,
    required this.blockOrTaluk,
    required this.district,
    required this.state,
    required this.pincode,
  });

  final String fullName;
  final String phone;
  final String email;
  final String abhaId;
  final String reasonCode;
  final String reasonText;
  final String timeSlot;
  final String addressLine1;
  final String addressLine2;
  final String villageOrWard;
  final String blockOrTaluk;
  final String district;
  final String state;
  final String pincode;
}

class DemoPrefillData {
  static DemoLoginPrefill loginForRoleIndex(int roleIndex) {
    switch (roleIndex) {
      case 0:
        return const DemoLoginPrefill(username: '', password: '');
      case 1:
        return const DemoLoginPrefill(
          username: 'loydiadit@gmail.com',
          password: 'Pratham@2026',
        );
      default:
        return const DemoLoginPrefill(username: '', password: '');
    }
  }

  static const DemoPatientPrefill patient = DemoPatientPrefill(
    firstName: 'Ananya',
    middleName: '',
    lastName: 'Sharma',
    gender: 'female',
    phoneNumber: '+919847812307',
    dateOfBirth: '1995-06-13',
    ageYears: '33',
    abhaNumber: '12345678908834',
    abhaAddress: 'Ananya.Sharma@abdm',
    email: 'Ananya.Sharma@example.com',
    addressLine1: 'Ward 6, Near Anganwadi Center',
    addressLine2: 'House 22',
    villageOrWard: 'Jyothinagar',
    gramPanchayat: 'Jyothinagar',
    blockOrTaluk: 'Chikkamagaluru',
    district: 'Chikkamagaluru',
    state: 'Karnataka',
    pincode: '577102',
    landmark: 'Near Government Primary School',
  );

  static const DemoPublicAppointmentPrefill publicAppointment =
      DemoPublicAppointmentPrefill(
        fullName: 'Lakshmi Reddy',
        phone: '+919876543540',
        email: 'lakshmi.reddy@example.com',
        abhaId: '56789012347478',
        reasonCode: 'maternal_newborn_follow_up',
        reasonText:
            'Need post-delivery follow-up and newborn feeding guidance.',
        timeSlot: 'morning',
        addressLine1: 'Behind PHC, House 11',
        addressLine2: 'Jyothinagar',
        villageOrWard: 'Jyothinagar',
        blockOrTaluk: 'Chikkamagaluru',
        district: 'Chikkamagaluru',
        state: 'Karnataka',
        pincode: '577102',
      );
}
