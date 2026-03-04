import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

class PatientSearchField extends StatelessWidget {
  const PatientSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onAddNew,
    this.onClear,
    this.loading = false,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onAddNew;
  final VoidCallback? onClear;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Find Patient',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
            TextButton.icon(
              onPressed: onAddNew,
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
              label: const Text('+ Add New Patient'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          onChanged: onChanged,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.lightTextPrimary,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.lightInputBg,
            hintText: 'Search by name, phone, ABHA...',
            hintStyle: const TextStyle(
              fontSize: 14,
              color: AppColors.lightPlaceholder,
              fontWeight: FontWeight.w400,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            prefixIcon: const Icon(Icons.search_rounded, color: AppColors.lightPlaceholder),
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
            suffixIcon: loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : (controller.text.trim().isNotEmpty && onClear != null)
                    ? IconButton(
                        onPressed: onClear,
                        icon: const Icon(Icons.close_rounded, color: AppColors.lightTextMuted),
                      )
                    : null,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Tip: 10-digit mobile and 14-digit ABHA are matched exactly.',
          style: TextStyle(color: AppColors.lightTextMuted, fontSize: 12),
        ),
      ],
    );
  }
}
