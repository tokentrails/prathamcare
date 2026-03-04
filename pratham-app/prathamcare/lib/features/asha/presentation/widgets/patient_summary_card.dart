import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

class PatientSummaryCard extends StatelessWidget {
  const PatientSummaryCard({
    super.key,
    required this.patient,
    required this.onChange,
    this.onEdit,
  });

  final Map<String, dynamic> patient;
  final VoidCallback onChange;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final name = '${patient['full_name'] ?? patient['name'] ?? ''}'.trim();
    final phone = '${patient['phone_number'] ?? patient['phone_masked'] ?? ''}'.trim();
    final location = [
      '${patient['village_or_ward'] ?? ''}'.trim(),
      '${patient['district'] ?? ''}'.trim(),
      '${patient['state'] ?? ''}'.trim(),
    ].where((v) => v.isNotEmpty).join(', ');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFFCF9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primaryBorder),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.verified_user_outlined, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name.isEmpty ? 'Patient selected' : name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(onPressed: onChange, child: const Text('Change')),
              if (onEdit != null) TextButton(onPressed: onEdit, child: const Text('Edit')),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              [if (phone.isNotEmpty) phone, if (location.isNotEmpty) location].join(' • '),
              style: const TextStyle(color: AppColors.lightTextMuted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
