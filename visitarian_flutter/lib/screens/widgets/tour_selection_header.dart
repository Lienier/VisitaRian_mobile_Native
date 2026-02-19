import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class TourSelectionHeader extends StatelessWidget {
  final ValueChanged<String> onSearchChanged;

  const TourSelectionHeader({super.key, required this.onSearchChanged});

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    final secondaryTextColor = Theme.of(context).colorScheme.onSurfaceVariant;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? scheme.surfaceContainerHigh : scheme.surface;

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
        final screenSize = MediaQuery.sizeOf(context);
        final isLandscapePhone =
            screenSize.width >= 640 && screenSize.height < 560;
        final titleFontSize = isLandscapePhone ? 24.0 : 32.0;
        final subtitleFontSize = isLandscapePhone ? 14.0 : 16.0;
        final containerPadding = isLandscapePhone ? 12.0 : 16.0;
        final gapAfterSubtitle = isLandscapePhone ? 12.0 : 20.0;

        return Padding(
          padding: EdgeInsets.all(containerPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                discoverTitle.isEmpty ? 'Discover' : discoverTitle,
                style: TextStyle(
                  fontSize: titleFontSize,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                discoverSubtitle.isEmpty
                    ? 'Find your perfect destination'
                    : discoverSubtitle,
                style: TextStyle(
                  fontSize: subtitleFontSize,
                  color: secondaryTextColor,
                ),
              ),
              SizedBox(height: gapAfterSubtitle),
              Container(
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? scheme.outline.withValues(alpha: 0.45)
                        : scheme.outline.withValues(alpha: 0.2),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.35 : 0.1,
                      ),
                      blurRadius: isDark ? 10 : 4,
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
