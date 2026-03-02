import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum AppPillButtonVariant { primary, dark, light }

class AppPillButton extends StatelessWidget {
  const AppPillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.arrow_upward_rounded,
    this.variant = AppPillButtonVariant.primary,
    this.height = 50,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData icon;
  final AppPillButtonVariant variant;
  final double height;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final bg = switch (variant) {
      AppPillButtonVariant.primary => const Color(0xFF0F766E),
      AppPillButtonVariant.dark => const Color(0xFF121829),
      AppPillButtonVariant.light => Colors.white,
    };
    final fg = switch (variant) {
      AppPillButtonVariant.primary => Colors.white,
      AppPillButtonVariant.dark => Colors.white,
      AppPillButtonVariant.light => AppColors.primary,
    };
    final iconBg = switch (variant) {
      AppPillButtonVariant.primary => const Color(0xFF188A81),
      AppPillButtonVariant.dark => const Color(0xFF1D2538),
      AppPillButtonVariant.light => const Color(0xFFF0F5F4),
    };
    final border = switch (variant) {
      AppPillButtonVariant.light => const Color(0xFFE2E8F0),
      _ => Colors.transparent,
    };

    Widget child = Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(999),
          child: Ink(
            height: height,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: border),
              boxShadow: variant == AppPillButtonVariant.light
                  ? const []
                  : const [
                      BoxShadow(
                        color: Color(0x22000000),
                        blurRadius: 8,
                        offset: Offset(0, 3),
                      ),
                    ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fg,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: iconBg,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, color: fg, size: 18),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (expand) {
      child = SizedBox(width: double.infinity, child: child);
    }
    return child;
  }
}

