import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:visitarian_flutter/core/services/services.dart';
import 'package:visitarian_flutter/screens/place_detail_screen.dart';
import 'package:visitarian_flutter/screens/profile_setup_screen.dart';
import 'package:visitarian_flutter/screens/widgets/tour_place_cards.dart';
import 'package:visitarian_flutter/screens/widgets/tour_profile_content.dart';
import 'package:visitarian_flutter/screens/widgets/tour_selection_bottom_nav.dart';
import 'package:visitarian_flutter/screens/widgets/tour_selection_header.dart';

class TourSelectionScreen extends StatefulWidget {
  const TourSelectionScreen({super.key});

  @override
  State<TourSelectionScreen> createState() => _TourSelectionScreenState();
}

class _TourSelectionScreenState extends State<TourSelectionScreen> {
  int _tabIndex = 0; // 0 = Home, 1 = Favorites, 2 = Profile
  String _query = '';
  String _debouncedQuery = '';
  final _auth = AuthService();
  Timer? _searchDebounce;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _profileStream;
  bool _homeLoading = true;
  bool _homeRefreshing = false;
  String? _homeError;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _cachedPlaces = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _cachedPopularPlaces = [];
  Set<String> _cachedFavorites = <String>{};

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _profileStream = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots();
      _refreshHomeData(initialLoad: true);
    } else {
      _homeLoading = false;
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  bool _matchesQuery(String title) {
    final q = _debouncedQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    return title.toLowerCase().contains(q);
  }

  void _onSearchChanged(String value) {
    _query = value;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() => _debouncedQuery = _query);
    });
  }

  Future<void> _refreshHomeData({bool initialLoad = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _homeLoading = false;
        _homeRefreshing = false;
      });
      return;
    }

    if (!initialLoad && _homeRefreshing) return;
    if (!mounted) return;
    setState(() {
      if (initialLoad) {
        _homeLoading = true;
      } else {
        _homeRefreshing = true;
      }
    });

    try {
      final results = await Future.wait([
        FirebaseFirestore.instance.collection('places').limit(50).get(),
        FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
        FirebaseFirestore.instance
            .collection('favoriteStats')
            .orderBy('count', descending: true)
            .limit(5)
            .get(),
      ]);

      final placesSnapshot = results[0] as QuerySnapshot<Map<String, dynamic>>;
      final userSnapshot = results[1] as DocumentSnapshot<Map<String, dynamic>>;
      final favoriteStatsSnapshot =
          results[2] as QuerySnapshot<Map<String, dynamic>>;

      final placesById = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{
        for (final place in placesSnapshot.docs) place.id: place,
      };
      final popularPlaces = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      for (final stat in favoriteStatsSnapshot.docs) {
        final place = placesById[stat.id];
        if (place != null) {
          popularPlaces.add(place);
        }
      }

      final favoritesList =
          userSnapshot.data()?['favorites'] as List<dynamic>? ?? [];
      final favoritesSet = Set<String>.from(
        favoritesList.map((e) => e.toString()),
      );

      if (!mounted) return;
      setState(() {
        _cachedPlaces = placesSnapshot.docs;
        _cachedPopularPlaces = popularPlaces;
        _cachedFavorites = favoritesSet;
        _homeLoading = false;
        _homeRefreshing = false;
        _homeError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _homeLoading = false;
        _homeRefreshing = false;
        _homeError = 'Failed to refresh destinations.';
      });
    }
  }

  Future<void> _toggleFavorite(String placeId, bool isFav) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      if (isFav) {
        _cachedFavorites.remove(placeId);
      } else {
        _cachedFavorites.add(placeId);
      }
    });

    try {
      final userDoc = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);
      final statsDoc = FirebaseFirestore.instance
          .collection('favoriteStats')
          .doc(placeId);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final userSnapshot = await transaction.get(userDoc);
        final statsSnapshot = await transaction.get(statsDoc);

        final currentFavorites = List<String>.from(
          (userSnapshot.data()?['favorites'] as List<dynamic>? ?? const []).map(
            (e) => e.toString(),
          ),
        );

        if (isFav) {
          currentFavorites.remove(placeId);
        } else if (!currentFavorites.contains(placeId)) {
          currentFavorites.add(placeId);
        }

        transaction.set(userDoc, {
          'favorites': currentFavorites,
        }, SetOptions(merge: true));

        final currentCount = (statsSnapshot.data()?['count'] as int?) ?? 0;
        final newCount = isFav ? (currentCount - 1) : (currentCount + 1);

        if (newCount > 0) {
          transaction.set(statsDoc, {
            'count': newCount,
          }, SetOptions(merge: true));
        } else {
          transaction.delete(statsDoc);
        }
      });
      _refreshHomeData();
    } catch (e) {
      await _refreshHomeData();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error updating favorite: $e')));
    }
  }

  Future<void> _logout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Logout'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (shouldLogout != true) return;

    try {
      // Just sign out - AuthGate StreamBuilder will automatically detect auth state change and rebuild
      await _auth.signOut();
      // No manual navigation needed
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error logging out: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 1000;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Row(
          children: [
            if (isDesktop) _buildDesktopNavigationRail(),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1280),
                  child: Column(
                    children: [
                      if (_tabIndex != 2)
                        TourSelectionHeader(onSearchChanged: _onSearchChanged),
                      Expanded(child: _buildContent()),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: isDesktop
          ? null
          : TourSelectionBottomNav(
              selectedIndex: _tabIndex,
              onTap: _onTabChanged,
            ),
    );
  }

  void _onTabChanged(int index) {
    setState(() {
      _tabIndex = index;
      _query = '';
      _debouncedQuery = '';
    });
  }

  Widget _buildDesktopNavigationRail() {
    return NavigationRail(
      selectedIndex: _tabIndex,
      onDestinationSelected: _onTabChanged,
      labelType: NavigationRailLabelType.all,
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: Text('Home'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.favorite_border),
          selectedIcon: Icon(Icons.favorite),
          label: Text('Wishlist'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: Text('Profile'),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_tabIndex == 0) {
      return _buildHomeContent();
    } else if (_tabIndex == 1) {
      return _buildWishlistContent();
    } else {
      return _buildProfileContent();
    }
  }

  Widget _buildHomeContent() {
    final textColor = Theme.of(context).colorScheme.onSurface;
    if (_homeLoading && _cachedPlaces.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final filteredDocs = _cachedPlaces
        .where((doc) => _matchesQuery((doc.data()['title'] ?? '').toString()))
        .toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final isLandscapePhone = width >= 640 && height < 560;
        final isDesktop = width >= 1000;
        final horizontalPadding = isDesktop
            ? 24.0
            : isLandscapePhone
            ? 12.0
            : 16.0;
        final popularHeight = isDesktop
            ? 240.0
            : isLandscapePhone
            ? 170.0
            : 200.0;
        final popularCardWidth = isDesktop
            ? 240.0
            : isLandscapePhone
            ? 180.0
            : 160.0;
        final crossAxisCount = width >= 1200
            ? 4
            : width >= 900
            ? 3
            : isLandscapePhone
            ? 3
            : 2;

        return Stack(
          children: [
            CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: horizontalPadding,
                        ),
                        child: Text(
                          'Popular Destination',
                          style: TextStyle(
                            fontSize: isLandscapePhone ? 18 : 20,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: popularHeight,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: EdgeInsets.symmetric(
                            horizontal: horizontalPadding,
                          ),
                          itemCount: _cachedPopularPlaces.length,
                          itemBuilder: (context, index) {
                            final doc = _cachedPopularPlaces[index];
                            final data = doc.data();
                            return PopularPlaceCard(
                              width: popularCardWidth,
                              title: (data['title'] ?? '').toString(),
                              location: (data['location'] ?? '').toString(),
                              imageUrl: (data['imageUrl'] ?? '').toString(),
                              isFavorite: _cachedFavorites.contains(doc.id),
                              onToggleFavorite: () => _toggleFavorite(
                                doc.id,
                                _cachedFavorites.contains(doc.id),
                              ),
                              onTap: () => _openPlaceDetail(doc.id, data),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                    ),
                    child: Text(
                      'Discover Places',
                      style: TextStyle(
                        fontSize: isLandscapePhone ? 18 : 20,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: isDesktop
                          ? 0.95
                          : isLandscapePhone
                          ? 0.98
                          : 0.8,
                    ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final doc = filteredDocs[index];
                      final data = doc.data();
                      return DiscoverPlaceCard(
                        title: (data['title'] ?? '').toString(),
                        location: (data['location'] ?? '').toString(),
                        imageUrl: (data['imageUrl'] ?? '').toString(),
                        isFavorite: _cachedFavorites.contains(doc.id),
                        onToggleFavorite: () => _toggleFavorite(
                          doc.id,
                          _cachedFavorites.contains(doc.id),
                        ),
                        onTap: () => _openPlaceDetail(doc.id, data),
                      );
                    }, childCount: filteredDocs.length),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
              ],
            ),
            if (_homeRefreshing)
              const Positioned(
                top: 8,
                right: 16,
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            if (_homeError != null && _cachedPlaces.isEmpty)
              Center(
                child: Text(
                  _homeError!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
          ],
        );
      },
    );
  }

  void _openPlaceDetail(String placeId, Map<String, dynamic> data) {
    final imageUrl = (data['imageUrl'] ?? '').toString();
    final place = Place(
      title: (data['title'] ?? '').toString(),
      location: (data['location'] ?? '').toString(),
      imagePath: imageUrl.isNotEmpty
          ? imageUrl
          : 'assets/images/onboarding/slide1.JPG',
      distanceKm: (data['distanceKm'] is num)
          ? (data['distanceKm'] as num).toDouble()
          : 0.0,
      favoriteCount: 0,
      weatherCondition: (data['weatherCondition'] ?? 'Unknown').toString(),
      description: (data['description'] ?? 'No description available')
          .toString(),
    );

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlaceDetailScreen(place: place, placeId: placeId),
      ),
    );
  }

  Widget _buildWishlistContent() {
    final secondaryTextColor = Theme.of(context).colorScheme.onSurfaceVariant;
    final favoritePlaces = _cachedPlaces
        .where((doc) => _cachedFavorites.contains(doc.id))
        .toList(growable: false);

    if (_homeLoading && favoritePlaces.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (favoritePlaces.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.favorite_border, size: 64, color: secondaryTextColor),
            const SizedBox(height: 16),
            Text(
              'No favorites yet',
              style: TextStyle(fontSize: 18, color: secondaryTextColor),
            ),
            const SizedBox(height: 8),
            Text(
              'Start adding places to your wishlist!',
              style: TextStyle(fontSize: 14, color: secondaryTextColor),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final isLandscapePhone = width >= 640 && height < 560;
        final isDesktop = width >= 1000;
        final crossAxisCount = width >= 1200
            ? 4
            : width >= 900
            ? 3
            : isLandscapePhone
            ? 3
            : 2;

        return Padding(
          padding: EdgeInsets.all(
            isDesktop
                ? 24.0
                : isLandscapePhone
                ? 12.0
                : 16.0,
          ),
          child: GridView.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: isDesktop
                  ? 0.95
                  : isLandscapePhone
                  ? 0.98
                  : 0.8,
            ),
            itemCount: favoritePlaces.length,
            itemBuilder: (context, index) {
              final doc = favoritePlaces[index];
              final data = doc.data();
              return DiscoverPlaceCard(
                title: (data['title'] ?? '').toString(),
                location: (data['location'] ?? '').toString(),
                imageUrl: (data['imageUrl'] ?? '').toString(),
                isFavorite: true,
                onToggleFavorite: () => _toggleFavorite(doc.id, true),
                onTap: () => _openPlaceDetail(doc.id, data),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildProfileContent() {
    final user = FirebaseAuth.instance.currentUser;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: Center(
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _profileStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const CircularProgressIndicator();
              }

              final userData = snapshot.data?.data();
              final username = (userData?['username'] ?? 'User') as String;
              final photoUrl = (userData?['photoUrl'] ?? '') as String;

              return TourProfileContent(
                username: username,
                email: user?.email ?? '',
                photoUrl: photoUrl,
                onEditProfile: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ProfileSetupScreen(),
                    ),
                  );
                },
                onLogout: _logout,
              );
            },
          ),
        ),
      ),
    );
  }
}
