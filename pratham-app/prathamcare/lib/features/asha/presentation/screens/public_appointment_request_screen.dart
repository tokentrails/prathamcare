import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../data/network/api_client.dart';

class PublicAppointmentRequestScreen extends StatefulWidget {
  const PublicAppointmentRequestScreen({super.key});

  @override
  State<PublicAppointmentRequestScreen> createState() => _PublicAppointmentRequestScreenState();
}

class _PublicAppointmentRequestScreenState extends State<PublicAppointmentRequestScreen> {
  final ApiClient _apiClient = ApiClient();
  final _formKey = GlobalKey<FormState>();

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _reasonText = TextEditingController();
  final _address1 = TextEditingController();
  final _address2 = TextEditingController();
  final _village = TextEditingController();
  final _block = TextEditingController();
  final _district = TextEditingController();
  final _state = TextEditingController();
  final _pincode = TextEditingController();
  final _abha = TextEditingController();

  String _reasonCode = 'home_visit_follow_up';
  String _timeSlot = 'morning';
  DateTime? _preferredDate;
  bool _submitting = false;
  String? _result;
  String? _error;

  static const _reasonOptions = <String, String>{
    'home_visit_follow_up': 'Home visit follow-up',
    'maternal_newborn_follow_up': 'Maternal/newborn follow-up',
    'immunization_mobilization': 'Immunization mobilization',
    'family_planning_counseling': 'Family planning counseling',
    'referral_support': 'Referral support',
    'community_follow_up': 'Community-level follow-up',
    'general_health_check': 'General health check',
  };

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _reasonText.dispose();
    _address1.dispose();
    _address2.dispose();
    _village.dispose();
    _block.dispose();
    _district.dispose();
    _state.dispose();
    _pincode.dispose();
    _abha.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
      _result = null;
    });

    try {
      final res = await _apiClient.requestPublicASHAAppointment(payload: {
        'requestor_name': _name.text.trim(),
        'requestor_phone': _phone.text.trim(),
        if (_email.text.trim().isNotEmpty) 'requestor_email': _email.text.trim(),
        if (_abha.text.trim().isNotEmpty) 'abha_number': _abha.text.trim(),
        'reason_code': _reasonCode,
        if (_reasonText.text.trim().isNotEmpty) 'reason_text': _reasonText.text.trim(),
        if (_preferredDate != null) 'preferred_date': _preferredDate!.toIso8601String().split('T').first,
        'preferred_time_slot': _timeSlot,
        'visit_type': 'home_visit',
        'address_line1': _address1.text.trim(),
        if (_address2.text.trim().isNotEmpty) 'address_line2': _address2.text.trim(),
        if (_village.text.trim().isNotEmpty) 'village_or_ward': _village.text.trim(),
        if (_block.text.trim().isNotEmpty) 'block_or_taluk': _block.text.trim(),
        'district': _district.text.trim(),
        'state': _state.text.trim(),
        'pincode': _pincode.text.trim(),
      });

      if (!mounted) return;
      setState(() {
        _result = 'Request submitted. Appointment ID: ${res['appointment_id'] ?? '-'} | Status: ${res['status'] ?? '-'}';
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '${e.code}: ${e.message}';
      });
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Request ASHA Appointment')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _field(_name, 'Name *'),
                _field(_phone, 'Phone *', keyboardType: TextInputType.phone),
                _field(_email, 'Email (optional)', keyboardType: TextInputType.emailAddress),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _reasonCode,
                  decoration: const InputDecoration(labelText: 'Reason *'),
                  items: _reasonOptions.entries
                      .map((e) => DropdownMenuItem<String>(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) => setState(() => _reasonCode = v ?? _reasonCode),
                ),
                _field(_reasonText, 'Additional details (optional)'),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_preferredDate == null
                      ? 'Preferred date (optional)'
                      : 'Preferred date: ${_preferredDate!.toIso8601String().split('T').first}'),
                  trailing: const Icon(Icons.calendar_today_outlined),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      firstDate: DateTime.now().subtract(const Duration(days: 1)),
                      lastDate: DateTime.now().add(const Duration(days: 90)),
                      initialDate: _preferredDate ?? DateTime.now(),
                    );
                    if (picked != null) setState(() => _preferredDate = picked);
                  },
                ),
                DropdownButtonFormField<String>(
                  value: _timeSlot,
                  decoration: const InputDecoration(labelText: 'Preferred time slot'),
                  items: const [
                    DropdownMenuItem(value: 'morning', child: Text('Morning')),
                    DropdownMenuItem(value: 'afternoon', child: Text('Afternoon')),
                    DropdownMenuItem(value: 'evening', child: Text('Evening')),
                  ],
                  onChanged: (v) => setState(() => _timeSlot = v ?? _timeSlot),
                ),
                const SizedBox(height: 8),
                _field(_address1, 'Address line 1 *'),
                _field(_address2, 'Address line 2 (optional)'),
                _field(_village, 'Village/Ward (optional)'),
                _field(_block, 'Block/Taluk (optional)'),
                _field(_district, 'District *'),
                _field(_state, 'State *'),
                _field(_pincode, 'Pincode *', keyboardType: TextInputType.number),
                _field(_abha, 'ABHA ID (optional)', keyboardType: TextInputType.number),
                const SizedBox(height: 12),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(_submitting ? 'Submitting...' : 'Submit Request'),
                  ),
                ),
                if (_result != null) ...[
                  const SizedBox(height: 12),
                  Text(_result!, style: const TextStyle(color: Color(0xFF166534))),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: AppColors.lightError)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
  }) {
    final isRequired = label.contains('*');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(labelText: label),
        validator: (v) {
          if (!isRequired) return null;
          if ((v ?? '').trim().isEmpty) return 'Required';
          return null;
        },
      ),
    );
  }
}
