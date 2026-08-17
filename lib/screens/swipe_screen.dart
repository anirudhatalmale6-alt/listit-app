import 'package:flutter/material.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';

import '../models/ad.dart';
import '../models/category.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/swipe_card.dart';
import 'ad_detail_screen.dart';
import 'auth/auth_screen.dart';

/// The Tinder-style discovery deck - the headline feature of the app. Swipe
/// right to show interest, left to pass, up to save for later. Cards stream in
/// a page at a time from the same `/search` feed the website uses.
///
/// Phase 1 keeps the "interested" and "saved" sets in memory. Phase 2 wires
/// them to `POST /save-ad` and the messaging endpoints once auth lands.
class SwipeScreen extends StatefulWidget {
  final Category? category;
  final ApiService api;
  final AuthService auth;

  /// Extra search filters (keyword, price range, ...) merged into every page
  /// request. Lets Browse feed the deck a keyword search or a category filter.
  final Map<String, dynamic> filters;

  /// Overrides the app-bar title (e.g. a keyword search shows the term).
  final String? titleOverride;

  const SwipeScreen({
    super.key,
    required this.api,
    required this.auth,
    this.category,
    this.filters = const {},
    this.titleOverride,
  });

  @override
  State<SwipeScreen> createState() => _SwipeScreenState();
}

class _SwipeScreenState extends State<SwipeScreen> {
  final CardSwiperController _controller = CardSwiperController();

  final List<Ad> _ads = [];
  final List<Ad> _interested = [];

  int _page = 1;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _exhausted = false;
  String? _error;

  // The section the deck is narrowed to (null = everything). Lets the user
  // filter Discover so it isn't showing random stuff.
  Category? _selected;
  List<Category> _cats = const [];

  static const int _pageSize = 20;
  static const int _prefetchThreshold = 6;

  String get _title =>
      widget.titleOverride ??
      (_selected == null ? 'Discover' : _sectionLabel(_selected!.name));

