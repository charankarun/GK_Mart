import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class AppBottomNavIcon extends StatelessWidget {
  const AppBottomNavIcon({
    super.key,
    required this.icon,
    required this.selected,
    this.badgeCount = 0,
  });

  final IconData icon;
  final bool selected;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? AppColors.primaryDark : AppColors.mutedText;
    final background = selected
        ? AppColors.primary.withValues(alpha: 0.14)
        : Colors.transparent;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: selected ? 48 : 40,
          height: 32,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Icon(icon, color: foreground, size: selected ? 25 : 23),
        ),
        if (badgeCount > 0)
          Positioned(
            right: selected ? 3 : 0,
            top: -3,
            child: Container(
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white, width: 1.4),
              ),
              alignment: Alignment.center,
              child: Text(
                badgeCount > 99 ? '99+' : '$badgeCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  height: 1,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
