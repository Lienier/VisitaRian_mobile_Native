import 'package:flutter/material.dart';

class PlaceSearchBar extends StatelessWidget {
  final String hintText;
  final ValueChanged<String> onChanged;

  const PlaceSearchBar({
    super.key,
    required this.hintText,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const pillGreen = Color(0xFF1B5A45);

    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              onChanged: onChanged,
              decoration: InputDecoration(
                hintText: hintText,
                border: InputBorder.none,
                hintStyle: TextStyle(
                  color: Colors.black.withValues(alpha: 0.45),
                  fontSize: 13,
                ),
              ),
            ),
          ),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: pillGreen.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.search, color: pillGreen, size: 20),
          ),
        ],
      ),
    );
  }
}
