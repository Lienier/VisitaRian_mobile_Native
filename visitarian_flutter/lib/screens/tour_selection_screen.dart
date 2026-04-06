import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visitarian_flutter/core/services/services.dart';
import 'package:visitarian_flutter/screens/place_detail_screen.dart';
import 'package:visitarian_flutter/screens/profile_setup_screen.dart';
import 'package:visitarian_flutter/screens/widgets/tour_place_cards.dart';
import 'package:visitarian_flutter/screens/widgets/tour_profile_content.dart';
import 'package:visitarian_flutter/screens/widgets/tour_selection_bottom_nav.dart';
import 'package:visitarian_flutter/screens/widgets/tour_selection_header.dart';
import 'package:visitarian_flutter/screens/widgets/tour_user_map_content.dart';

class TourSelectionScreen extends StatefulWidget {
  const TourSelectionScreen({super.key});

  @override
  State<TourSelectionScreen> createState() => _TourSelectionScreenState();
}

class _TourSelectionScreenState extends State<TourSelectionScreen> {
  int _tabIndex = 0; // 0 = Home, 1 = Map, 2 = Favorites, 3 = Profile
  String _query = '';
  String _debouncedQuery = '';
  final _auth = AuthService();
  static const _homeCacheVersion = 'v1';
  Timer? _searchDebounce;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _profileStream;
  bool _homeLoading = true;
  bool _homeRefreshing = false;
  String? _homeError;
  List<_CachedPlace> _cachedPlaces = [];
  List<_CachedPlace> _cachedPopularPlaces = [];
  Map<String, int> _favoriteCountsByPlaceId = <String, int>{};
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
      _loadHomeCacheThenRefresh(user.uid);
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

  String _homeCacheKey(String uid) =>
      'tour_home_cache_${_homeCacheVersion}_$uid';

  Future<void> _loadHomeCacheThenRefresh(String uid) async {
    await _loadHomeCache(uid);
    if (!mounted) return;
    unawaited(_refreshHomeData(initialLoad: true));
  }

  Future<void> _loadHomeCache(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_homeCacheKey(uid));
      if (raw == null || raw.isEmpty) return;

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;

      final rawPlaces = decoded['places'] as List<dynamic>? ?? const [];
      final rawPopularIds =
          decoded['popularPlaceIds'] as List<dynamic>? ?? const [];
      final rawFavorites = decoded['favorites'] as List<dynamic>? ?? const [];
      final rawFavoriteCounts =
          decoded['favoriteCountsByPlaceId'] as Map<String, dynamic>? ??
          const {};

      final places = rawPlaces
          .whereType<Map<String, dynamic>>()
          .map(_cachedPlaceFromMap)
          .where((p) => p.id.isNotEmpty)
          .toList(growable: false);
      final placesById = {for (final p in places) p.id: p};
      final popularPlaces = rawPopularIds
          .map((e) => e.toString())
          .map((id) => placesById[id])
          .whereType<_CachedPlace>()
          .toList(growable: false);
      final favorites = rawFavorites
          .map((e) => e.toString())
          .where((id) => id.isNotEmpty)
          .toSet();
      final favoriteCounts = <String, int>{};
      for (final entry in rawFavoriteCounts.entries) {
        final count = (entry.value is num)
            ? (entry.value as num).toInt()
            : int.tryParse('${entry.value}');
        if (count != null && count > 0 && entry.key.isNotEmpty) {
          favoriteCounts[entry.key] = count;
        }
      }
      final computedPopular = _buildPopularPlaces(places, favoriteCounts);

