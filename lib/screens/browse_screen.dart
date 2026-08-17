import 'package:flutter/material.dart';

import '../models/category.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/site_settings.dart';
import '../theme.dart';
import '../widgets/featured_dealers_strip.dart';
import '../widgets/network_photo.dart';
import '../widgets/vehicle_search_panel.dart';
import 'auth/auth_screen.dart';
import 'recently_viewed_screen.dart';
import 'results_screen.dart';
import 'saved_searches_screen.dart';
import 'search_screen.dart';
import 'swipe_screen.dart';

/// 2679 -> "2,679". Keeps the home screen numbers reading cleanly.
String _grouped(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// The marketplace calls its Cars & Motors section "Motor Mall" - map the
/// stored category name to that label wherever a section name is shown.
String sectionLabel(String name) =>
    name == 'Cars & Motors' ? 'Motor Mall' : name;

/// The Browse tab, modelled on DoneDeal's marketplace home: a hero banner with
/// the brand and tagline, a search bar tucked into it, then every marketplace
/// section as a clean list row with a colourful thumbnail and live listing
/// count. Tapping a section drops you into its swipe deck.
class BrowseScreen extends StatefulWidget {
  final ApiService api;
  final AuthService auth;

  /// Jumps the shell to the Discover tab (the swipe deck for everything).
  final VoidCallback onDiscover;

  const BrowseScreen({
    super.key,
    required this.api,
    required this.auth,
    required this.onDiscover,
  });

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  // The two sections that get their own top tab (Cars & Motors and Property);
  // everything else lives under "Marketplace".
  static const int _carsCatId = 62;
  static const int _propertyCatId = 106;
  // The Cars For Sale leaf (a vehicle section) that the car-search panel runs
  // against, so make/year/price resolve through the backend's vehicle filter.
  static const int _carsForSaleCatId = 89;

  late Future<List<Category>> _future;
  List<Category> _all = const [];
  // 0 = Cars & Motors, 1 = Marketplace (default), 2 = Property.
  int _tab = 1;

  final TextEditingController _search = TextEditingController();

  // Live "currently listed" count per category id, matching exactly what the
  // website shows. The category feed carries a broader all-time figure, so we
  // fetch the real live totals separately and fill each row in as they land.
  final Map<int, int> _liveCounts = {};

  @override
  void initState() {
    super.initState();
    _future = widget.api.fetchAllCategories();
    _future.then((all) {
      if (!mounted) return;
      setState(() => _all = all);
      _loadCounts(_visibleCats);
    });
  }

  // --- Section tabs ---------------------------------------------------------

  List<Category> get _topLevel {
    final t = _all.where((c) => c.isTopLevel && c.name.isNotEmpty).toList();
    t.sort((a, b) => b.adCount.compareTo(a.adCount));
    return t;
  }

  List<Category> _childrenOf(int id) {
    final l = _all.where((c) => c.parentId == id && c.name.isNotEmpty).toList();
    l.sort((a, b) => b.adCount.compareTo(a.adCount));
    return l;
  }

  Category? _catById(int id) {
    for (final c in _all) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// The category rows shown under the current tab.
  List<Category> get _visibleCats {
    switch (_tab) {
      case 0:
        return _childrenOf(_carsCatId);
      case 2:
        return _childrenOf(_propertyCatId);
      default:
        return _topLevel;
    }
  }

  /// The section the search is scoped to for the current tab (null = whole site).
  Category? get _scope {
    switch (_tab) {
      case 0:
        return _catById(_carsCatId);
      case 2:
        return _catById(_propertyCatId);
      default:
        return null;
    }
  }

  /// The Marketplace tab now feeds in every ad on the island (private sellers,
  /// dealers, agents and businesses alike), so no seller filter is applied.
  Map<String, dynamic> get _sectionBase => const {};

  String get _searchHint => _scope == null
      ? 'Search cars, property, jobs, furniture...'
      : 'Search ${sectionLabel(_scope!.name)}';

  String get _sectionHeading {
    switch (_tab) {
      case 0:
        return 'Browse Motor Mall';
      case 2:
        return 'Browse Property';
      default:
        // No "Browse the marketplace" heading - the categories lead straight
        // in, like DoneDeal.
        return '';
    }
  }

  void _setTab(int i) {
    if (i == _tab) return;
    setState(() => _tab = i);
    _loadCounts(_visibleCats);
  }

  void _loadCounts(List<Category> cats) {
    // Recompute per-section so Marketplace counts reflect private-only.
    _liveCounts.clear();
    final base = _sectionBase;
    for (final c in cats) {
      widget.api
          .search(
              categoryId: c.id,
              isVehicle: c.isVehicle,
              limit: 1,
              filters: base)
          .then((r) {
        if (mounted) setState(() => _liveCounts[c.id] = r.total);
      }).catchError((_) {/* leave the row on 'Browse' if a count fails */});
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _liveCounts.clear();
      _all = const [];
      _future = widget.api.fetchAllCategories();
    });
    _future.then((all) {
      if (!mounted) return;
      setState(() => _all = all);
      _loadCounts(_visibleCats);
    });
  }

  void _openCategory(Category c) {
    // Tapping a section drops you straight into all its ads (newest first),
    // exactly like DoneDeal - narrow down from there with Filter.
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ResultsScreen(
          api: widget.api,
          auth: widget.auth,
          category: c,
          baseFilters: _sectionBase,
          titleOverride: c.name == 'Cars & Motors' ? 'Motor Mall' : null,
        ),
      ),
    );
  }

  /// A clean white top bar with the blue Listit logo (like the website header),
  /// carrying the log-in button / account avatar.
  Widget _topBar() {
    // padding.top is zeroed if an ancestor has already consumed it, which left
    // the logo sitting under the clock on some handsets. viewPadding always
    // reports the physical status-bar inset, so fall back to it.
    final mq = MediaQuery.of(context);
    final topPad = mq.padding.top > 0 ? mq.padding.top : mq.viewPadding.top;
    return Container(
      // A plain white bar with a hairline under it, the height of a normal
      // app bar - not a floating panel.
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      padding: EdgeInsets.fromLTRB(16, topPad + 9, 16, 9),
      child: Row(
        children: [
          Image.asset(
            'assets/listit_logo.png',
            height: 28,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            // Dark-on-transparent logo tinted to the brand blue for the white bar.
            color: AppColors.primary,
            colorBlendMode: BlendMode.srcIn,
          ),
          const Spacer(),
          ListenableBuilder(
            listenable: widget.auth,
            builder: (context, _) {
              if (!widget.auth.isLoggedIn) {
                return OutlinedButton(
                  onPressed: _openAuth,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppRadius.control)),
                    textStyle: const TextStyle(
                        fontSize: AppText.body, fontWeight: FontWeight.w600),
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Log in'),
                );
              }
              final u = widget.auth.user!;
              final avatar = u.avatar;
              const initialsStyle = TextStyle(
                  color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700);
              return Container(
                width: 36,
                height: 36,
                clipBehavior: Clip.antiAlias,
                decoration: const BoxDecoration(
                    color: AppColors.primary, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: (avatar != null && avatar.isNotEmpty)
                    ? Image.network(
                        avatar,
                        width: 36,
                        height: 36,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stack) =>
                            Center(child: Text(u.initials, style: initialsStyle)),
                      )
                    : Text(u.initials, style: initialsStyle),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _openAuth() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AuthScreen(auth: widget.auth)),
    );
    if (ok == true) widget.auth.refreshProfile();
  }

  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchScreen(
            api: widget.api,
            auth: widget.auth,
            scope: _scope,
            baseFilters: _sectionBase),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async => _reload(),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _topBar()),
            // A slim photo band carrying the tagline - enough to say what
            // Listit is, not enough to push the marketplace off the screen.
            SliverToBoxAdapter(child: _Hero(tab: _tab)),
            // Section switch, then the search box scoped by it. Tabs sit above
            // the box because the tab decides what the box searches.
            SliverToBoxAdapter(child: _sectionTabs()),
            SliverToBoxAdapter(child: _searchBar()),
            // The car-search block leads the Motor Mall tab, sitting right
            // under the search so its Search button is easy to reach.
            SliverToBoxAdapter(child: _vehicleSearchPanel()),
            SliverToBoxAdapter(child: _quickLinks()),
            // Discover is the one thing the island's other marketplaces don't
            // have, so it stays high on the page - but as a marketplace
            // feature, not a banner.
            SliverToBoxAdapter(child: _discoverBanner()),
            SliverToBoxAdapter(child: _sectionLabel(_sectionHeading)),
            _list(),
            SliverToBoxAdapter(child: _seeAll()),
            // The Featured Dealer banner sits further down the page, below the
            // category list, exactly like DoneDeal's marketplace home.
            SliverToBoxAdapter(child: _featuredDealers()),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
          ],
        ),
      ),
    );
  }

  /// The section switch: Cars & Motors, the general Marketplace, or Property.
  /// The active tab drives the category list below and what the search box
  /// looks in. Plain tabs with an underline on the active one - a navigation
  /// control, not a floating card.
  Widget _sectionTabs() {
    const labels = ['Motor Mall', 'Marketplace', 'Property'];
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(child: _tabItem(labels[i], i)),
        ],
      ),
    );
  }

  Widget _tabItem(String label, int i) {
    final active = i == _tab;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _setTab(i),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? AppColors.primary : Colors.transparent,
              width: 2.5,
            ),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: active ? AppColors.ink : AppColors.slate,
            fontSize: AppText.body,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: TextField(
        controller: _search,
        readOnly: true,
        onTap: _openSearch,
        decoration: InputDecoration(
          hintText: _searchHint,
          prefixIcon: const Icon(Icons.search, color: AppColors.slate, size: 20),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 40, minHeight: 40),
          isDense: true,
        ),
      ),
    );
  }

  /// Recently Viewed and Saved Searches as one compact row rather than two
  /// large cards - useful, but not worth a third of the first screen.
  Widget _quickLinks() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.line),
          bottom: BorderSide(color: AppColors.line),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _quickLink(
              icon: Icons.history_rounded,
              label: 'Recently Viewed',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => RecentlyViewedScreen(api: widget.api),
              )),
            ),
          ),
          const SizedBox(
            height: 22,
            child: VerticalDivider(width: 1, color: AppColors.line),
          ),
          Expanded(
            child: _quickLink(
              icon: Icons.bookmark_border_rounded,
              label: 'Saved Searches',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    SavedSearchesScreen(api: widget.api, auth: widget.auth),
              )),
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickLink({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.slate, size: 17),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: AppText.meta,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The DoneDeal-style car-search block - only on the Cars & Motors tab, and
  /// only once the Cars For Sale section has loaded so it can run the search.
  Widget _vehicleSearchPanel() {
    if (_tab != 0) return const SizedBox.shrink();
    final cars = _catById(_carsForSaleCatId);
    if (cars == null) return const SizedBox.shrink();
    return VehicleSearchPanel(
      key: const ValueKey('car-search'),
      api: widget.api,
      auth: widget.auth,
      carsCategory: cars,
    );
  }

  /// A single Featured Dealer banner (rotating hourly) on the Cars & Motors and
  /// Marketplace tabs. Farming has no dealer sector, so it doesn't appear there.
  Widget _featuredDealers() {
    if (_tab == 2) return const SizedBox.shrink();
    return FeaturedDealersStrip(
      key: const ValueKey('featured-motors'),
      api: widget.api,
      auth: widget.auth,
      sector: 'motors',
      title: 'Featured Dealer',
    );
  }

  /// A "See all in {section}" row at the foot of the category list - opens every
  /// live ad in the current section (or the whole site under Marketplace).
  Widget _seeAll() {
    if (_all.isEmpty) return const SizedBox.shrink();
    final label = _tab == 0
        ? 'See all in Motor Mall'
        : _tab == 2
            ? 'See all in Farming'
            : 'See all in Marketplace';
    return InkWell(
      onTap: _openSeeAll,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: AppText.body,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
            const Icon(Icons.arrow_forward_ios,
                size: 13, color: AppColors.primary),
          ],
        ),
      ),
    );
  }

  void _openSeeAll() {
    final scope = _scope;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ResultsScreen(
        api: widget.api,
        auth: widget.auth,
        category: scope,
        baseFilters: _sectionBase,
        titleOverride:
            scope == null ? 'All ads' : sectionLabel(scope.name),
      ),
    ));
  }

  /// Opens the swipe deck scoped to whatever section the home tab is on.
  /// On Marketplace (no scope) this is the whole island; on Motor Mall or
  /// Property it swipes through just that section instead of everything.
  void _openDiscover() {
    final scope = _scope;
    if (scope == null) {
      widget.onDiscover();
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SwipeScreen(
        api: widget.api,
        auth: widget.auth,
        category: scope,
        titleOverride: sectionLabel(scope.name),
      ),
    ));
  }

  /// Discover as a marketplace feature rather than a billboard: one compact
  /// row in the same rhythm as the category list, with the fanned deck to show
  /// what swiping is. Nothing else on the island does swipe-to-browse, so it
  /// stays high on the page - it just no longer shouts.
  Widget _discoverBanner() {
    final scope = _scope;
    final subtitle = scope == null
        ? 'Swipe through everything on the island'
        : 'Swipe through ${sectionLabel(scope.name)}';
    return InkWell(
      onTap: _openDiscover,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          children: [
            const _SwipeDeckMark(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Discover',
                    style: TextStyle(
                      fontSize: AppText.listing,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AppText.meta,
                      color: AppColors.slate,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.muted),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    if (text.isEmpty) return const SizedBox(height: 4);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: AppText.section,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
      ),
    );
  }

  Widget _list() {
    return FutureBuilder<List<Category>>(
      future: _future,
      builder: (context, snap) {
        if (_all.isEmpty && snap.connectionState == ConnectionState.waiting) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            ),
          );
        }
        if (_all.isEmpty && snap.hasError) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  const Text('Could not load categories.',
                      style: TextStyle(color: AppColors.slate)),
                  const SizedBox(height: 12),
                  ElevatedButton(
                      onPressed: _reload, child: const Text('Retry')),
                ],
              ),
            ),
          );
        }
        final cats = _visibleCats;
        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) => _CategoryRow(
              category: cats[i],
              liveCount: _liveCounts[cats[i].id],
              onTap: () => _openCategory(cats[i]),
            ),
            childCount: cats.length,
          ),
        );
      },
    );
  }
}

