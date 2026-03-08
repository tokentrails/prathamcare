import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../data/network/api_client.dart';
import '../../data/models/admin_doctor.dart';
import '../widgets/doctor_form.dart';

class AdminDoctorFormScreen extends StatefulWidget {
  const AdminDoctorFormScreen({super.key, this.initialDoctor});

  final AdminDoctor? initialDoctor;

  @override
  State<AdminDoctorFormScreen> createState() => _AdminDoctorFormScreenState();
}

class _AdminDoctorFormScreenState extends State<AdminDoctorFormScreen> {
  final ApiClient _apiClient = ApiClient();
  bool _submitting = false;

  bool get _isEdit => widget.initialDoctor != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Doctor' : 'Add Doctor'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: DoctorForm(
              initialDoctor: widget.initialDoctor,
              submitting: _submitting,
              onSubmit: _submit,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit(Map<String, dynamic> payload) async {
    setState(() => _submitting = true);
    try {
      if (_isEdit) {
        await _apiClient.adminUpdateDoctor(
          doctorId: widget.initialDoctor!.doctorId,
          payload: payload,
        );
      } else {
        await _apiClient.adminCreateDoctor(payload: payload);
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isEdit ? 'Doctor updated successfully' : 'Doctor created successfully')),
      );
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${e.code}: ${e.message}')),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save doctor')),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
}
