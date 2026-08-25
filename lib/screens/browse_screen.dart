import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/category.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/recent_searches.dart';
import '../services/site_settings.dart';
import '../theme.dart';
import '../widgets/featured_dealers_strip.dart';
import '../widgets/network_photo.dart';
import '../widgets/vehicle_search_panel.dart';
import 'auth/auth_screen.dart';
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
  // The sections that get their own top tab (Cars & Motors, Property and
  // Farming); everything else lives under "Marketplace".
  static const int _carsCatId = 62;
  static const int _propertyCatId = 106;
  static const int _farmingCatId = 100;
  // The Cars For Sale leaf (a vehicle section) that the car-search panel runs
  // against, so make/year/price resolve through the backend's vehicle filter.
  static const int _carsForSaleCatId = 89;

  late Future<List<Category>> _future;
  List<Category> _all = const [];
  // 0 = Cars & Motors, 1 = Marketplace (default), 2 = Property, 3 = Farming.
  int _tab = 1;

  final TextEditingController _search = TextEditingController();

  /// The area the hero search is limited to. `null` is the website's default,
  /// "All areas in the Isle of Man".
  String? _location;

  // Live "currently listed" count per category id, matching exactly what the
  // website shows. The category feed carries a broader all-time figure, so we
  // fetch the real live totals separately and fill each row in as they land.
  final Map<int, int> _liveCounts = {};

  // The two rows under the search box: the last thing they searched for
  // on this device, and how many searches they have saved.
  String? _lastSearch;
  int _savedCount = 0;

  @override
  void initState() {
    super.initState();
    _future = widget.api.fetchAllCategories();
    _future.then((all) {
      if (!mounted) return;
      setState(() => _all = all);
      _loadCounts(_visibleCats);
    });
    _loadShortcuts();
  }

  /// Coming back from a search or a sign-in changes both shortcut rows, so they
  /// are refreshed whenever this screen is shown again, not only on start.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadShortcuts();
  }

  /// Run a keyword search the way the search screen does - same filter key, so
  /// a tap on the last search lands exactly where it originally did.
  void _runSearch(String term) {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => ResultsScreen(
            api: widget.api,
            auth: widget.auth,
            baseFilters: {..._sectionBase, 'keyword': term},
            titleOverride: term,
          ),
        ))
        .then((_) => _loadShortcuts());
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
      case 3:
        return _childrenOf(_farmingCatId);
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
      case 3:
        return _catById(_farmingCatId);
      default:
        return null;
    }
  }

  /// The Marketplace tab now feeds in every ad on the island (private sellers,
  /// dealers, agents and businesses alike), so no seller filter is applied.
  Map<String, dynamic> get _sectionBase => const {};

  /// The short section name the website puts in the orange badge beside the
  /// logo, and in the search placeholder.
  String get _sectionBadge {
    switch (_tab) {
      case 0:
        return 'Motors';
      case 2:
        return 'Property';
      case 3:
        return 'Farming';
      default:
        return 'Marketplace';
    }
  }

  String get _searchHint => 'Search in $_sectionBadge';

  /// The website's blue button label. It says "Motor Mall" even though the tab
  /// above it says "Motors" - both spellings are the site's own.
  String get _searchButtonLabel {
    switch (_tab) {
      case 0:
        return 'Search Motor Mall';
      case 2:
        return 'Search Property';
      case 3:
        return 'Search Farming';
      default:
        return 'Search Marketplace';
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
    // Farming lost its tab, so its row is the way into the mall - the fifteen
    // subsections - rather than into every farming ad at once. Same behaviour
    // as the Farming tile on the website.
    if (c.id == _farmingCatId) {
      _setTab(3);
      return;
    }
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

  /// The website's header, on the same navy: the blue Listit logo, the orange
  /// badge naming the section you are in, then the search magnifier and the
  /// log-in button / account avatar.
  ///
  /// This band does not scroll. The site's does, but the app draws behind the
  /// status bar, and a scrolling navy bar would slide white listings under a
  /// clock that has been set to white - so it stays put and the rest of the
  /// hero scrolls under it.
  Widget _topBar() {
    // padding.top is zeroed if an ancestor has already consumed it, which left
    // the logo sitting under the clock on some handsets. viewPadding always
    // reports the physical status-bar inset, so fall back to it.
    final mq = MediaQuery.of(context);
    final topPad = mq.padding.top > 0 ? mq.padding.top : mq.viewPadding.top;
    return Container(
      color: AppColors.navy,
      padding: EdgeInsets.fromLTRB(16, topPad + 10, 16, 10),
      child: Row(
        children: [
          // Logo and badge shrink together rather than the badge clipping its
          // own word: "Market..." beside the logo is worse than a slightly
          // smaller logo on a narrow handset.
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/listit_logo.png',
                    height: 28,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    // Dark-on-transparent logo tinted to the brand blue,
                    // exactly as the site draws it over the navy.
                    color: AppColors.primary,
                    colorBlendMode: BlendMode.srcIn,
                  ),
                  const SizedBox(width: 10),
                  _sectionBadgePill(),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _openSearch,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            icon: const Icon(Icons.search, color: Colors.white, size: 26),
            tooltip: 'Search',
          ),
          const SizedBox(width: 6),
          ListenableBuilder(
            listenable: widget.auth,
            builder: (context, _) {
              if (!widget.auth.isLoggedIn) {
                // Plain words, not a pill. DoneDeal's top-right action is
                // set the same way and an outlined blue button beside a logo
                // is the thing that reads as a template.
                return InkWell(
                  onTap: _openAuth,
                  child: const Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: Text('Log in',
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: Colors.white)),
                  ),
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
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // The header behind the clock is navy now, so the clock and the signal
      // bars have to be drawn white or they vanish into it.
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppColors.page,
        body: Column(
          children: [
            _topBar(),
            Expanded(child: _pageBody()),
          ],
        ),
      ),
    );
  }

  Widget _pageBody() {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async => _reload(),
      child: CustomScrollView(
          slivers: [
            // The section switch, the search box, the area and the blue
            // Search button, all on the navy - the website's hero.
            SliverToBoxAdapter(child: _heroBlock()),
            SliverToBoxAdapter(child: _searchShortcuts()),
            // Discover is the one thing the island's other marketplaces don't
            // have, so it stays high on the page - but as a marketplace
            // feature, not a banner.
            SliverToBoxAdapter(child: _discoverBanner()),
            // No heading over the sections. A centred "Explore Some Of Our
            // Popular Categories" used to sit here, two lines deep, and it was
            // the loudest thing on the page while saying nothing a buyer did
            // not already know from the rows underneath it. Marketplaces that
            // have been running for years put nothing there at all.
            _list(),
            SliverToBoxAdapter(child: _seeAll()),
            // The Featured Dealer banner sits further down the page, below the
            // category list, exactly like DoneDeal's marketplace home.
            SliverToBoxAdapter(child: _featuredDealers()),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
          ],
        ),
    );
  }

  /// "My Last Search" and "Saved Searches", the two rows DoneDeal puts directly
  /// under the search box. Both were already in the app - the last search is
  /// recorded on the device every time one is run, and the saved-searches
  /// screen was reachable only from Profile - so this is wiring, not new work.
  ///
  /// The last-search row is left out entirely until there is one, rather than
  /// sitting there empty on a new install.
  Widget _searchShortcuts() {
    final rows = <Widget>[];

    if (_lastSearch != null && _lastSearch!.isNotEmpty) {
      rows.add(InkWell(
        onTap: () => _runSearch(_lastSearch!),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              const Icon(Icons.schedule_rounded,
                  size: 20, color: AppColors.muted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('My Last Search',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink)),
                    const SizedBox(height: 2),
                    Text(_lastSearch!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14.5, color: AppColors.slate)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ));
    }

    rows.add(InkWell(
      onTap: _openSavedSearches,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
        child: Row(
          children: [
            const Icon(Icons.star_rounded, size: 22, color: Color(0xFFF5C518)),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Saved Searches',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink)),
            ),
            Text('$_savedCount',
                style: const TextStyle(fontSize: 16, color: AppColors.slate)),
          ],
        ),
      ),
    ));

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Column(children: rows),
    );
  }

  void _openSavedSearches() {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) =>
              SavedSearchesScreen(api: widget.api, auth: widget.auth),
        ))
        // The count changes if they delete one while they are in there.
        .then((_) => _loadShortcuts());
  }

  Future<void> _loadShortcuts() async {
    final recent = await RecentSearches.load();
    var saved = 0;
    if (widget.auth.isLoggedIn) {
      try {
        final list =
            await widget.api.listSavedSearches(userId: widget.auth.user!.id);
        saved = list.length;
      } catch (_) {/* a dead network should not blank the home screen */}
    }
    if (!mounted) return;
    setState(() {
      _lastSearch = recent.isEmpty ? null : recent.first;
      _savedCount = saved;
    });
  }

  /// The orange badge beside the logo, naming the section you are in.
  Widget _sectionBadgePill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.badge,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        _sectionBadge,
        maxLines: 1,
        softWrap: false,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  /// The website's hero, one for one: the section tabs, a search box, the area
  /// selector and the blue Search button, all sitting on the navy with the
  /// banner photo bleeding in from the right.
  Widget _heroBlock() {
    return Stack(
      children: [
        Positioned.fill(child: _Hero(tab: _tab)),
        Column(
          children: [
            _sectionTabs(),
            // Motors searches by make, year and price - the fields a car buyer
            // actually uses - so on that tab they ARE the hero. The other two
            // tabs keep the keyword box and the area picker, which is how the
            // website and DoneDeal both split it.
            if (_tab == 0 && _catById(_carsForSaleCatId) != null)
              VehicleSearchPanel(
                key: const ValueKey('car-search-hero'),
                api: widget.api,
                auth: widget.auth,
                carsCategory: _catById(_carsForSaleCatId)!,
                onNavy: true,
              )
            else
              Padding(
                // Tight. The hero was taking better than a third of the screen
                // before a single listing appeared; the fields themselves are
                // unchanged, it is the air around them that came out.
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  children: [
                    _searchBar(),
                    const SizedBox(height: 10),
                    _locationBar(),
                    const SizedBox(height: 14),
                    _searchButton(),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// The section switch: Motors, the general Marketplace, or Property. The
  /// active tab drives the category grid below and what the search box looks
  /// in. White words on the navy, the live one in the site's lighter blue with
  /// a rounded underline.
  Widget _sectionTabs() {
    // Farming is still a section in the Marketplace grid; it just no
    // longer takes a quarter of the header.
    const labels = ['Motors', 'Marketplace', 'Property'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
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
    final style = TextStyle(
      color: active ? AppColors.heroBlue : Colors.white,
      // A ceiling, not a promise: the FittedBox below scales this down on a
      // narrow screen or a large system font.
      fontSize: 21,
      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _setTab(i),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The underline is the width of the word, not the width of the
            // tab - a bar running the full third of the screen under "Motors"
            // reads as a selected block rather than as the site's underline.
            final painter = TextPainter(
              text: TextSpan(text: label, style: style),
              textDirection: TextDirection.ltr,
              textScaler: MediaQuery.textScalerOf(context),
            )..layout();
            final barWidth = painter.width.clamp(0.0, constraints.maxWidth);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                // The width has to be tight for BoxFit.scaleDown to do
                // anything - with the loose constraints a Container
                // `alignment` hands down, the box sized itself to the text and
                // the label overflowed into its neighbour.
                SizedBox(
                  width: double.infinity,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.center,
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      style: style,
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                Container(
                  width: barWidth,
                  height: 3,
                  decoration: BoxDecoration(
                    color: active ? AppColors.heroBlue : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// The white search box. Unlike the old one this types in place, so the
  /// Search button under it has something to run - the magnifier in the header
  /// is still the way to the full search screen with suggestions and history.
  Widget _searchBar() {
    return TextField(
      controller: _search,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => _runHeroSearch(),
      style: const TextStyle(fontSize: 16, color: AppColors.ink),
      decoration: InputDecoration(
        hintText: _searchHint,
        hintStyle: const TextStyle(color: AppColors.muted, fontSize: 16),
        prefixIcon: const Icon(Icons.search, color: AppColors.slate, size: 22),
        prefixIconConstraints:
            const BoxConstraints(minWidth: 46, minHeight: 46),
        contentPadding: const EdgeInsets.symmetric(vertical: 15),
        border: _heroFieldBorder,
        enabledBorder: _heroFieldBorder,
        focusedBorder: _heroFieldBorder,
      ),
    );
  }

  /// White field, no visible border - the site's hero inputs have none, and a
  /// grey hairline on white over navy reads as a mistake.
  static final OutlineInputBorder _heroFieldBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.control),
    borderSide: BorderSide.none,
  );

  /// "All areas in the Isle of Man", the website's second hero field. Opens the
  /// island's towns in a sheet.
  Widget _locationBar() {
    final chosen = _location;
    return InkWell(
      onTap: _pickLocation,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Row(
          children: [
            Expanded(
              child: chosen == null
                  ? const Text.rich(
                      TextSpan(
                        text: 'All areas in the ',
                        children: [
                          TextSpan(
                            text: 'Isle of Man',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 16, color: AppColors.ink),
                    )
                  : Text(
                      chosen,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink),
                    ),
            ),
            const Icon(Icons.arrow_drop_down, color: AppColors.slate),
          ],
        ),
      ),
    );
  }

  Future<void> _pickLocation() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text('Area',
                    style: TextStyle(
                        fontSize: AppText.section,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink)),
              ),
              ListTile(
                title: const Text('All areas in the Isle of Man'),
                // An empty string is the sheet's way of saying "clear it" -
                // returning null is what a dismissed sheet gives back, and the
                // two must not mean the same thing.
                onTap: () => Navigator.of(sheetContext).pop(''),
              ),
              for (final town in kImTowns)
                ListTile(
                  title: Text(town),
                  onTap: () => Navigator.of(sheetContext).pop(town),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _location = picked.isEmpty ? null : picked);
  }

  /// The big blue button. Runs whatever the two fields above it say.
  Widget _searchButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: _runHeroSearch,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.cta,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            _searchButtonLabel,
            maxLines: 1,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }

  /// Runs the hero: whatever was typed, inside the section the tabs are on,
  /// limited to the chosen area. An empty box with an area picked is a valid
  /// search - "everything in Ramsey" - so nothing here is required.
  void _runHeroSearch() {
    FocusScope.of(context).unfocus();
    final term = _search.text.trim();
    final filters = <String, dynamic>{..._sectionBase};
    if (term.isNotEmpty) filters['keyword'] = term;
    if (_location != null) filters['location'] = _location;
    if (term.isNotEmpty) RecentSearches.add(term);

    final scope = _scope;
    final title = term.isNotEmpty
        ? term
        : _location ?? (scope == null ? 'Marketplace' : sectionLabel(scope.name));

    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => ResultsScreen(
            api: widget.api,
            auth: widget.auth,
            category: scope,
            baseFilters: filters,
            titleOverride: title,
          ),
        ))
        .then((_) => _loadShortcuts());
  }

  /// A single Featured Dealer banner (rotating hourly) on the Cars & Motors and
  /// Marketplace tabs. Neither Property nor Farming has a dealer sector behind
  /// it, so it stays off both.
  Widget _featuredDealers() {
    if (_tab == 2 || _tab == 3) return const SizedBox.shrink();
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
            ? 'See all in Property'
            : _tab == 3
                ? 'See all in Farming'
                : 'See all in Marketplace';
    return InkWell(
      onTap: _openSeeAll,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: AppColors.line),
            bottom: BorderSide(color: AppColors.line),
          ),
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
    // On Marketplace this row is the same journey as the Discover tab in the
    // bottom bar, so it only earns its place on the scoped tabs.
    if (_tab == 1) return const SizedBox.shrink();
    final scope = _scope;
    final subtitle = scope == null
        ? 'Swipe through everything on the island'
        : 'Swipe through ${sectionLabel(scope.name)}';
    return InkWell(
      onTap: _openDiscover,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
        decoration: const BoxDecoration(
          color: Colors.white,
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
                  // Set exactly like "My Last Search" above it - same size,
                  // same weight, same subtitle - so the three rows read as one
                  // list rather than as three separately designed things.
                  const Text(
                    'Discover',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
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
        // One section to a line, artwork on the left - DoneDeal's shape, which
        // is what Chris asked for after seeing the two-up cards. A whole
        // section fits on one screen this way; the cards showed four.
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

/// Sections that ship with their own illustration (`assets/cat/<slug>.png`).
/// Drawn objects rather than flat glyphs, which is what a buyer scanning a
/// classifieds home screen recognises fastest. Anything not listed here falls
/// back to the website's own category image, then to the flat icon, so adding a
/// new section never leaves a blank tile.
const Set<String> _catArt = {
  'animals',
  'baby-and-kids',
  'bedding-and-feeding',
  'boat-and-jet-skis',
  'boat-extras',
  'business',
  'campers',
  'car-extras',
  'car-parts',
  'caravans',
  'cars-and-motors',
  'cars-for-breaking',
  'cars-for-sale',
  'clothes-and-lifestyle',
  'coaches-and-buses',
  'commercial',
  'damaged-repairables',
  'dhs-rentals',
  'electric-cars',
  'electronics',
  'everything',
  'farm-machinery',
  'farm-services',
  'farm-sheds',
  'farm-tools',
  'farmers-market',
  'farmers-noticeboard',
  'farming',
  'feeding-equipment',
  'fencing-equipment',
  'fertilizers',
  'for-sale',
  'free-stuff',
  'holidays-and-tickets',
  'house-and-diy',
  'jobs',
  'land-and-farms',
  'livestock',
  'lost-and-found',
  'modified-cars',
  'motorbike-extras',
  'motorbikes',
  'music-and-education',
  'new-homes',
  'other-farming',
  'other-motors',
  'parking',
  'plant-machinery',
  'poultry',
  'property',
  'quads',
  'rally-cars',
  'scooters',
  'services',
  'sharing',
  'sold',
  'sports-and-hobbies',
  'to-rent',
  'tractors',
  'trailers',
  'trucks',
  'vans-and-commercials',
  'vintage-bikes',
  'vintage-cars',
  'vintage-machinery',
  'wanted',
  'weird-and-wonderful',
  'whats-on',
};

String? _catArtFor(String slug) =>
    _catArt.contains(slug) ? 'assets/cat/$slug.png' : null;

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

  /// Each section shows its own hero from the website's settings: Property gets
  /// the site's `property` banner and Farming its `farming` one, everything else
  /// the home banner.
  /// Changing them on the site changes them here too; we fall back to the
  /// last-known image if settings haven't loaded yet.
  Widget _heroBackground() {
    return ValueListenableBuilder<Map<String, String>>(
      valueListenable: SiteSettings.values,
      builder: (context, _, _) {
        final sectionBanner = tab == 2
            ? SiteSettings.propertyBanner
            : tab == 3
                ? SiteSettings.farmingBanner
                : null;
        final url = sectionBanner ?? SiteSettings.homeBanner ?? _heroImage;
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
    // A backdrop, not a band: the block above decides how tall this is.
    //
    // The website's hero is navy first and photograph second - the banner is
    // only visible where it bleeds in from the right-hand edge, behind the
    // Search button. Anything more and the white fields stop reading.
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(decoration: BoxDecoration(color: AppColors.navy)),
        // The section banner...
        Positioned.fill(child: _heroBackground()),
        // ...under a navy wash that is solid on the left and thins out to the
        // right, so the photo only shows where the site's does.
        //
        // A gradient laid over the photo rather than a ShaderMask cut out of
        // it: the mask renders as nothing at all on some web/Impeller
        // back-ends, and a hero that silently loses its photograph is not worth
        // the tidier code.
        //
        // The wash is heavy on purpose. At phone width the fields cover the
        // left of the banner, so all the photo had left to show was a crop of
        // whoever happens to be standing on the right of it - a face looming
        // out from behind the search box, which reads as a mistake rather than
        // as a photograph. Held down to a texture it does what the site's
        // does: stops the navy being a flat slab.
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  AppColors.navy,
                  AppColors.navy,
                  Color(0xE0132740),
                ],
                stops: [0.0, 0.45, 1.0],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The Discover mark - the same layered-cards glyph the toolbar uses for the
/// tab, drawn bare.
///
/// It used to sit on a pale blue rounded tile. A glyph on a tinted rounded
/// square is the house style of every app template going, and it put this row
/// out of line with the two above it, which are a plain clock and a plain star.
/// Three rows, three plain icons, one left edge.
class _SwipeDeckMark extends StatelessWidget {
  const _SwipeDeckMark();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 22,
      height: 22,
      child: Icon(Icons.style_rounded, color: AppColors.slate, size: 22),
    );
  }
}

/// A marketplace section on one line, DoneDeal's shape: the section's artwork
/// on the left, the name, then its live listing count.
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
    final art = _catArtFor(category.slug);
    final useImage =
        art == null && style == _fallbackStyle && category.imageUrl.isNotEmpty;
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.line)),
          ),
          child: Row(
            children: [
              SizedBox(
                // The artwork is a drawn object rather than a flat glyph, so it
                // gets a wide box - a van or a tractor needs the width more
                // than an icon does, and at 46 the detail turned to mush.
                width: art != null ? 66 : 46,
                height: 52,
                child: Center(
                  child: art != null
                      ? Image.asset(art, fit: BoxFit.contain)
                      : useImage
                          ? Padding(
                              padding: const EdgeInsets.all(6),
                              child: NetworkPhoto(
                                  url: category.imageUrl, fit: BoxFit.contain),
                            )
                          // Sections with no artwork keep the flat icon on its
                          // tinted tile, so a new one is never a blank line.
                          : Container(
                              width: 46,
                              height: 46,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: style.color.withValues(alpha: 0.10),
                                borderRadius:
                                    BorderRadius.circular(AppRadius.image),
                              ),
                              child: Icon(style.icon,
                                  color: style.color, size: 23),
                            ),
                ),
              ),
              const SizedBox(width: 14),
              // Name on the left, count on the right - the classifieds layout,
              // and it keeps every line to a single row.
              Expanded(
                child: Text(
                  sectionLabel(category.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // Not bold. There are a dozen of these in a column, and when
                  // every line is semibold none of them is emphasised - the
                  // list just looks shouted. The rows above it are actions;
                  // these are a menu.
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Blank until the live count lands, rather than a "0 ads" that
              // would be wrong for the second it took to arrive.
              Text(
                liveCount != null
                    ? '${_grouped(liveCount!)} ${liveCount == 1 ? 'ad' : 'ads'}'
                    : '',
                maxLines: 1,
                style: const TextStyle(
                  fontSize: AppText.meta,
                  color: AppColors.slate,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
