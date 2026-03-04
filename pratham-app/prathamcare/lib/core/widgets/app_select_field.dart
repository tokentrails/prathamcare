import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class AppSelectOption<T> {
  const AppSelectOption({
    required this.value,
    required this.label,
    this.subtitle,
    this.icon,
  });

  final T value;
  final String label;
  final String? subtitle;
  final IconData? icon;
}

class AppSelectField<T> extends StatefulWidget {
  const AppSelectField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.enabled = true,
    this.leading,
    this.menuMaxHeight = 260,
  });

  final String label;
  final T value;
  final List<AppSelectOption<T>> options;
  final ValueChanged<T> onChanged;
  final bool enabled;
  final Widget? leading;
  final double menuMaxHeight;

  @override
  State<AppSelectField<T>> createState() => _AppSelectFieldState<T>();
}

class _AppSelectFieldState<T> extends State<AppSelectField<T>> {
  final GlobalKey _fieldKey = GlobalKey();
  bool _opening = false;

  @override
  Widget build(BuildContext context) {
    final selected = _selectedOption;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.lightTextMuted,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          key: _fieldKey,
          onTap: widget.enabled ? _openPopover : null,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: widget.enabled ? Colors.white : AppColors.lightDisabledBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _opening
                    ? AppColors.primary
                    : (widget.enabled
                        ? AppColors.lightBorder
                        : AppColors.lightDisabledText.withValues(alpha: 0.35)),
              ),
            ),
            child: Row(
              children: [
                if (widget.leading != null) ...[
                  widget.leading!,
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    selected?.label ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: widget.enabled ? AppColors.lightTextPrimary : AppColors.lightDisabledText,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                Icon(
                  _opening ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  color: widget.enabled ? AppColors.primary : AppColors.lightDisabledText,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  AppSelectOption<T>? get _selectedOption {
    for (final item in widget.options) {
      if (item.value == widget.value) {
        return item;
      }
    }
    return widget.options.isEmpty ? null : widget.options.first;
  }

  Future<void> _openPopover() async {
    if (_opening || widget.options.isEmpty) {
      return;
    }
    final contextRef = _fieldKey.currentContext;
    if (contextRef == null) {
      return;
    }

    final renderBox = contextRef.findRenderObject() as RenderBox?;
    final overlayBox = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (renderBox == null || overlayBox == null) {
      return;
    }

    final topLeft = renderBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    final bottomRight = renderBox.localToGlobal(renderBox.size.bottomRight(Offset.zero), ancestor: overlayBox);

    final position = RelativeRect.fromLTRB(
      topLeft.dx,
      topLeft.dy + renderBox.size.height + 6,
      overlayBox.size.width - bottomRight.dx,
      overlayBox.size.height - (topLeft.dy + renderBox.size.height + 6),
    );

    setState(() => _opening = true);
    final selected = await showMenu<T>(
      context: context,
      position: position,
      elevation: 10,
      color: Colors.white,
      constraints: BoxConstraints(
        minWidth: renderBox.size.width,
        maxWidth: renderBox.size.width,
        maxHeight: widget.menuMaxHeight,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.lightBorder),
      ),
      items: widget.options.map((item) {
        final active = item.value == widget.value;
        return PopupMenuItem<T>(
          value: item.value,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: active ? const Color(0xFFEAF2FC) : Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: active ? AppColors.primary : AppColors.lightTextPrimary,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (active)
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: AppColors.primary,
                  ),
              ],
            ),
          ),
        );
      }).toList(),
    );

    if (mounted) {
      setState(() => _opening = false);
    }
    if (selected != null && selected != widget.value) {
      widget.onChanged(selected);
    }
  }
}