/// A colourful icon + accent colour per marketplace section, keyed on the
/// category slug. The website's category art is all one blue line-art style,
/// which made the app read as a wall of blue - this gives every section its
/// own bright, recognisable colour like DoneDeal's home. Unknown slugs fall
/// back to a neutral thumbnail that still shows the website image.
class _CatStyle {
  final IconData icon;
  final Color color;
  const _CatStyle(this.icon, this.color);
}

const _CatStyle _fallbackStyle = _CatStyle(Icons.category_rounded, AppColors.primary);

_CatStyle _styleFor(String slug) {
  switch (slug) {
    case 'property':
      return const _CatStyle(Icons.home_rounded, Color(0xFF2F6BE0));
    case 'cars-and-motors':
      return const _CatStyle(Icons.directions_car_rounded, Color(0xFFE8532B));
    case 'electronics':
      return const _CatStyle(Icons.devices_rounded, Color(0xFF7C4DFF));
    case 'house-and-diy':
      return const _CatStyle(Icons.chair_rounded, Color(0xFFB4741E));
    case 'sports-and-hobbies':
      return const _CatStyle(Icons.sports_soccer_rounded, Color(0xFF12A150));
    case 'clothes-and-lifestyle':
      return const _CatStyle(Icons.checkroom_rounded, Color(0xFFE84D8A));
    case 'baby-and-kids':
      return const _CatStyle(Icons.child_friendly_rounded, Color(0xFFEC9A00));
    case 'animals':
      return const _CatStyle(Icons.pets_rounded, Color(0xFF8D5A2B));
    case 'music-and-education':
      return const _CatStyle(Icons.music_note_rounded, Color(0xFF5A55CA));
    case 'services':
      return const _CatStyle(Icons.miscellaneous_services_rounded, Color(0xFF0E9AA7));
    case 'free-stuff':
      return const _CatStyle(Icons.card_giftcard_rounded, Color(0xFF2FA84F));
    case 'whats-on':
      return const _CatStyle(Icons.local_activity_rounded, Color(0xFF9333EA));
    case 'weird-and-wonderful':
      return const _CatStyle(Icons.auto_awesome_rounded, Color(0xFFC026D3));
    case 'business':
      return const _CatStyle(Icons.business_center_rounded, Color(0xFF3E5C76));
    case 'farming':
      return const _CatStyle(Icons.agriculture_rounded, Color(0xFF4E8C2A));
    case 'holidays-and-tickets':
      return const _CatStyle(Icons.flight_takeoff_rounded, Color(0xFF0EA5C4));
    case 'lost-and-found':
      return const _CatStyle(Icons.travel_explore_rounded, Color(0xFFEA7317));
    case 'jobs':
      return const _CatStyle(Icons.work_rounded, Color(0xFF2557A7));
    default:
      return _fallbackStyle;
  }
}

