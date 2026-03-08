import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

class DoctorStatusChip extends StatelessWidget {
  const DoctorStatusChip({super.key, required this.isActive});

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final bg = isActive ? AppColors.lightSuccessSoft : AppColors.lightErrorSoft;
    final fg = isActive ? AppColors.lightSuccess : AppColors.lightError;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isActive ? 'Active' : 'Inactive',
        style: TextStyle(
          color: fg,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
