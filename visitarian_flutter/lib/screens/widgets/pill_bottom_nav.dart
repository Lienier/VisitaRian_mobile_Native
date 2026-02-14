import 'package:flutter/material.dart';

class PillBottomNav extends StatelessWidget {
  final int activeIndex;
  final ValueChanged<int> onChange;

  const PillBottomNav({
    required this.activeIndex,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 62,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 240, 240, 240),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color.fromARGB(255, 0, 0, 0), width: 1),
      ),
      child: Row(
        children: [
          NavItem(
            label: 'Home',
            icon: Icons.home_outlined,
            selected: activeIndex == 0,
            onTap: () => onChange(0),
          ),
          const SizedBox(width: 10),
          NavItem(
            label: 'Favorites',
            icon: Icons.favorite_border,
            selected: activeIndex == 1,
            onTap: () => onChange(1),
          ),
          const SizedBox(width: 10),
          NavItem(
            label: 'Profile',
            icon: Icons.person_outline,
            selected: activeIndex == 2,
            onTap: () => onChange(2),
          ),
        ],
      ),
    );
  }
}

class NavItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const NavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const pillGreen = Color(0xFF1B5A45);

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? pillGreen : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: selected ? Colors.white : Colors.black87, size: 20),
              if (selected) ...[
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
