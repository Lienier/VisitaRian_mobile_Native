import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import 'profile_setup_screen.dart';
import 'place_detail_screen.dart';
import 'widgets/tour_place_cards.dart';
import 'widgets/tour_profile_content.dart';
import 'widgets/tour_selection_bottom_nav.dart';
import 'widgets/tour_selection_header.dart';

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
  Timer? _homeRefreshTimer;
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
      _homeRefreshTimer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => _refreshHomeData(),
      );
    } else {
      _homeLoading = false;
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _homeRefreshTimer?.cancel();
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

      if (isFav) {
        // Remove from favorites
        await userDoc.update({
          'favorites': FieldValue.arrayRemove([placeId]),
        });
        // Decrement count in favoriteStats - use transaction to handle non-existent doc
        await FirebaseFirestore.instance.runTransaction((transaction) async {
          final snapshot = await transaction.get(statsDoc);
          if (snapshot.exists) {
            final currentCount = snapshot.data()?['count'] as int? ?? 0;
            final newCount = (currentCount - 1)
                .clamp(0, double.infinity)
                .toInt();
            if (newCount > 0) {
              transaction.update(statsDoc, {'count': newCount});
            } else {
              // Delete the document if count becomes 0
              transaction.delete(statsDoc);
            }
          }
        });
      } else {
        // Add to favorites
        await userDoc.update({
          'favorites': FieldValue.arrayUnion([placeId]),
        });
        // Increment count in favoriteStats - use transaction to handle non-existent doc
        await FirebaseFirestore.instance.runTransaction((transaction) async {
          final snapshot = await transaction.get(statsDoc);
          if (snapshot.exists) {
            final currentCount = snapshot.data()?['count'] as int? ?? 0;
            transaction.update(statsDoc, {'count': currentCount + 1});
          } else {
            // Create new document with count = 1
            transaction.set(statsDoc, {'count': 1});
          }
        });
      }
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
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            if (_tabIndex != 2)
              TourSelectionHeader(onSearchChanged: _onSearchChanged),

            // Content
            Expanded(child: _buildContent()),
          ],
        ),
      ),
      bottomNavigationBar: TourSelectionBottomNav(
        selectedIndex: _tabIndex,
        onTap: (index) => setState(() {
          _tabIndex = index;
          _query = '';
          _debouncedQuery = '';
        }),
      ),
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

    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text(
                      'Popular Destination',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 200,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _cachedPopularPlaces.length,
                      itemBuilder: (context, index) {
                        final doc = _cachedPopularPlaces[index];
                        final data = doc.data();
                        return PopularPlaceCard(
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
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  'Discover Places',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.8,
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
            child: Text(_homeError!, style: const TextStyle(color: Colors.red)),
          ),
      ],
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
      temperatureC: (data['temperatureC'] is num)
          ? (data['temperatureC'] as num).toDouble()
          : 0.0,
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

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.8,
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
  }

  Widget _buildProfileContent() {
    final user = FirebaseAuth.instance.currentUser;
    return Center(
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
                MaterialPageRoute(builder: (_) => const ProfileSetupScreen()),
              );
            },
            onLogout: _logout,
          );
        },
      ),
    );
  }
}
