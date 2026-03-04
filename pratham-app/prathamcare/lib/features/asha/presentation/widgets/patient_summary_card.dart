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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEFFCF9), // AppColors.primarySoft
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Color(0x0A0F756D), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: AppColors.primary.withValues(alpha: 0.1), blurRadius: 4),
                  ],
                ),
                child: const Icon(Icons.verified_user_rounded, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? 'Patient selected' : name,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.lightTextPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [if (phone.isNotEmpty) phone, if (location.isNotEmpty) location].join(' • '),
                      style: const TextStyle(color: AppColors.lightTextSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (onEdit != null)
                InkWell(
                  onTap: onEdit,
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.primary),
                      borderRadius: BorderRadius.circular(999),
                      color: Colors.white,
                    ),
                    child: const Text(
                      'Edit Details',
                      style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                ),
              const SizedBox(width: 12),
              InkWell(
                onTap: onChange,
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Change Patient',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
