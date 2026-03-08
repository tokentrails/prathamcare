import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../data/network/api_client.dart';
import '../../data/models/admin_doctor.dart';
import '../widgets/doctor_status_chip.dart';

class AdminDoctorDetailScreen extends StatefulWidget {
  const AdminDoctorDetailScreen({super.key, required this.doctorId});

  final String doctorId;

  @override
  State<AdminDoctorDetailScreen> createState() => _AdminDoctorDetailScreenState();
}

class _AdminDoctorDetailScreenState extends State<AdminDoctorDetailScreen> {
  final ApiClient _apiClient = ApiClient();
  bool _loading = true;
  String? _error;
  AdminDoctor? _doctor;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _apiClient.adminGetDoctorById(doctorId: widget.doctorId);
      if (!mounted) {
        return;
      }
      setState(() => _doctor = AdminDoctor.fromJson(data));
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _error = '${e.code}: ${e.message}');
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _error = 'Failed to load doctor');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(title: const Text('Doctor Details')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_loading) const Center(child: CircularProgressIndicator()),
                  if (_error != null)
                    Text(_error!, style: const TextStyle(color: AppColors.lightError)),
                  if (!_loading && _doctor == null && _error == null) const Text('Doctor not found'),
                  if (_doctor != null) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _doctor!.fullName.isEmpty ? _doctor!.firstName : _doctor!.fullName,
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                          ),
                        ),
                        DoctorStatusChip(isActive: _doctor!.isActive),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _item('Registration', _doctor!.registrationNumber),
                    _item('Specialization', _doctor!.specialization),
                    _item('Phone', _doctor!.phoneNumber),
                    _item('Email', _doctor!.email),
                    _item('Gender', _doctor!.gender),
                    _item('DOB', _doctor!.dateOfBirth),
                    _item('Qualifications', _doctor!.qualifications),
                    _item('Years Experience', '${_doctor!.yearsExperience}'),
                    _item('Languages', _doctor!.languagesSpoken.join(', ')),
                    _item('Clinic', _doctor!.clinicName),
                    _item(
                      'Address',
                      [
                        _doctor!.addressLine1,
                        _doctor!.addressLine2,
                        _doctor!.city,
                        _doctor!.district,
                        _doctor!.state,
                        _doctor!.pincode,
                      ].where((e) => e.trim().isNotEmpty).join(', '),
                    ),
                    _item(
                      'Consultation Mode',
                      '${_doctor!.inPerson ? 'In-person' : ''}${_doctor!.inPerson && _doctor!.telemedicine ? ', ' : ''}${_doctor!.telemedicine ? 'Telemedicine' : ''}',
                    ),
                    _item('Created At', _doctor!.createdAt),
                    _item('Updated At', _doctor!.updatedAt),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: const TextStyle(color: AppColors.lightTextMuted)),
          ),
          Expanded(child: Text(value.trim().isEmpty ? '-' : value)),
        ],
      ),
    );
  }
}
