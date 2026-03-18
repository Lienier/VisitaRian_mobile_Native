import 'package:flutter/material.dart';
import 'package:visitarian_flutter/screens/widgets/tour_selection_styles.dart';

class TourSelectionBottomNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const TourSelectionBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.sizeOf(context);
    final isLandscapePhone = size.width >= 640 && size.height < 560;
    final surface = isDark ? scheme.surfaceContainerHigh : scheme.surface;
    return Container(
      decoration: BoxDecoration(
        color: surface,
        border: Border(
          top: BorderSide(
            color: isDark
                ? scheme.outline.withValues(alpha: 0.45)
                : scheme.outline.withValues(alpha: 0.15),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.1),
            blurRadius: isDark ? 10 : 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: isLandscapePhone ? 4 : 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(
                icon: Icons.home,
                label: 'Home',
                compact: isLandscapePhone,
                active: selectedIndex == 0,
                onTap: () => onTap(0),
              ),
              _NavItem(
                icon: Icons.map_outlined,
                label: 'Map',
                compact: isLandscapePhone,
                active: selectedIndex == 1,
                onTap: () => onTap(1),
              ),
              _NavItem(
                icon: Icons.favorite,
                label: 'Wishlist',
                compact: isLandscapePhone,
                active: selectedIndex == 2,
                onTap: () => onTap(2),
              ),
              _NavItem(
                icon: Icons.person,
                label: 'Profile',
                compact: isLandscapePhone,
                active: selectedIndex == 3,
                onTap: () => onTap(3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool compact;
  final bool active;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    this.compact = false,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final secondaryTextColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: active ? tsPrimaryGreen : secondaryTextColor,
            size: compact ? 22 : 24,
          ),
          SizedBox(height: compact ? 2 : 4),
          Text(
            label,
            style: TextStyle(
              color: active ? tsPrimaryGreen : secondaryTextColor,
              fontSize: compact ? 11 : 12,
              fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
