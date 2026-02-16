import 'package:flutter/material.dart';

class PopularPlaceCard extends StatelessWidget {
  final String title;
  final String location;
  final String imageUrl;
  final bool isFavorite;
  final double width;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;

  const PopularPlaceCard({
    super.key,
    required this.title,
    required this.location,
    required this.imageUrl,
    required this.isFavorite,
    this.width = 160,
    required this.onTap,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    final secondaryTextColor = Theme.of(context).colorScheme.onSurfaceVariant;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? scheme.surfaceContainerHigh : scheme.surface;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: cardColor,
          border: Border.all(
            color: isDark
                ? scheme.outline.withValues(alpha: 0.45)
                : scheme.outline.withValues(alpha: 0.12),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.1),
              blurRadius: isDark ? 10 : 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                        child: _cardImage(imageUrl),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.9),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          onPressed: onToggleFavorite,
                          icon: Icon(
                            isFavorite ? Icons.favorite : Icons.favorite_border,
                            color: isFavorite ? Colors.red : Colors.grey,
                            size: 16,
                          ),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      location,
                      style: TextStyle(fontSize: 12, color: secondaryTextColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DiscoverPlaceCard extends StatelessWidget {
  final String title;
  final String location;
  final String imageUrl;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;

  const DiscoverPlaceCard({
    super.key,
    required this.title,
    required this.location,
    required this.imageUrl,
    required this.isFavorite,
    required this.onTap,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    final secondaryTextColor = Theme.of(context).colorScheme.onSurfaceVariant;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? scheme.surfaceContainerHigh : scheme.surface;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: cardColor,
          border: Border.all(
            color: isDark
                ? scheme.outline.withValues(alpha: 0.45)
                : scheme.outline.withValues(alpha: 0.12),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.1),
              blurRadius: isDark ? 10 : 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                        child: _cardImage(imageUrl),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.9),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          onPressed: onToggleFavorite,
                          icon: Icon(
                            isFavorite ? Icons.favorite : Icons.favorite_border,
                            color: isFavorite ? Colors.red : Colors.grey,
                            size: 14,
                          ),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      location,
                      style: TextStyle(fontSize: 10, color: secondaryTextColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _cardImage(String imageUrl) {
  if (imageUrl.isNotEmpty) {
    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) {
        return Image.asset(
          'assets/images/onboarding/slide1.JPG',
          fit: BoxFit.cover,
        );
      },
    );
  }
  return Image.asset('assets/images/onboarding/slide1.JPG', fit: BoxFit.cover);
}
