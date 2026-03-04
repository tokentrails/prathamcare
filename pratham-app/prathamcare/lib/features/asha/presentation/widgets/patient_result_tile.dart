import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

class PatientResultTile extends StatelessWidget {
  const PatientResultTile({
    super.key,
    required this.patient,
    required this.onTap,
    this.selected = false,
  });

  final Map<String, dynamic> patient;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final name = '${patient['name'] ?? ''}'.trim();
    final district = '${patient['district'] ?? ''}'.trim();
    final village = '${patient['village_or_ward'] ?? ''}'.trim();
    final phoneMasked = '${patient['phone_masked'] ?? ''}'.trim();
    final abhaMasked = '${patient['abha_masked'] ?? ''}'.trim();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySoft : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.primaryBorder : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.person_outline_rounded, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isEmpty ? 'Unnamed patient' : name,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [if (phoneMasked.isNotEmpty) phoneMasked, if (village.isNotEmpty) village, if (district.isNotEmpty) district]
                        .join(' • '),
                    style: const TextStyle(color: AppColors.lightTextMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (abhaMasked.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  'ABHA $abhaMasked',
                  style: const TextStyle(fontSize: 11, color: AppColors.lightTextMuted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
