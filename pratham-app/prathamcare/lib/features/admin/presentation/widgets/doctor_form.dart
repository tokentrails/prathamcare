import 'package:flutter/material.dart';

import '../../data/models/admin_doctor.dart';

class DoctorForm extends StatefulWidget {
  const DoctorForm({
    super.key,
    this.initialDoctor,
    this.submitting = false,
    required this.onSubmit,
  });

  final AdminDoctor? initialDoctor;
  final bool submitting;
  final Future<void> Function(Map<String, dynamic> payload) onSubmit;

  @override
  State<DoctorForm> createState() => _DoctorFormState();
}

class _DoctorFormState extends State<DoctorForm> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _firstName;
  late final TextEditingController _middleName;
  late final TextEditingController _lastName;
  late final TextEditingController _fullName;
  late final TextEditingController _gender;
  late final TextEditingController _dob;
  late final TextEditingController _registrationNumber;
  late final TextEditingController _specialization;
  late final TextEditingController _qualifications;
  late final TextEditingController _yearsExperience;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _clinicName;
  late final TextEditingController _addressLine1;
  late final TextEditingController _addressLine2;
  late final TextEditingController _city;
  late final TextEditingController _district;
  late final TextEditingController _state;
  late final TextEditingController _pincode;
  late final TextEditingController _availabilitySummary;
  late final TextEditingController _cognitoSub;
  final TextEditingController _languageInput = TextEditingController();

  List<String> _languages = <String>[];
  bool _inPerson = true;
  bool _telemedicine = true;
  bool _isActive = true;

  bool get _isEdit => widget.initialDoctor != null;

  @override
  void initState() {
    super.initState();
    final d = widget.initialDoctor;
    _firstName = TextEditingController(text: d?.firstName ?? '');
    _middleName = TextEditingController(text: d?.middleName ?? '');
    _lastName = TextEditingController(text: d?.lastName ?? '');
    _fullName = TextEditingController(text: d?.fullName ?? '');
    _gender = TextEditingController(text: d?.gender ?? '');
    _dob = TextEditingController(text: d?.dateOfBirth ?? '');
    _registrationNumber = TextEditingController(text: d?.registrationNumber ?? '');
    _specialization = TextEditingController(text: d?.specialization ?? '');
    _qualifications = TextEditingController(text: d?.qualifications ?? '');
    _yearsExperience = TextEditingController(text: d == null || d.yearsExperience <= 0 ? '' : '${d.yearsExperience}');
    _phone = TextEditingController(text: d?.phoneNumber ?? '');
    _email = TextEditingController(text: d?.email ?? '');
    _clinicName = TextEditingController(text: d?.clinicName ?? '');
    _addressLine1 = TextEditingController(text: d?.addressLine1 ?? '');
    _addressLine2 = TextEditingController(text: d?.addressLine2 ?? '');
    _city = TextEditingController(text: d?.city ?? '');
    _district = TextEditingController(text: d?.district ?? '');
    _state = TextEditingController(text: d?.state ?? '');
    _pincode = TextEditingController(text: d?.pincode ?? '');
    _availabilitySummary = TextEditingController(text: d?.availabilitySummary?.toString() ?? '');
    _cognitoSub = TextEditingController(text: d?.cognitoSub ?? '');
    _languages = List<String>.from(d?.languagesSpoken ?? const <String>[]);
    _inPerson = d?.inPerson ?? true;
    _telemedicine = d?.telemedicine ?? true;
    _isActive = d?.isActive ?? true;
  }

  @override
  void dispose() {
    _firstName.dispose();
    _middleName.dispose();
    _lastName.dispose();
    _fullName.dispose();
    _gender.dispose();
    _dob.dispose();
    _registrationNumber.dispose();
    _specialization.dispose();
    _qualifications.dispose();
    _yearsExperience.dispose();
    _phone.dispose();
    _email.dispose();
    _clinicName.dispose();
    _addressLine1.dispose();
    _addressLine2.dispose();
    _city.dispose();
    _district.dispose();
    _state.dispose();
    _pincode.dispose();
    _availabilitySummary.dispose();
    _cognitoSub.dispose();
    _languageInput.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle('Personal'),
          _row(
            _field(_firstName, 'First Name*', validator: _required('first_name is required')),
            _field(_middleName, 'Middle Name'),
          ),
          _row(
            _field(_lastName, 'Last Name'),
            _field(_fullName, 'Full Name (optional override)'),
          ),
          _row(
            _field(_gender, 'Gender (male/female/other/unknown)'),
            _field(_dob, 'Date of Birth (YYYY-MM-DD)'),
          ),
          const SizedBox(height: 14),
          _sectionTitle('Professional'),
          _row(
            _field(_registrationNumber, 'Registration Number*', validator: _required('registration_number is required')),
            _field(_specialization, 'Specialization*', validator: _required('specialization is required')),
          ),
          _row(
            _field(_qualifications, 'Qualifications'),
            _field(
              _yearsExperience,
              'Years Experience',
              keyboardType: TextInputType.number,
              validator: (value) {
                final trimmed = (value ?? '').trim();
                if (trimmed.isEmpty) {
                  return null;
                }
                final n = int.tryParse(trimmed);
                if (n == null || n < 0 || n > 80) {
                  return 'years_experience must be between 0 and 80';
                }
                return null;
              },
            ),
          ),
          const SizedBox(height: 10),
          _languageEditor(),
          const SizedBox(height: 14),
          _sectionTitle('Contact'),
          _row(
            _field(_phone, 'Phone Number*', validator: _phoneValidator),
            _field(_email, 'Email*', validator: _emailValidator),
          ),
          _field(_cognitoSub, 'Cognito Sub (optional)'),
          const SizedBox(height: 14),
          _sectionTitle('Practice'),
          _field(_clinicName, 'Clinic Name'),
          _field(_addressLine1, 'Address Line 1'),
          _field(_addressLine2, 'Address Line 2'),
          _row(
            _field(_city, 'City'),
            _field(_district, 'District'),
          ),
          _row(
            _field(_state, 'State'),
            _field(_pincode, 'Pincode', keyboardType: TextInputType.number, validator: _pincodeValidator),
          ),
          _field(_availabilitySummary, 'Availability Summary (text/json)'),
          const SizedBox(height: 10),
          SwitchListTile.adaptive(
            value: _inPerson,
            onChanged: widget.submitting ? null : (v) => setState(() => _inPerson = v),
            title: const Text('In-person consultation'),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
          SwitchListTile.adaptive(
            value: _telemedicine,
            onChanged: widget.submitting ? null : (v) => setState(() => _telemedicine = v),
            title: const Text('Telemedicine consultation'),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
          if (_isEdit)
            SwitchListTile.adaptive(
              value: _isActive,
              onChanged: widget.submitting ? null : (v) => setState(() => _isActive = v),
              title: const Text('Doctor is active'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: widget.submitting ? null : _submit,
            icon: widget.submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_isEdit ? 'Save Changes' : 'Create Doctor'),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      );

  Widget _row(Widget a, Widget b) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            children: [
              a,
              const SizedBox(height: 8),
              b,
              const SizedBox(height: 8),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: a),
            const SizedBox(width: 10),
            Expanded(child: b),
          ],
        );
      },
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? Function(String?)? validator,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        controller: controller,
        enabled: !widget.submitting,
        keyboardType: keyboardType,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _languageEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _languageInput,
                enabled: !widget.submitting,
                decoration: const InputDecoration(
                  labelText: 'Languages Spoken',
                  hintText: 'Type language and press add',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: widget.submitting ? null : _addLanguage,
              child: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _languages
              .map(
                (item) => Chip(
                  label: Text(item),
                  onDeleted: widget.submitting
                      ? null
                      : () {
                          setState(() => _languages.remove(item));
                        },
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  void _addLanguage() {
    final value = _languageInput.text.trim();
    if (value.isEmpty) {
      return;
    }
    if (!_languages.contains(value)) {
      setState(() => _languages.add(value));
    }
    _languageInput.clear();
  }

  String? Function(String?) _required(String message) {
    return (value) => (value ?? '').trim().isEmpty ? message : null;
  }

  String? _phoneValidator(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return 'phone_number is required';
    }
    final cleaned = text.replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleaned.length < 10) {
      return 'phone_number must be valid';
    }
    return null;
  }

  String? _emailValidator(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return 'email is required';
    }
    final pattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    if (!pattern.hasMatch(text)) {
      return 'invalid email format';
    }
    return null;
  }

  String? _pincodeValidator(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return null;
    }
    if (!RegExp(r'^\d{6}$').hasMatch(text)) {
      return 'pincode must be 6 digits';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_lastName.text.trim().isEmpty && _fullName.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('last_name or full_name is required')),
      );
      return;
    }

    final payload = <String, dynamic>{
      'cognito_sub': _cognitoSub.text.trim(),
      'first_name': _firstName.text.trim(),
      'middle_name': _middleName.text.trim(),
      'last_name': _lastName.text.trim(),
      'full_name': _fullName.text.trim(),
      'gender': _gender.text.trim().toLowerCase(),
      'date_of_birth': _dob.text.trim(),
      'registration_number': _registrationNumber.text.trim(),
      'specialization': _specialization.text.trim(),
      'qualifications': _qualifications.text.trim(),
      'years_experience': int.tryParse(_yearsExperience.text.trim()) ?? 0,
      'languages_spoken': _languages,
      'phone_number': _phone.text.trim(),
      'email': _email.text.trim(),
      'clinic_name': _clinicName.text.trim(),
      'address_line1': _addressLine1.text.trim(),
      'address_line2': _addressLine2.text.trim(),
      'city': _city.text.trim(),
      'district': _district.text.trim(),
      'state': _state.text.trim(),
      'pincode': _pincode.text.trim(),
      'consultation_mode': {
        'in_person': _inPerson,
        'telemedicine': _telemedicine,
      },
      'availability_summary': _availabilitySummary.text.trim(),
      if (_isEdit) 'is_active': _isActive,
    };
    await widget.onSubmit(payload);
  }
}
