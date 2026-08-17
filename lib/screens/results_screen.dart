import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/ad.dart';
import '../models/ad_attribute.dart';
import '../models/ad_filters.dart';
import '../models/category.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../services/vehicle_catalog.dart';
import '../utils/listing_specs.dart';
import '../utils/vehicle_names.dart';
import '../widgets/card_image_carousel.dart';
import '../widgets/network_photo.dart';
import '../widgets/featured_dealers_strip.dart';
import 'ad_detail_screen.dart';
import 'auth/auth_screen.dart';
import 'make_model_picker_screen.dart';
import 'property_map_screen.dart';
import 'swipe_screen.dart';

/// Which shape the results list uses for each listing.
///
/// `false` - photo on top, full width: the photo sells the item, and it is the
/// shape DoneDeal's own app uses.
/// `true`  - photo on the left with the details beside it: fits roughly three
/// times as many listings on a screen.
///
/// One line to flip, and both shapes are kept in step with the rest of the
/// styling, so this can be switched without a rewrite.
const bool kCompactListingRows = false;

const List<String> kImTowns = [
  'Douglas', 'Onchan', 'Ramsey', 'Peel', 'Castletown', 'Port Erin',
  'Port St Mary', 'Ballasalla', 'Laxey', 'Kirk Michael', 'Ballaugh',
  'Sulby', 'Andreas', 'Foxdale', 'Colby', 'Crosby', 'Glen Vine', 'Santon',
];

/// A DoneDeal-style search-results screen: a scrolling list of listing cards
/// for a category (or a keyword search), with a Filter button top-right and a
/// floating Filter button that appears as you scroll. Tapping Filter opens a
/// sheet to narrow by price, town, seller type, for-sale/wanted and sort.
class ResultsScreen extends StatefulWidget {
  final ApiService api;
  final AuthService auth;
  final Category? category;

  /// Base filters always applied (e.g. a keyword search from Browse).
  final Map<String, dynamic> baseFilters;
  final String? titleOverride;

  /// Filters to start with (e.g. the make/year/price picked in the car-search
  /// panel), so they're pre-applied and shown in the Filter sheet.
  final AdFilters? initialFilters;

  const ResultsScreen({
    super.key,
    required this.api,
    required this.auth,
    this.category,
    this.baseFilters = const {},
    this.titleOverride,
    this.initialFilters,
  });

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  final ScrollController _scroll = ScrollController();
  final List<Ad> _ads = [];

  late AdFilters _filters = widget.initialFilters ?? const AdFilters();
  int _page = 1;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _exhausted = false;
  String? _error;
  bool _showFab = false;

  static const int _pageSize = 20;

  String get _title =>
      widget.titleOverride ?? widget.category?.name ?? 'Search results';

