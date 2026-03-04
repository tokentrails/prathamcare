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
          border: selected 
              ? Border.all(color: AppColors.primaryBorder)
              : Border.all(color: Colors.transparent),
          boxShadow: selected ? null : const [
            BoxShadow(color: Color(0x0A0F756D), blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: AppColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person_outline_rounded, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isEmpty ? 'Unnamed patient' : name,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.lightTextPrimary),
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.lightInputBg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.lightBorder),
                ),
                child: Text(
                  'ABHA $abhaMasked',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.lightTextSecondary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
