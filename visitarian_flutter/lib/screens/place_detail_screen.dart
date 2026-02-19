import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:visitarian_flutter/screens/xr_tour_player_screen.dart';

class PlaceDetailScreen extends StatelessWidget {
  final Place place;
  final String? placeId;

  const PlaceDetailScreen({super.key, required this.place, this.placeId});

  @override
  Widget build(BuildContext context) {
    const pillGreen = Color(0xFF1B5A45);

    if (placeId != null) {
      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('favoriteStats')
            .doc(placeId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Scaffold(
              backgroundColor: Theme.of(context).colorScheme.surface,
              body: const Center(child: CircularProgressIndicator()),
            );
          }

          var favoriteCount = 0;
          if (snapshot.hasData &&
              snapshot.data != null &&
              snapshot.data!.exists) {
            final data = snapshot.data!.data() ?? {};
            favoriteCount = (data['count'] is num)
                ? (data['count'] as num).toInt()
                : 0;
          }

          return _buildDetailScreen(
            context,
            place.copyWith(favoriteCount: favoriteCount),
            pillGreen,
          );
        },
      );
    }

    return _buildDetailScreen(context, place, pillGreen);
  }

  Widget _buildDetailScreen(
    BuildContext context,
    Place place,
    Color pillGreen,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final height = constraints.maxHeight;
            final isDesktop = width >= 1000;
            final isLandscapePhone = width >= 640 && height < 560;
            final useSplitLayout = isDesktop || isLandscapePhone;
            final pagePadding = isDesktop
                ? 24.0
                : isLandscapePhone
                ? 12.0
                : 18.0;

            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1360),
                child: Padding(
                  padding: EdgeInsets.all(pagePadding),
                  child: useSplitLayout
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              flex: 6,
                              child: _buildHeroCard(
                                context,
                                place,
                                isDesktop: true,
                              ),
                            ),
                            SizedBox(width: isLandscapePhone ? 12 : 18),
                            Expanded(
                              flex: 5,
                              child: _buildInfoCard(
                                context,
                                place,
                                pillGreen,
                                isDesktop: !isLandscapePhone,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            _buildHeroCard(context, place, isDesktop: false),
                            const SizedBox(height: 12),
                            Expanded(
                              child: _buildInfoCard(
                                context,
                                place,
                                pillGreen,
                                isDesktop: false,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeroCard(
    BuildContext context,
    Place place, {
    required bool isDesktop,
  }) {
    return SizedBox(
      width: double.infinity,
      height: isDesktop ? double.infinity : 260,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            Positioned.fill(child: _PlaceImage(path: place.imagePath)),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.15),
                      Colors.black.withValues(alpha: 0.0),
                      Colors.black.withValues(alpha: 0.55),
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              top: 12,
              child: _RoundIconButton(
                icon: Icons.arrow_back,
                onTap: () => Navigator.pop(context),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    place.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on,
                        size: 14,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          place.location,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(
    BuildContext context,
    Place place,
    Color pillGreen, {
    required bool isDesktop,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.surfaceContainerHigh
            : colorScheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark
              ? colorScheme.outline.withValues(alpha: 0.45)
              : colorScheme.outline.withValues(alpha: 0.14),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.32 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          isDesktop ? 22 : 18,
          isDesktop ? 20 : 16,
          isDesktop ? 22 : 18,
          isDesktop ? 20 : 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _StatCard(
                  label: 'Distance',
                  value: place.distanceKm.toStringAsFixed(0),
                  suffix: 'Km',
                ),
                _StatCard(
                  label: 'Favorites',
                  value: place.favoriteCount.toString(),
                  suffix: '',
                ),
                _StatCard(
                  label: 'Weather',
                  value: place.weatherCondition,
                  suffix: '',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Description',
              style: TextStyle(
                fontSize: isDesktop ? 14 : 12,
                fontWeight: FontWeight.w800,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  place.description,
                  style: TextStyle(
                    fontSize: isDesktop ? 14 : 12.5,
                    height: 1.4,
                    color: colorScheme.onSurface.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: pillGreen,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                onPressed: () => _openTour(context, place),
                child: const Text(
                  'Explore',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openTour(BuildContext context, Place place) async {
    if (placeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tour is unavailable for this place.')),
      );
      return;
    }

    try {
      final placeDoc = await FirebaseFirestore.instance
          .collection('places')
          .doc(placeId)
          .get();

      final tourId = (placeDoc.data()?['tourId'] ?? '').toString().trim();

      if (tourId.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No XR tour has been created for this place yet.'),
          ),
        );
        return;
      }

      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => XrTourPlayerScreen(
            tourId: tourId,
            placeTitle: place.title,
            showEntryFlow: true,
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to open XR tour: $e')));
    }
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _RoundIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const pillGreen = Color(0xFF1B5A45);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: pillGreen.withValues(alpha: 0.75),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String suffix;

  const _StatCard({
    required this.label,
    required this.value,
    required this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final valueColor = isDark ? colorScheme.onSurface : const Color(0xFF1B5A45);

    return Container(
      width: 96,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.surfaceContainerHighest
            : colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? colorScheme.outline.withValues(alpha: 0.5)
              : const Color(0xFF1B5A45).withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: valueColor,
                ),
              ),
              if (suffix.isNotEmpty) ...[
                const SizedBox(width: 2),
                Text(
                  suffix,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: valueColor,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class Place {
  final String title;
  final String location;
  final String imagePath;
  final double distanceKm;
  final int favoriteCount;
  final String weatherCondition;
  final String description;

  const Place({
    required this.title,
    required this.location,
    required this.imagePath,
    required this.distanceKm,
    required this.favoriteCount,
    required this.weatherCondition,
    required this.description,
  });

  Place copyWith({
    String? title,
    String? location,
    String? imagePath,
    double? distanceKm,
    int? favoriteCount,
    String? weatherCondition,
    String? description,
  }) {
    return Place(
      title: title ?? this.title,
      location: location ?? this.location,
      imagePath: imagePath ?? this.imagePath,
      distanceKm: distanceKm ?? this.distanceKm,
      favoriteCount: favoriteCount ?? this.favoriteCount,
      weatherCondition: weatherCondition ?? this.weatherCondition,
      description: description ?? this.description,
    );
  }
}

class _PlaceImage extends StatelessWidget {
  final String path;

  const _PlaceImage({required this.path});

  bool _looksLikeNetwork(String p) {
    return p.startsWith('http://') || p.startsWith('https://');
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = Theme.of(context).colorScheme.surfaceContainerHighest;

    if (_looksLikeNetwork(path) && path != 'test') {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return ColoredBox(
            color: placeholder,
            child: Center(child: Icon(Icons.broken_image)),
          );
        },
      );
    }

    return ColoredBox(
      color: placeholder,
      child: Center(child: Icon(Icons.broken_image)),
    );
  }
}
