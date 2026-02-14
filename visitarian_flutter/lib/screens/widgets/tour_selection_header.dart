import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class TourSelectionHeader extends StatelessWidget {
  final ValueChanged<String> onSearchChanged;

  const TourSelectionHeader({super.key, required this.onSearchChanged});

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    final secondaryTextColor = Theme.of(context).colorScheme.onSurfaceVariant;
    final cardColor = Theme.of(context).colorScheme.surface;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('appConfig')
          .doc('tourSelectionHeader')
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? const <String, dynamic>{};
        final discoverTitle = (data['discoverTitle'] ?? 'Discover')
            .toString()
            .trim();
        final discoverSubtitle =
            (data['discoverSubtitle'] ?? 'Find your perfect destination')
                .toString()
                .trim();
        final searchHint = (data['searchHint'] ?? 'Search destinations...')
            .toString()
            .trim();

        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                discoverTitle.isEmpty ? 'Discover' : discoverTitle,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                discoverSubtitle.isEmpty
                    ? 'Find your perfect destination'
                    : discoverSubtitle,
                style: TextStyle(fontSize: 16, color: secondaryTextColor),
              ),
              const SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TextField(
                  onChanged: onSearchChanged,
                  decoration: InputDecoration(
                    hintText: searchHint.isEmpty
                        ? 'Search destinations...'
                        : searchHint,
                    hintStyle: TextStyle(color: secondaryTextColor),
                    prefixIcon: Icon(Icons.search, color: secondaryTextColor),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