  @override
  void initState() {
    super.initState();
    _selected = widget.category;
    _loadFirstPage();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await widget.api.search(
          categoryId: _selected?.id,
          isVehicle: _selected?.isVehicle ?? false,
          page: 1,
          limit: _pageSize,
          filters: widget.filters);
      if (!mounted) return;
      setState(() {
        _ads
          ..clear()
          ..addAll(res.ads);
        _total = res.total;
        _page = 1;
        _exhausted = res.ads.length < _pageSize;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _exhausted) return;
    _loadingMore = true;
    try {
      final next = _page + 1;
      final res = await widget.api.search(
          categoryId: _selected?.id,
          isVehicle: _selected?.isVehicle ?? false,
          page: next,
          limit: _pageSize,
          filters: widget.filters);
      if (!mounted) return;
      setState(() {
        final existing = _ads.map((a) => a.id).toSet();
        _ads.addAll(res.ads.where((a) => !existing.contains(a.id)));
        _page = next;
        if (res.ads.isEmpty || res.ads.length < _pageSize) _exhausted = true;
      });
    } catch (_) {
      // A failed prefetch is non-fatal - the user can keep swiping what's
      // loaded and we'll retry on the next threshold crossing.
    } finally {
      _loadingMore = false;
    }
  }

  bool _onSwipe(int previous, int? current, CardSwiperDirection direction) {
    final ad = _ads[previous];
    if (direction == CardSwiperDirection.right) {
      _interested.add(ad);
      _toast('Interested in "${_shorten(ad.title)}"', AppColors.success);
    } else if (direction == CardSwiperDirection.top) {
      _save(ad);
    }
    if (current != null && current >= _ads.length - _prefetchThreshold) {
      _loadMore();
    }
    return true;
  }

  /// Persist a save to the user's account. Signed-out users get a gentle
  /// nudge to sign in rather than losing the action silently.
  Future<void> _save(Ad ad) async {
    final user = widget.auth.user;
    if (user == null) {
      _promptLogin();
      return;
    }
    try {
      await widget.api.saveAd(userId: user.id, adId: ad.id);
      _toast('Saved "${_shorten(ad.title)}"', AppColors.save);
    } on ApiException catch (e) {
      _toast(e.message, AppColors.danger);
    } catch (_) {
      _toast('Could not save right now.', AppColors.danger);
    }
  }

  void _promptLogin() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Sign in to save ads'),
          backgroundColor: AppColors.ink,
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'SIGN IN',
            textColor: Colors.white,
            onPressed: () async {
              final ok = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => AuthScreen(
                      auth: widget.auth, reason: 'Sign in to save this ad'),
                ),
              );
              if (ok == true) widget.auth.refreshProfile();
            },
          ),
        ),
      );
  }

  void _openDetail(Ad ad) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdDetailScreen(
            adId: ad.id, api: widget.api, preview: ad, auth: widget.auth),
      ),
    );
  }

  /// Let the user narrow Discover to one section so the deck isn't random.
  Future<void> _openFilter() async {
    if (_cats.isEmpty) {
      try {
        _cats = await widget.api.fetchTopCategories();
      } catch (_) {/* show just "Everything" if the list can't load */}
    }
    if (!mounted) return;
    // Returns a Category for a section, the string 'ALL' for Everything, or
    // null if dismissed with no change.
    final picked = await showModalBottomSheet<Object?>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      isScrollControlled: true,
      builder: (_) => _SectionPicker(cats: _cats, selectedId: _selected?.id),
    );
    if (picked == null) return;
    setState(() => _selected = picked is Category ? picked : null);
    _loadFirstPage();
  }

  void _toast(String message, Color color) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 900),
        ),
      );
  }

  String _shorten(String s) => s.length <= 28 ? s : '${s.substring(0, 28)}...';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(_title),
        actions: [
          if (_total > 0)
            Center(
              child: Text(
                '$_total listings',
                style: const TextStyle(
                  color: AppColors.slate,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          // Reset brings the whole deck back from the start, in case you
          // swiped past something and change your mind.
          IconButton(
            tooltip: 'Reset',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _loadFirstPage,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 4, left: 4),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  tooltip: 'Filter',
                  icon: const Icon(Icons.tune_rounded),
                  onPressed: _openFilter,
                ),
                if (_selected != null)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(
                          color: AppColors.primary, shape: BoxShape.circle),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (_error != null) {
      return _ErrorState(message: _error!, onRetry: _loadFirstPage);
    }
    if (_ads.isEmpty) {
      return const _EmptyState();
    }
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: CardSwiper(
              controller: _controller,
              cardsCount: _ads.length,
              numberOfCardsDisplayed: _ads.length >= 3 ? 3 : _ads.length,
              backCardOffset: const Offset(0, 40),
              padding: EdgeInsets.zero,
              isLoop: false,
              onSwipe: _onSwipe,
              onEnd: _onDeckEnd,
              cardBuilder: (context, index, hOffset, vOffset) {
                final ad = _ads[index];
                final stamp = _stampFor(hOffset, vOffset);
                final opacity = _stampOpacity(hOffset, vOffset);
                return GestureDetector(
                  onTap: () => _openDetail(ad),
                  child: SwipeCard(
                    ad: ad,
                    overlay: stamp,
                    overlayOpacity: opacity,
                  ),
                );
              },
            ),
          ),
        ),
        _actionBar(),
      ],
    );
  }

  SwipeStamp _stampFor(int h, int v) {
    if (v < -20 && v.abs() > h.abs()) return SwipeStamp.save;
    if (h > 20) return SwipeStamp.like;
    if (h < -20) return SwipeStamp.nope;
    return SwipeStamp.none;
  }

  double _stampOpacity(int h, int v) {
    final magnitude = (v < 0 && v.abs() > h.abs()) ? v.abs() : h.abs();
    return (magnitude / 100).clamp(0, 1);
  }

  void _onDeckEnd() {
    if (!_exhausted) {
      _loadMore();
    } else {
      _toast('That\'s everything for now', AppColors.slate);
    }
  }

  Widget _actionBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _circleButton(
            icon: Icons.close_rounded,
            color: AppColors.danger,
            size: 60,
            onTap: () => _controller.swipe(CardSwiperDirection.left),
          ),
          _circleButton(
            icon: Icons.bookmark_border_rounded,
            color: AppColors.save,
            size: 48,
            onTap: () => _controller.swipe(CardSwiperDirection.top),
          ),
          _circleButton(
            icon: Icons.undo_rounded,
            color: AppColors.slate,
            size: 48,
            onTap: () => _controller.undo(),
          ),
          _circleButton(
            icon: Icons.favorite_rounded,
            color: AppColors.success,
            size: 60,
            onTap: () => _controller.swipe(CardSwiperDirection.right),
          ),
        ],
      ),
    );
  }

  Widget _circleButton({
    required IconData icon,
    required Color color,
    required double size,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      elevation: 0,
      shadowColor: Colors.black26,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, color: color, size: size * 0.5),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 48, color: AppColors.muted),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.slate, fontSize: 15),
            ),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

/// The Cars & Motors section is shown as "Motor Mall" in the app.
String _sectionLabel(String name) =>
    name == 'Cars & Motors' ? 'Motor Mall' : name;

/// A bottom sheet to pick which section Discover swipes through (or Everything).
class _SectionPicker extends StatelessWidget {
  final List<Category> cats;
  final int? selectedId;
  const _SectionPicker({required this.cats, required this.selectedId});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, controller) {
        return Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Show me',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: controller,
                children: [
                  ListTile(
                    leading: const Icon(Icons.all_inclusive_rounded,
                        color: AppColors.primary),
                    title: const Text('Everything',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    trailing: selectedId == null
                        ? const Icon(Icons.check, color: AppColors.primary)
                        : null,
                    onTap: () => Navigator.of(context).pop('ALL'),
                  ),
                  for (final c in cats)
                    ListTile(
                      title: Text(_sectionLabel(c.name)),
                      trailing: selectedId == c.id
                          ? const Icon(Icons.check, color: AppColors.primary)
                          : null,
                      onTap: () => Navigator.of(context).pop(c),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: AppColors.muted),
            SizedBox(height: 16),
            Text(
              'No listings here yet.\nCheck back soon.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.slate, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}
