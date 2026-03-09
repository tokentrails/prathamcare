import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_pill_button.dart';
import '../../../../data/network/api_client.dart';
import '../../../shared/prefill/demo_prefill_data.dart';
import '../../../shared/widgets/demo_prefill_button.dart';
import '../widgets/patient_form_section.dart';

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
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to submit right now. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  void _prefillDemoData() {
    final preset = DemoPrefillData.publicAppointment;
    setState(() {
      _name.text = preset.fullName;
      _phone.text = preset.phone;
      _email.text = preset.email;
      _abha.text = preset.abhaId;
      _reasonCode = preset.reasonCode;
      _reasonText.text = preset.reasonText;
      _preferredDate = DateTime.now().add(const Duration(days: 1));
      _timeSlot = preset.timeSlot;
      _address1.text = preset.addressLine1;
      _address2.text = preset.addressLine2;
      _village.text = preset.villageOrWard;
      _block.text = preset.blockOrTaluk;
      _district.text = preset.district;
      _state.text = preset.state;
      _pincode.text = preset.pincode;
      _error = null;
      _result = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(
        title: const Text('ASHA Home Visit Request'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildHeaderCard(),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: DemoPrefillButton(onPressed: _prefillDemoData),
                  ),
                  const SizedBox(height: 12),
                  _buildSectionCard(
                    child: PatientFormSection(
                      title: 'Contact Details',
                      child: Column(
                        children: [
                          _textField(_name, 'Full Name *', validator: _required('Name is required')),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _textField(
                                  _phone,
                                  'Phone Number *',
                                  keyboardType: TextInputType.phone,
                                  validator: (value) {
                                    final v = (value ?? '').trim();
                                    if (v.isEmpty) {
                                      return 'Phone number is required';
                                    }
                                    final digits = v.replaceAll(RegExp(r'[^0-9]'), '');
                                    if (digits.length < 10 || digits.length > 12) {
                                      return 'Enter valid phone number';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _textField(
                                  _email,
                                  'Email (optional)',
                                  keyboardType: TextInputType.emailAddress,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _textField(
                            _abha,
                            'ABHA ID (optional)',
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              final v = (value ?? '').trim();
                              if (v.isEmpty) {
                                return null;
                              }
                              final digits = v.replaceAll(RegExp(r'[^0-9]'), '');
                              if (digits.length != 14) {
                                return 'ABHA should be 14 digits';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildSectionCard(
                    child: PatientFormSection(
                      title: 'Visit Reason',
                      child: Column(
                        children: [
                          _dropdownField(
                            label: 'Reason *',
                            value: _reasonCode,
                            items: _reasonOptions.entries
                                .map((e) => DropdownMenuItem<String>(value: e.key, child: Text(e.value)))
                                .toList(),
                            onChanged: (v) => setState(() => _reasonCode = v ?? _reasonCode),
                          ),
                          const SizedBox(height: 10),
                          _textField(_reasonText, 'Additional Notes (optional)', maxLines: 3),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Preferred Date (optional)',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.lightTextSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    InkWell(
                                      onTap: () async {
                                        final picked = await showDatePicker(
                                          context: context,
                                          firstDate: DateTime.now().subtract(const Duration(days: 1)),
                                          lastDate: DateTime.now().add(const Duration(days: 90)),
                                          initialDate: _preferredDate ?? DateTime.now(),
                                        );
                                        if (picked != null) {
                                          setState(() => _preferredDate = picked);
                                        }
                                      },
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                        decoration: BoxDecoration(
                                          color: AppColors.lightInputBg,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: AppColors.lightBorder),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.calendar_today_outlined, size: 18, color: AppColors.lightTextMuted),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                _preferredDate == null
                                                    ? 'Select date'
                                                    : _preferredDate!.toIso8601String().split('T').first,
                                                style: const TextStyle(fontSize: 14),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _dropdownField(
                                  label: 'Time Slot *',
                                  value: _timeSlot,
                                  items: const [
                                    DropdownMenuItem(value: 'morning', child: Text('Morning')),
                                    DropdownMenuItem(value: 'afternoon', child: Text('Afternoon')),
                                    DropdownMenuItem(value: 'evening', child: Text('Evening')),
                                  ],
                                  onChanged: (v) => setState(() => _timeSlot = v ?? _timeSlot),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildSectionCard(
                    child: PatientFormSection(
                      title: 'Address',
                      child: Column(
                        children: [
                          _textField(_address1, 'Address Line 1 *', validator: _required('Address is required')),
                          const SizedBox(height: 10),
                          _textField(_address2, 'Address Line 2 (optional)'),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(child: _textField(_village, 'Village / Ward (optional)')),
                              const SizedBox(width: 10),
                              Expanded(child: _textField(_block, 'Block / Taluk (optional)')),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(child: _textField(_district, 'District *', validator: _required('District is required'))),
                              const SizedBox(width: 10),
                              Expanded(child: _textField(_state, 'State *', validator: _required('State is required'))),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _textField(
                            _pincode,
                            'Pincode *',
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              final v = (value ?? '').trim();
                              if (v.isEmpty) {
                                return 'Pincode is required';
                              }
                              if (!RegExp(r'^\d{6}$').hasMatch(v)) {
                                return 'Pincode must be 6 digits';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_result != null) ...[
                    const SizedBox(height: 12),
                    _buildStatusCard(_result!, AppColors.lightSuccessSoft, AppColors.lightSuccess),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    _buildStatusCard(_error!, AppColors.lightErrorSoft, AppColors.lightError),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 52,
                    child: AppPillButton(
                      onPressed: _submitting ? null : _submit,
                      icon: Icons.arrow_outward_rounded,
                      label: _submitting ? 'Submitting...' : 'Submit Appointment Request',
                      variant: AppPillButtonVariant.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F766E), Color(0xFF129186)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Request an ASHA Home Visit',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 6),
          Text(
            'Fill this form once. We will assign the nearest ASHA worker based on your location.',
            style: TextStyle(color: Color(0xFFE2FFFB), fontSize: 13.5, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: child,
    );
  }

  Widget _buildStatusCard(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _textField(
    TextEditingController controller,
    String label, {
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.lightTextSecondary,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: keyboardType,
          maxLines: maxLines,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.lightTextPrimary,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.lightInputBg,
            hintText: 'Enter ${label.replaceAll('*', '').replaceAll('(optional)', '').trim()}',
            hintStyle: const TextStyle(
              fontSize: 14,
              color: AppColors.lightPlaceholder,
              fontWeight: FontWeight.w400,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.lightBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.lightBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.lightError),
            ),
          ),
        ),
      ],
    );
  }

  Widget _dropdownField({
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.lightTextSecondary,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: value,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.lightTextMuted),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.lightTextPrimary,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.lightInputBg,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.lightBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.lightBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
            ),
          ),
          items: items,
          onChanged: onChanged,
        ),
      ],
    );
  }

  FormFieldValidator<String> _required(String message) {
    return (value) => (value ?? '').trim().isEmpty ? message : null;
  }
}
