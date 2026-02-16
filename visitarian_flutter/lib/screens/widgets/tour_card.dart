import 'package:flutter/material.dart';

class TourCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String imageUrl;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onTap;

  const TourCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const pillGreen = Color(0xFF1B5A45);

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            children: [
              Positioned.fill(
                child: (imageUrl.isNotEmpty && imageUrl != 'test')
                    ? Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: Colors.black12,
                            child: const Center(
                              child: Icon(Icons.broken_image_outlined),
                            ),
                          );
                        },
                      )
                    : Container(
                        color: Colors.black12,
                        child: const Center(
                          child: Icon(Icons.image_not_supported_outlined),
                        ),
                      ),
              ),

              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.0),
                        Colors.black.withValues(alpha: 0.55),
                      ],
                    ),
                  ),
                ),
              ),

              Positioned(
                left: 18,
                bottom: 18,
                right: 60,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              Positioned(
                right: 14,
                top: 14,
                child: GestureDetector(
                  onTap: onToggleFavorite,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: pillGreen.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isFavorite ? Icons.favorite : Icons.favorite_border,
                      color: isFavorite ? Colors.redAccent : Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