  Map<String, dynamic> get _mergedFilters => {
        ...widget.baseFilters,
        ..._filters.toQuery(),
      };

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadFirstPage();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final show = _scroll.offset > 320;
    if (show != _showFab) setState(() => _showFab = show);
    if (_scroll.position.pixels >=
        _scroll.position.maxScrollExtent - 600) {
      _loadMore();
    }
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await widget.api.search(
        categoryId: widget.category?.id,
        isVehicle: widget.category?.isVehicle ?? false,
        page: 1,
        limit: _pageSize,
        filters: _mergedFilters,
      );
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
    if (_loadingMore || _exhausted || _loading) return;
    _loadingMore = true;
    try {
      final next = _page + 1;
      final res = await widget.api.search(
        categoryId: widget.category?.id,
        isVehicle: widget.category?.isVehicle ?? false,
        page: next,
        limit: _pageSize,
        filters: _mergedFilters,
      );
      if (!mounted) return;
      setState(() {
        final seen = _ads.map((a) => a.id).toSet();
        _ads.addAll(res.ads.where((a) => !seen.contains(a.id)));
        _page = next;
        if (res.ads.isEmpty || res.ads.length < _pageSize) _exhausted = true;
      });
    } catch (_) {
      // Non-fatal; the list keeps what it has and retries on the next scroll.
    } finally {
      _loadingMore = false;
    }
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<AdFilters>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (_) => _FilterSheet(
        api: widget.api,
        category: widget.category,
        baseFilters: widget.baseFilters,
        initial: _filters,
      ),
    );
    if (result != null) {
      setState(() => _filters = result);
      _scroll.jumpTo(0);
      _loadFirstPage();
    }
  }

  Future<void> _saveSearch() async {
    final auth = widget.auth;
    final messenger = ScaffoldMessenger.of(context);
    if (!auth.isLoggedIn) {
      final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) =>
            AuthScreen(auth: auth, reason: 'Sign in to save searches'),
      ));
      if (ok != true) return;
      auth.refreshProfile();
    }
    final user = auth.user;
    if (user == null) return;
    final filters = <String, dynamic>{
      ..._mergedFilters,
      if (widget.category != null) 'categories': '${widget.category!.id}',
    };
    final title = widget.titleOverride ??
        widget.category?.name ??
        'All of Listit';
    try {
      await widget.api.saveSearch(userId: user.id, title: title, filters: filters);
      messenger.showSnackBar(const SnackBar(
        content: Text('Search saved - find it under the search bar.'),
        backgroundColor: AppColors.success,
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e.toString()),
        backgroundColor: AppColors.danger,
      ));
    }
  }

  void _openSwipe() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SwipeScreen(
        api: widget.api,
        auth: widget.auth,
        category: widget.category,
        filters: _mergedFilters,
        titleOverride: widget.titleOverride,
      ),
    ));
  }

  void _openDetail(Ad ad) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AdDetailScreen(
          adId: ad.id, api: widget.api, preview: ad, auth: widget.auth),
    ));
  }

  /// Property sections (top 106, For Sale 289, To Rent 290, Commercial 288,
  /// Sold 294) get the map view - their ads carry lat/lng coordinates.
  bool get _isPropertyCategory =>
      const {106, 288, 289, 290, 294}.contains(widget.category?.id);

  void _openMap() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PropertyMapScreen(
        api: widget.api,
        auth: widget.auth,
        ads: List<Ad>.from(_ads),
        title: '$_title map',
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final active = _filters.activeCount;
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(_title),
        actions: [
          if (_isPropertyCategory)
            IconButton(
              tooltip: 'Map view',
              icon: const Icon(Icons.map_outlined),
              onPressed: _ads.isEmpty ? null : _openMap,
            ),
          IconButton(
            tooltip: 'Save search',
            icon: const Icon(Icons.bookmark_add_outlined),
            onPressed: _saveSearch,
          ),
          IconButton(
            tooltip: 'Swipe these',
            icon: const Icon(Icons.style_rounded),
            onPressed: _ads.isEmpty ? null : _openSwipe,
          ),
          // Filter button, top-right, with a count badge when filters are on.
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  tooltip: 'Filter',
                  icon: const Icon(Icons.tune_rounded),
                  onPressed: _openFilters,
                ),
                if (active > 0)
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                          color: AppColors.primary, shape: BoxShape.circle),
                      constraints:
                          const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text('$active',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(child: _body()),
      floatingActionButton: _showFab
          ? SizedBox(
              // Full-width Filter bar, DoneDeal-style, rather than a small pill.
              width: MediaQuery.of(context).size.width - 32,
              height: 46,
              child: ElevatedButton.icon(
                onPressed: _openFilters,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.control)),
                ),
                icon: const Icon(Icons.tune_rounded, color: Colors.white),
                label: Text(
                  active > 0 ? 'Filter ($active)' : 'Filter',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: AppText.listing,
                      fontWeight: FontWeight.w600),
                ),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_error != null) {
      return _ResultsError(message: _error!, onRetry: _loadFirstPage);
    }
    // A Featured Estate Agents / Dealers strip leads the list for the sections
    // that have featured businesses (Property, Cars & Motors).
    final sector = _featuredSector;
    final header = sector == null ? 0 : 1;
    return Column(
      children: [
        _resultsBar(),
        Expanded(
          child: _ads.isEmpty
              ? _emptyState()
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 88),
                  itemCount: header + _ads.length + (_exhausted ? 0 : 1),
                  itemBuilder: (context, i) {
                    if (header == 1 && i == 0) {
                      return FeaturedDealersStrip(
                        api: widget.api,
                        auth: widget.auth,
                        sector: sector!,
                        title: sector == 'property'
                            ? 'Featured Estate Agents'
                            : 'Featured Dealers',
                        edgeInset: 4,
                      );
                    }
                    final idx = i - header;
                    if (idx >= _ads.length) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                            child: SizedBox(
                                width: 26,
                                height: 26,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: AppColors.primary))),
                      );
                    }
                    final ad = _ads[idx];
                    return kCompactListingRows
                        ? _CompactResultCard(
                            ad: ad,
                            api: widget.api,
                            auth: widget.auth,
                            onTap: () => _openDetail(ad))
                        : _ResultCard(
                            ad: ad,
                            api: widget.api,
                            auth: widget.auth,
                            onTap: () => _openDetail(ad));
                  },
                ),
        ),
      ],
    );
  }

  /// Which featured-business strip (if any) leads this section's results.
  /// Only the top Property (106) and Cars & Motors (62) sections carry one.
  String? get _featuredSector {
    switch (widget.category?.id) {
      case 106:
        return 'property';
      case 62:
        return 'motors';
      default:
        return null;
    }
  }

  Widget _resultsBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Found ${_grouped(_total)} ${_total == 1 ? 'ad' : 'ads'}',
              style: const TextStyle(
                  fontWeight: FontWeight.w700, color: AppColors.ink),
            ),
          ),
          TextButton.icon(
            onPressed: _openFilters,
            icon: const Icon(Icons.sort_rounded, size: 18),
            label: Text(_filters.sort.label,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded,
                size: 48, color: AppColors.muted),
            const SizedBox(height: 14),
            const Text('No ads match these filters.',
                style: TextStyle(color: AppColors.slate, fontSize: 15)),
            if (_filters.hasAny) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () {
                  setState(() => _filters = const AdFilters());
                  _loadFirstPage();
                },
                child: const Text('Clear filters'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _grouped(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

String _priceLabel(Ad ad) {
  if (ad.isFree) return 'Free';
  final p = ad.price;
  final whole = p == p.roundToDouble();
  final s = whole ? p.toStringAsFixed(0) : p.toStringAsFixed(2);
  return '£${_grouped(int.tryParse(s.split('.').first) ?? 0)}${whole ? '' : '.${s.split('.').last}'}';
}

/// A DoneDeal-style results card: big photo up top with the seller type, then
/// price, title and location beneath.
class _ResultCard extends StatelessWidget {
  final Ad ad;
  final ApiService api;
  final AuthService auth;
  final VoidCallback onTap;
  const _ResultCard({
    required this.ad,
    required this.api,
    required this.auth,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Spotlight (paid-promoted) ads get an amber glow + border and a badge,
    // exactly like the website, so they stand out in the results.
    final spot = ad.isSpotlight;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.card),
          clipBehavior: Clip.antiAlias,
          elevation: 0,
          child: InkWell(
            onTap: onTap,
            child: Container(
              // Spotlight (paid-promoted) ads are marked with an amber border
              // and a badge rather than a glow - the border is what the eye
              // needs, and the glow made every promoted ad look like a
              // notification.
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(
                  color: spot ? AppColors.save : AppColors.line,
                  width: spot ? 1.6 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Dealer / estate-agent name sits on top of the card, as on
                  // DoneDeal, so traders read as a business at a glance.
                  if (ad.isDealer) _dealerHeader(),
                  Stack(
                    children: [
                      CardImageCarousel(
                        images: ad.images,
                        aspectRatio: 16 / 9,
                      ),
                      if (spot)
                        Positioned(
                          left: 0,
                          top: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: const BoxDecoration(
                              color: AppColors.save,
                              borderRadius: BorderRadius.only(
                                  bottomRight: Radius.circular(AppRadius.image)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.bolt_rounded,
                                    size: 15, color: Colors.white),
                                SizedBox(width: 3),
                                Text('Spotlight',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: AppText.micro,
                                        fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        ),
                      if (ad.underOffer)
                        Positioned(
                          left: spot ? null : 10,
                          right: spot ? 10 : null,
                          top: 10,
                          child: _tag('Under offer', AppColors.primary),
                        ),
                    ],
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Price on the left, save heart directly across from it.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              _priceLabel(ad),
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          _SaveHeart(ad: ad, api: api, auth: auth),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        ad.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: AppText.listing,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                          height: 1.25,
                        ),
                      ),
                      _specChipsRow(ad),
                      if (ad.location.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined,
                                size: 15, color: AppColors.muted),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                ad.location,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 13, color: AppColors.slate),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The DoneDeal-style "key details" row - "3 Bed · 3 Bath · 90 m² · House"
  /// for property, "2021 · 31,000 mi · Petrol · Manual" for vehicles.
  Widget _specChipsRow(Ad ad) {
    final chips = specChipsFor(ad);
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (var i = 0; i < chips.length; i++) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text('·',
                    style: TextStyle(fontSize: 13, color: AppColors.muted)),
              ),
            Text(chips[i],
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.slate)),
          ],
        ],
      ),
    );
  }

  Widget _dealerHeader() {
    final name = ad.displayName.isEmpty ? 'Dealer' : ad.displayName;
    final label = ad.isProperty ? 'Estate Agent' : 'Independent Dealership';
    final rating =
        double.tryParse('${ad.raw['average_rating'] ?? ''}') ?? 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      child: Row(
        children: [
          _dealerLogo(),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink)),
                const SizedBox(height: 1),
                Row(
                  children: [
                    const Icon(Icons.verified_rounded,
                        size: 13, color: AppColors.success),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.slate,
                              fontWeight: FontWeight.w600)),
                    ),
                    if (rating > 0) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.star_rounded,
                          size: 14, color: AppColors.save),
                      const SizedBox(width: 2),
                      Text(rating.toStringAsFixed(1),
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.slate,
                              fontWeight: FontWeight.w700)),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The dealer's real logo (from the ad's `logo` / `seller_image`), falling
  /// back to a generic business icon when they haven't uploaded one.
  Widget _dealerLogo() {
    final url = ad.dealerLogo;
    Widget box(Widget child) => Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: AppColors.line),
          ),
          clipBehavior: Clip.antiAlias,
          alignment: Alignment.center,
          child: child,
        );
    if (url.isEmpty) {
      return box(Icon(
          ad.isProperty ? Icons.apartment_rounded : Icons.storefront_rounded,
          size: 18,
          color: AppColors.primary));
    }
    return box(Image.network(
      url,
      width: 36,
      height: 36,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => Icon(
          ad.isProperty ? Icons.apartment_rounded : Icons.storefront_rounded,
          size: 18,
          color: AppColors.primary),
    ));
  }

  Widget _tag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.image),
      ),
      child: Text(text,
          style: const TextStyle(
              color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

/// A white circular save heart shown on result-card photos (DoneDeal-style).
/// Optimistically toggles and prompts sign-in when needed.
/// A compact listing row: photo on the left, everything else stacked beside it.
/// Trades the big photo for roughly three times as many listings on screen -
/// the classifieds-list shape rather than the card-feed shape.
class _CompactResultCard extends StatelessWidget {
  final Ad ad;
  final ApiService api;
  final AuthService auth;
  final VoidCallback onTap;
  const _CompactResultCard({
    required this.ad,
    required this.api,
    required this.auth,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final spot = ad.isSpotlight;
    final chips = specChipsFor(ad);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: spot ? AppColors.save : AppColors.line,
                width: spot ? 1.6 : 1,
              ),
            ),
            padding: const EdgeInsets.all(8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.image),
                  child: SizedBox(
                    width: 124,
                    height: 93,
                    child: ad.images.isEmpty
                        ? Container(
                            color: AppColors.surface,
                            alignment: Alignment.center,
                            child: const Icon(Icons.image_not_supported_outlined,
                                color: AppColors.muted, size: 22),
                          )
                        : NetworkPhoto(url: ad.images.first, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _priceLabel(ad),
                              style: const TextStyle(
                                fontSize: AppText.section,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          if (spot)
                            const Padding(
                              padding: EdgeInsets.only(right: 4),
                              child: Icon(Icons.bolt_rounded,
                                  size: 16, color: AppColors.save),
                            ),
                          _SaveHeart(ad: ad, api: api, auth: auth, compact: true),
                        ],
                      ),
                      Text(
                        ad.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: AppText.body,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                          height: 1.25,
                        ),
                      ),
                      if (chips.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          chips.join('  \u00b7  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: AppText.meta, color: AppColors.slate),
                        ),
                      ],
                      const SizedBox(height: 3),
                      Text(
                        [
                          if (ad.location.isNotEmpty) ad.location,
                          if (ad.isDealer && ad.displayName.isNotEmpty)
                            ad.displayName,
                        ].join('  \u00b7  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: AppText.meta, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SaveHeart extends StatefulWidget {
  final Ad ad;
  final ApiService api;
  final AuthService auth;
  /// The compact row has less space, so the heart loses its padding there.
  final bool compact;
  const _SaveHeart({
    required this.ad,
    required this.api,
    required this.auth,
    this.compact = false,
  });

  @override
  State<_SaveHeart> createState() => _SaveHeartState();
}

class _SaveHeartState extends State<_SaveHeart> {
  late bool _saved = widget.ad.isSaved;
  bool _busy = false;

  Future<void> _toggle() async {
    if (_busy) return;
    if (!widget.auth.isLoggedIn) {
      final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => AuthScreen(auth: widget.auth, reason: 'Sign in to save ads'),
      ));
      if (ok != true) return;
      widget.auth.refreshProfile();
    }
    final user = widget.auth.user;
    if (user == null) return;
    final was = _saved;
    setState(() {
      _saved = !was;
      _busy = true;
    });
    try {
      if (was) {
        await widget.api.unsaveAd(userId: user.id, adId: widget.ad.id);
      } else {
        await widget.api.saveAd(userId: user.id, adId: widget.ad.id);
      }
    } catch (_) {
      if (mounted) setState(() => _saved = was);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _saved
          ? AppColors.danger.withValues(alpha: 0.10)
          : AppColors.surface,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _toggle,
        child: Padding(
          padding: EdgeInsets.all(widget.compact ? 5 : 10),
          child: Icon(
            _saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            size: widget.compact ? 19 : 28,
            color: _saved ? AppColors.danger : AppColors.slate,
          ),
        ),
      ),
    );
  }
}

// --- Filter sheet -----------------------------------------------------------

class _FilterSheet extends StatefulWidget {
  final ApiService api;
  final Category? category;
  final Map<String, dynamic> baseFilters;
  final AdFilters initial;
  const _FilterSheet({
    required this.api,
    required this.category,
    required this.baseFilters,
    required this.initial,
  });

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late AdFilters _draft = widget.initial;
  final _minCtrl = TextEditingController();
  final _maxCtrl = TextEditingController();

  Timer? _debounce;
  int? _count; // live "Show N results" count, null while loading
  bool _counting = false;

  // Dynamic per-category attribute filters (Bedrooms, Storage, ...), pulled
  // from the backend so they mirror the website for whichever category we're in.
  List<AdAttribute> _attrs = const [];
  bool _attrsLoading = false;

  // Vehicle sections only show for vehicle categories (Cars For Sale, ...).
  bool get _isVehicle => widget.category?.isVehicle ?? false;

  // Year / mileage option lists for the vehicle dropdowns.
  static final List<int> _years = [
    for (var y = DateTime.now().year; y >= 1990; y--) y
  ];
  static const List<int> _mileages = [
    10000, 20000, 30000, 50000, 75000, 100000, 150000,
  ];
  // Canonical option sets - matched loosely (LIKE) against the messier stored
  // values, so "Petrol" also catches "PETROL/ELECTRIC HYBRID" etc.
  static const List<String> _fuelOpts = ['Petrol', 'Diesel', 'Electric', 'Hybrid'];
  static const List<String> _transOpts = ['Automatic', 'Manual'];
  static const List<String> _bodyOpts = [
    'Hatchback', 'Estate', 'SUV', 'Saloon', 'Coupe',
    'Convertible', 'MPV', 'Van', 'Motorbike', 'Motorhome',
  ];
  static const List<String> _colourOpts = [
    'Black', 'White', 'Silver', 'Grey', 'Blue',
    'Red', 'Green', 'Yellow', 'Orange', 'Gold',
  ];

  @override
  void initState() {
    super.initState();
    _minCtrl.text = widget.initial.priceFrom ?? '';
    _maxCtrl.text = widget.initial.priceTo ?? '';
    _refreshCount();
    if (!_isVehicle) _loadAttributes();
  }

  /// Fetch the category's filterable attributes (and its parent's, since the
  /// website defines most attributes on the top-level category), then keep the
  /// ones that make sense as filters - a set of options to pick from.
  Future<void> _loadAttributes() async {
    final cat = widget.category;
    if (cat == null) return;
    setState(() => _attrsLoading = true);
    try {
      final results = await Future.wait([
        widget.api.fetchAttributes(cat.id),
        if (cat.parentId > 0) widget.api.fetchAttributes(cat.parentId),
      ]);
      final seen = <String>{};
      final merged = <AdAttribute>[];
      for (final list in results) {
        for (final a in list) {
          if (a.isFilter && a.hasOptions && seen.add(a.key)) merged.add(a);
        }
      }
      if (mounted) {
        setState(() {
          _attrs = merged;
          _attrsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _attrsLoading = false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  void _update(AdFilters f) {
    setState(() => _draft = f);
    _refreshCount();
  }

  void _refreshCount() {
    _debounce?.cancel();
    setState(() => _counting = true);
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final res = await widget.api.search(
          categoryId: widget.category?.id,
          isVehicle: widget.category?.isVehicle ?? false,
          limit: 1,
          filters: {...widget.baseFilters, ..._draft.toQuery()},
        );
        if (mounted) {
          setState(() {
            _count = res.total;
            _counting = false;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _count = null;
            _counting = false;
          });
        }
      }
    });
  }

  void _reset() {
    _minCtrl.clear();
    _maxCtrl.clear();
    _update(const AdFilters());
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, controller) {
          return Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Expanded(
                      child: Text('Filters',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700)),
                    ),
                    TextButton(
                      onPressed: _draft.hasAny ? _reset : null,
                      child: const Text('Reset all'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  children: [
                    _sectionTitle('Sort'),
                    _chips<AdSort>(
                      values: AdSort.values,
                      selected: _draft.sort,
                      label: (s) => s.label,
                      onSelected: (s) => _update(_draft.copyWith(sort: s)),
                    ),
                    if (_isVehicle) ..._vehicleSections(),
                    ..._attributeSections(),
                    const SizedBox(height: 18),
                    _sectionTitle('Ad type'),
                    _chips<int?>(
                      values: const [null, 1, 2],
                      selected: _draft.adType,
                      label: (v) =>
                          v == null ? 'Any' : (v == 1 ? 'For sale' : 'Wanted'),
                      onSelected: (v) => _update(v == null
                          ? _draft.copyWith(clearAdType: true)
                          : _draft.copyWith(adType: v)),
                    ),
                    const SizedBox(height: 18),
                    _sectionTitle('Seller'),
                    // Multi-select: tick any combination. None ticked = everyone.
                    _multiSelect(
                      const [
                        MapEntry('private', 'Private sellers'),
                        MapEntry('trader', 'Traders'),
                        MapEntry('agent', 'Estate agents'),
                      ],
                      _draft.sellerTypes,
                      (v) => _update(_draft.copyWith(sellerTypes: v)),
                    ),
                    const SizedBox(height: 10),
                    _checkRow(
                      icon: Icons.star_rounded,
                      label: '4+ rated sellers only',
                      value: _draft.minRating != null,
                      onChanged: (v) => _update(v
                          ? _draft.copyWith(minRating: 4)
                          : _draft.copyWith(clearMinRating: true)),
                    ),
                    const SizedBox(height: 18),
                    _sectionTitle('Price (£)'),
                    Row(
                      children: [
                        Expanded(child: _priceField(_minCtrl, 'Min', true)),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Text('to', style: TextStyle(color: AppColors.slate)),
                        ),
                        Expanded(child: _priceField(_maxCtrl, 'Max', false)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _checkRow(
                      label: 'Show ads with a price only',
                      value: _draft.priceOnly,
                      onChanged: (v) =>
                          _update(_draft.copyWith(priceOnly: v)),
                    ),
                    const SizedBox(height: 18),
                    _sectionTitle('Town / Area'),
                    DropdownButtonFormField<String>(
                      initialValue: _draft.location,
                      isExpanded: true,
                      decoration: _dec('Anywhere on the island'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Anywhere on the island')),
                        for (final t in kImTowns)
                          DropdownMenuItem(value: t, child: Text(t)),
                      ],
                      onChanged: (v) => _update(v == null
                          ? _draft.copyWith(clearLocation: true)
                          : _draft.copyWith(location: v)),
                    ),
                  ],
                ),
              ),
              // Show results button
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(_draft),
                      child: Text(
                        _counting || _count == null
                            ? 'Show results'
                            : 'Show ${_grouped(_count!)} ${_count == 1 ? 'result' : 'results'}',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- Dynamic per-category attribute sections -----------------------------

  List<Widget> _attributeSections() {
    if (_attrs.isEmpty) {
      if (_attrsLoading) {
        return [
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Center(
              child: SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        ];
      }
      return const [];
    }
    return [
      const SizedBox(height: 6),
      for (final attr in _attrs)
        _collapsible(
          attr.label,
          (_draft.attributes[attr.key] ?? const []).join(', '),
          _multiSelect(
            [for (final o in attr.options) MapEntry(o, o)],
            _draft.attributes[attr.key] ?? const [],
            (v) => _setAttr(attr.key, v),
          ),
        ),
    ];
  }

  void _setAttr(String key, List<String> values) {
    final next = Map<String, List<String>>.from(_draft.attributes);
    if (values.isEmpty) {
      next.remove(key);
    } else {
      next[key] = values;
    }
    _update(_draft.copyWith(attributes: next));
  }

  // --- Vehicle filter sections (collapsible, DoneDeal-style) ---------------

  List<Widget> _vehicleSections() {
    return [
      const SizedBox(height: 6),
      _makeModelRow(),
      _collapsible(
        'Year',
        _rangeSummary(_draft.yearFrom, _draft.yearTo),
        Row(
          children: [
            Expanded(
              child: _miniDropdown<int>(
                hint: 'From',
                value: int.tryParse(_draft.yearFrom ?? ''),
                items: _years,
                label: (y) => '$y',
                onChanged: (v) => _update(v == null
                    ? _draft.copyWith(clearYearFrom: true)
                    : _draft.copyWith(yearFrom: '$v')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _miniDropdown<int>(
                hint: 'To',
                value: int.tryParse(_draft.yearTo ?? ''),
                items: _years,
                label: (y) => '$y',
                onChanged: (v) => _update(v == null
                    ? _draft.copyWith(clearYearTo: true)
                    : _draft.copyWith(yearTo: '$v')),
              ),
            ),
          ],
        ),
      ),
      _collapsible(
        'Mileage',
        (_draft.mileageTo ?? '').isEmpty
            ? ''
            : 'Up to ${_grouped(int.tryParse(_draft.mileageTo!) ?? 0)} miles',
        _miniDropdown<int>(
          hint: 'Max mileage',
          value: int.tryParse(_draft.mileageTo ?? ''),
          items: _mileages,
          label: (m) => 'Up to ${_grouped(m)} miles',
          onChanged: (v) => _update(v == null
              ? _draft.copyWith(clearMileageTo: true)
              : _draft.copyWith(mileageTo: '$v')),
        ),
      ),
      _collapsible(
        'Fuel type',
        _draft.fuelTypes.join(', '),
        _multiSelect(
          [for (final o in _fuelOpts) MapEntry(o, o)],
          _draft.fuelTypes,
          (v) => _update(_draft.copyWith(fuelTypes: v)),
        ),
      ),
      _collapsible(
        'Body type',
        _draft.bodyTypes.join(', '),
        _multiSelect(
          [for (final o in _bodyOpts) MapEntry(o, o)],
          _draft.bodyTypes,
          (v) => _update(_draft.copyWith(bodyTypes: v)),
        ),
      ),
      _collapsible(
        'Transmission',
        _draft.transmissions.join(', '),
        _multiSelect(
          [for (final o in _transOpts) MapEntry(o, o)],
          _draft.transmissions,
          (v) => _update(_draft.copyWith(transmissions: v)),
        ),
      ),
      _collapsible(
        'Colour',
        _draft.colours.join(', '),
        _multiSelect(
          [for (final o in _colourOpts) MapEntry(o, o)],
          _draft.colours,
          (v) => _update(_draft.copyWith(colours: v)),
        ),
      ),
    ];
  }

  String _rangeSummary(String? from, String? to) {
    final f = (from ?? '').isEmpty ? null : from;
    final t = (to ?? '').isEmpty ? null : to;
    if (f == null && t == null) return '';
    if (f != null && t != null) return '$f - $t';
    if (f != null) return 'From $f';
    return 'Up to $t';
  }

  /// The Make & model row - opens the full make/model picker (checkbox list
  /// with "Select all" and models under each make), rather than a busy chip
  /// grid. Shows a summary of what's picked.
  Widget _makeModelRow() {
    final picked = [
      ..._draft.makes.map(prettyVehicleName),
      ..._draft.models.map(prettyVehicleName),
    ];
    final summary = picked.isEmpty ? 'Any' : picked.join(', ');
    return InkWell(
      onTap: _openMakeModel,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          children: [
            const Text('Make & model',
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                summary,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: picked.isEmpty ? AppColors.slate : AppColors.primary,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.slate),
          ],
        ),
      ),
    );
  }

  Future<void> _openMakeModel() async {
    final res = await Navigator.of(context).push<MakeModelSelection>(
      MaterialPageRoute(
        builder: (_) => MakeModelPickerScreen(
          initialMakes: _draft.makes,
          initialModels: _draft.models,
          bucket: vehicleBucketForCategory(widget.category?.id),
        ),
      ),
    );
    if (res != null) {
      _update(_draft.copyWith(makes: res.makes, models: res.models));
    }
  }

  /// A collapsible filter section with a title and a summary of what's picked,
  /// matching DoneDeal's expandable filter rows.
  Widget _collapsible(String title, String summary, Widget child) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.line)),
        ),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 14),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          title: Text(title,
              style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
          subtitle: summary.isEmpty
              ? null
              : Text(summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
          children: [child],
        ),
      ),
    );
  }

  /// A DoneDeal-style option list: full-width tappable rows with the label on
  /// the left and the tick on the right, so it's easy to reach one-handed.
  /// Value kept, label shown.
  Widget _multiSelect(
    List<MapEntry<String, String>> options,
    List<String> selected,
    ValueChanged<List<String>> onChanged,
  ) {
    void toggle(String key) {
      final next = List<String>.from(selected);
      next.contains(key) ? next.remove(key) : next.add(key);
      onChanged(next);
    }

    return Column(
      children: [
        for (final o in options)
          InkWell(
            onTap: () => toggle(o.key),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(o.value,
                        style:
                            const TextStyle(fontSize: 15, color: AppColors.ink)),
                  ),
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: selected.contains(o.key),
                      onChanged: (_) => toggle(o.key),
                      activeColor: AppColors.primary,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _miniDropdown<T>({
    required String hint,
    required T? value,
    required List<T> items,
    required String Function(T) label,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColors.line),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          hint: Text(hint,
              style: const TextStyle(fontSize: 14.5, color: AppColors.muted)),
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              color: AppColors.slate),
          style: const TextStyle(
              fontSize: 14.5, color: AppColors.ink, fontWeight: FontWeight.w600),
          items: [
            DropdownMenuItem<T>(
                value: null,
                child:
                    Text(hint, style: const TextStyle(color: AppColors.muted))),
            for (final it in items)
              DropdownMenuItem<T>(value: it, child: Text(label(it))),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(t,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      );

  /// A DoneDeal-style checkbox row (e.g. "4+ rated sellers only").
  Widget _checkRow({
    IconData? icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 10),
            if (icon != null) ...[
              Icon(icon, size: 17, color: AppColors.save),
              const SizedBox(width: 4),
            ],
            Text(label,
                style: const TextStyle(fontSize: 14.5, color: AppColors.ink)),
          ],
        ),
      ),
    );
  }

  /// Single-select rows: label on the left, radio on the right (right-hand
  /// friendly), matching the DoneDeal-style filter list.
  Widget _chips<T>({
    required List<T> values,
    required T selected,
    required String Function(T) label,
    required ValueChanged<T> onSelected,
  }) {
    return Column(
      children: [
        for (final v in values)
          InkWell(
            onTap: () => onSelected(v),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(label(v),
                        style:
                            const TextStyle(fontSize: 15, color: AppColors.ink)),
                  ),
                  Icon(
                    v == selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 22,
                    color: v == selected ? AppColors.primary : AppColors.muted,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _priceField(TextEditingController c, String hint, bool isMin) {
    return TextField(
      controller: c,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: _dec(hint).copyWith(prefixText: '£ '),
      onChanged: (v) {
        final t = v.trim();
        _update(isMin
            ? (t.isEmpty
                ? _draft.copyWith(clearPriceFrom: true)
                : _draft.copyWith(priceFrom: t))
            : (t.isEmpty
                ? _draft.copyWith(clearPriceTo: true)
                : _draft.copyWith(priceTo: t)));
      },
    );
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
        ),
      );
}

class _ResultsError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ResultsError({required this.message, required this.onRetry});

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
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.slate, fontSize: 15)),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
