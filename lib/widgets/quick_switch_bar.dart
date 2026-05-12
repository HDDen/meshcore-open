import 'dart:ui';

import 'package:flutter/material.dart';
import '../l10n/l10n.dart';

class QuickSwitchBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final int contactsUnreadCount;
  final int channelsUnreadCount;

  const QuickSwitchBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.contactsUnreadCount = 0,
    this.channelsUnreadCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final labelStyle = theme.textTheme.labelMedium ?? const TextStyle();

    return SizedBox(
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.transparent,
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: NavigationBarTheme(
              data: NavigationBarThemeData(
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                shadowColor: Colors.transparent,
                indicatorColor: colorScheme.primaryContainer,
                labelTextStyle: WidgetStateProperty.resolveWith((states) {
                  final isSelected = states.contains(WidgetState.selected);
                  return labelStyle.copyWith(
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurfaceVariant,
                  );
                }),
                iconTheme: WidgetStateProperty.resolveWith((states) {
                  final isSelected = states.contains(WidgetState.selected);
                  return IconThemeData(
                    color: isSelected
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurfaceVariant,
                  );
                }),
              ),
              child: NavigationBar(
                height: 60,
                selectedIndex: selectedIndex,
                onDestinationSelected: onDestinationSelected,
                destinations: [
                  NavigationDestination(
                    icon: _buildIconWithBadge(
                      const Icon(Icons.people_outline),
                      contactsUnreadCount,
                    ),
                    selectedIcon: _buildIconWithBadge(
                      const Icon(Icons.people),
                      contactsUnreadCount,
                    ),
                    label: context.l10n.nav_contacts,
                  ),
                  NavigationDestination(
                    icon: _buildIconWithBadge(
                      const Icon(Icons.tag),
                      channelsUnreadCount,
                    ),
                    selectedIcon: _buildIconWithBadge(
                      const Icon(Icons.tag),
                      channelsUnreadCount,
                    ),
                    label: context.l10n.nav_channels,
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.map_outlined),
                    selectedIcon: const Icon(Icons.map),
                    label: context.l10n.nav_map,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconWithBadge(Icon icon, int count) {
    if (count <= 0) return icon;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          right: -2,
          top: -2,
          child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Colors.redAccent,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ],
    );
  }
}