/// The hero: a slim photo band with the tagline over it, so a first-time
/// visitor learns what Listit is in one line and then gets straight to the
/// marketplace. Square-cornered and edge to edge - a masthead rather than a
/// floating panel, and small enough that the listings start near the top of
/// the screen.
class _Hero extends StatelessWidget {
  final int tab;
  const _Hero({required this.tab});

  /// The marketplace banner image from the website's own settings, so the app
  /// hero matches the site. A dark overlay sits on top for white-text contrast;
  /// if it ever fails to load we fall back to the plain brand gradient.
  static const String _heroImage =
      'https://api.listit.im/assets/images/settings/1761592985344-cropped-image-opt.jpg';

  /// Each section shows its own hero from the website's settings: the Property
  /// tab gets the site's `property` banner, everything else the home banner.
  /// Changing them on the site changes them here too; we fall back to the
  /// last-known image if settings haven't loaded yet.
  Widget _heroBackground() {
    return ValueListenableBuilder<Map<String, String>>(
      valueListenable: SiteSettings.values,
      builder: (context, _, _) {
        final url = tab == 2
            ? (SiteSettings.propertyBanner ??
                SiteSettings.homeBanner ??
                _heroImage)
            : (SiteSettings.homeBanner ?? _heroImage);
        return Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) => const SizedBox.shrink(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 86,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Brand colour sits underneath as the base / fallback.
          const DecoratedBox(
            decoration: BoxDecoration(color: AppColors.primaryDark),
          ),
          // The section-appropriate banner image.
          Positioned.fill(child: _heroBackground()),
          // A flat scrim for text contrast - no gradient theatrics, just
          // enough to keep the tagline readable over any photo.
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(color: Color(0xB00B2430)),
            ),
          ),
          const Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                "The Isle of Man's place to buy & sell",
                style: TextStyle(
                  fontSize: 19,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The Discover thumbnail - the same layered-cards mark the toolbar uses for
/// the tab, sized and tinted like every other row thumbnail so the row sits in
/// the rhythm of the list under it.
class _SwipeDeckMark extends StatelessWidget {
  const _SwipeDeckMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.image),
      ),
      child: const Icon(Icons.style_rounded, color: AppColors.primary, size: 21),
    );
  }
}