      if (!mounted) return;
      setState(() {
        _cachedPlaces = places;
        _cachedPopularPlaces = computedPopular.isEmpty
            ? popularPlaces
            : computedPopular;
        _favoriteCountsByPlaceId = favoriteCounts;
        _cachedFavorites = favorites;
        _homeLoading = false;
      });
      final toWarm = computedPopular.isEmpty ? popularPlaces : computedPopular;
      unawaited(_warmVisibleImageCache(places: places, popularPlaces: toWarm));
    } catch (_) {
      // Ignore cache decode failures and continue with network refresh.
    }
  }

  _CachedPlace _cachedPlaceFromMap(Map<String, dynamic> item) {
    final id = (item['id'] ?? '').toString();
    final data = item['data'];
    if (id.isEmpty || data is! Map<String, dynamic>) {
      return const _CachedPlace(id: '', data: <String, dynamic>{});
    }
    return _CachedPlace(id: id, data: Map<String, dynamic>.from(data));
  }

  Map<String, dynamic> _placeDataForCache(Map<String, dynamic> data) {
    double readDouble(dynamic value) {
      if (value is num) return value.toDouble();
      final parsed = double.tryParse('$value');
      return parsed ?? 0.0;
    }

    return {
      'title': (data['title'] ?? '').toString(),
      'location': (data['location'] ?? '').toString(),
      'imageUrl': (data['imageUrl'] ?? '').toString(),
      'distanceKm': readDouble(data['distanceKm']),
      'weatherCondition': (data['weatherCondition'] ?? 'Unknown').toString(),
      'description': (data['description'] ?? 'No description available')
          .toString(),
      'tourId': (data['tourId'] ?? '').toString(),
    };
  }

  Future<void> _persistHomeCache(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = <String, dynamic>{
        'savedAt': DateTime.now().toIso8601String(),
        'places': _cachedPlaces
            .where((p) => p.id.isNotEmpty)
            .map((p) => {'id': p.id, 'data': p.data})
            .toList(growable: false),
        'popularPlaceIds': _cachedPopularPlaces
            .where((p) => p.id.isNotEmpty)
            .map((p) => p.id)
            .toList(growable: false),
        'favoriteCountsByPlaceId': _favoriteCountsByPlaceId,
        'favorites': _cachedFavorites.toList(growable: false),
      };
      await prefs.setString(_homeCacheKey(uid), jsonEncode(payload));
    } catch (_) {
      // Ignore cache write failures.
    }
  }

  Future<Map<String, int>> _fetchFavoriteCountsForPlaces(
    List<_CachedPlace> places,
  ) async {
    final ids = places
        .map((p) => p.id)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (ids.isEmpty) return <String, int>{};

    const chunkSize = 30;
    final counts = <String, int>{};
    for (var i = 0; i < ids.length; i += chunkSize) {
      final chunk = ids.sublist(i, min(i + chunkSize, ids.length));
      final snapshot = await FirebaseFirestore.instance
          .collection('favoriteStats')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snapshot.docs) {
        final count = (doc.data()['count'] as num?)?.toInt() ?? 0;
        if (count > 0) {
          counts[doc.id] = count;
        }
      }
    }
    return counts;
  }

  List<_CachedPlace> _buildPopularPlaces(
    List<_CachedPlace> places,
    Map<String, int> counts,
  ) {
    final ranked = places
        .where((place) => (counts[place.id] ?? 0) > 0)
        .toList(growable: false);
    ranked.sort((a, b) {
      final countCompare = (counts[b.id] ?? 0).compareTo(counts[a.id] ?? 0);
      if (countCompare != 0) return countCompare;
      final titleA = (a.data['title'] ?? '').toString().toLowerCase();
      final titleB = (b.data['title'] ?? '').toString().toLowerCase();
      return titleA.compareTo(titleB);
    });
    return ranked.take(5).toList(growable: false);
  }

  void _applyLocalFavoriteDelta(String placeId, {required bool isFavorite}) {
    final current = _favoriteCountsByPlaceId[placeId] ?? 0;
    final next = isFavorite ? current + 1 : max(0, current - 1);
    if (next > 0) {
      _favoriteCountsByPlaceId[placeId] = next;
    } else {
      _favoriteCountsByPlaceId.remove(placeId);
    }
    _cachedPopularPlaces = _buildPopularPlaces(
      _cachedPlaces,
      _favoriteCountsByPlaceId,
    );
  }

  Future<void> _warmVisibleImageCache({
    required List<_CachedPlace> places,
    required List<_CachedPlace> popularPlaces,
  }) async {
    if (!mounted) return;
    final urls = <String>{
      ...popularPlaces
          .map((p) => (p.data['imageUrl'] ?? '').toString().trim())
          .where((u) => u.startsWith('http://') || u.startsWith('https://'))
          .take(6),
      ...places
          .map((p) => (p.data['imageUrl'] ?? '').toString().trim())
          .where((u) => u.startsWith('http://') || u.startsWith('https://'))
          .take(10),
    };

    for (final url in urls) {
      if (!mounted) return;
      try {
        await precacheImage(CachedNetworkImageProvider(url), context);
      } catch (_) {
        // Best-effort prefetch only.
      }
    }
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
        _homeLoading = _cachedPlaces.isEmpty;
      } else {
        _homeRefreshing = true;
      }
    });

    try {
      final results = await Future.wait([
        FirebaseFirestore.instance.collection('places').limit(50).get(),
        FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
      ]);

      final placesSnapshot = results[0] as QuerySnapshot<Map<String, dynamic>>;
      final userSnapshot = results[1] as DocumentSnapshot<Map<String, dynamic>>;

      final places = placesSnapshot.docs
          .map(
            (place) => _CachedPlace(
              id: place.id,
              data: _placeDataForCache(place.data()),
            ),
          )
          .toList(growable: false);

      final favoriteCounts = await _fetchFavoriteCountsForPlaces(places);
      final popularPlaces = _buildPopularPlaces(places, favoriteCounts);

      final favoritesList =
          userSnapshot.data()?['favorites'] as List<dynamic>? ?? [];
      final favoritesSet = Set<String>.from(
        favoritesList.map((e) => e.toString()),
      );

      if (!mounted) return;
      setState(() {
        _cachedPlaces = places;
        _cachedPopularPlaces = popularPlaces;
        _favoriteCountsByPlaceId = favoriteCounts;
        _cachedFavorites = favoritesSet;
        _homeLoading = false;
        _homeRefreshing = false;
        _homeError = null;
      });
      unawaited(
        _warmVisibleImageCache(places: places, popularPlaces: popularPlaces),
      );
      unawaited(_persistHomeCache(user.uid));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _homeLoading = false;
        _homeRefreshing = false;
        _homeError = _cachedPlaces.isEmpty
            ? 'Failed to refresh destinations.'
            : null;
      });
    }
  }

  Future<void> _toggleFavorite(String placeId, bool isFav) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      if (isFav) {
        _cachedFavorites.remove(placeId);
        _applyLocalFavoriteDelta(placeId, isFavorite: false);
      } else {
        _cachedFavorites.add(placeId);
        _applyLocalFavoriteDelta(placeId, isFavorite: true);
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

        final currentFavorites = List<String>.from(
          (userSnapshot.data()?['favorites'] as List<dynamic>? ?? const []).map(
            (e) => e.toString(),
          ),
        );

        var delta = 0;
        if (isFav) {
          final removed = currentFavorites.remove(placeId);
          if (removed) delta = -1;
        } else if (!currentFavorites.contains(placeId)) {
          currentFavorites.add(placeId);
          delta = 1;
        }

        transaction.set(userDoc, {
          'favorites': currentFavorites,
        }, SetOptions(merge: true));

        if (delta > 0) {
          transaction.set(statsDoc, {
            'count': FieldValue.increment(1),
          }, SetOptions(merge: true));
        } else if (delta < 0) {
          transaction.update(statsDoc, {'count': FieldValue.increment(-1)});
        }
      });
      unawaited(_persistHomeCache(user.uid));
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
                      if (_tabIndex != 3 && _tabIndex != 1)
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
          icon: Icon(Icons.map_outlined),
          selectedIcon: Icon(Icons.map),
          label: Text('Map'),
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
      return const TourUserMapContent();
    } else if (_tabIndex == 2) {
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
        .where((doc) => _matchesQuery((doc.data['title'] ?? '').toString()))
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
                          key: const PageStorageKey<String>(
                            'popular-places-list',
                          ),
                          scrollDirection: Axis.horizontal,
                          padding: EdgeInsets.symmetric(
                            horizontal: horizontalPadding,
                          ),
                          itemCount: _cachedPopularPlaces.length,
                          itemBuilder: (context, index) {
                            final doc = _cachedPopularPlaces[index];
                            final data = doc.data;
                            return PopularPlaceCard(
                              key: ValueKey('popular-${doc.id}'),
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
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final doc = filteredDocs[index];
                        final data = doc.data;
                        return DiscoverPlaceCard(
                          key: ValueKey('discover-${doc.id}'),
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
                      childCount: filteredDocs.length,
                      findChildIndexCallback: (key) {
                        if (key is! ValueKey<String>) return null;
                        const prefix = 'discover-';
                        final value = key.value;
                        if (!value.startsWith(prefix)) return null;
                        final id = value.substring(prefix.length);
                        final index = filteredDocs.indexWhere(
                          (doc) => doc.id == id,
                        );
                        return index == -1 ? null : index;
                      },
                    ),
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
        builder: (_) => PlaceDetailScreen(
          key: ValueKey('place-detail-$placeId'),
          place: place,
          placeId: placeId,
        ),
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
              final data = doc.data;
              return DiscoverPlaceCard(
                key: ValueKey('wishlist-${doc.id}'),
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

class _CachedPlace {
  final String id;
  final Map<String, dynamic> data;

  const _CachedPlace({required this.id, required this.data});
}