/// A single marketplace section row, DoneDeal-style: a colourful rounded
/// thumbnail, the section name, its live listing count, and a chevron.
class _CategoryRow extends StatelessWidget {
  final Category category;
  final int? liveCount;
  final VoidCallback onTap;
  const _CategoryRow({
    required this.category,
    required this.liveCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final style = _styleFor(category.slug);
    final useImage = style == _fallbackStyle && category.imageUrl.isNotEmpty;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: style.color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppRadius.image),
              ),
              alignment: Alignment.center,
              clipBehavior: Clip.antiAlias,
              child: useImage
                  ? Padding(
                      padding: const EdgeInsets.all(7),
                      child: NetworkPhoto(
                          url: category.imageUrl, fit: BoxFit.contain),
                    )
                  : Icon(style.icon, color: style.color, size: 21),
            ),
            const SizedBox(width: 12),
            // Name on the left, count on the right - the classifieds layout,
            // and it keeps every row to a single line.
            Expanded(
              child: Text(
                sectionLabel(category.name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: AppText.listing,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              liveCount != null
                  ? '${_grouped(liveCount!)} ${liveCount == 1 ? 'ad' : 'ads'}'
                  : '',
              style: const TextStyle(
                fontSize: AppText.meta,
                color: AppColors.slate,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_ios,
                size: 13, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}
