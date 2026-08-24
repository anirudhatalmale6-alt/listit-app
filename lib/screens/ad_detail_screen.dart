import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/ad.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/recently_viewed.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../utils/phone.dart';
import '../widgets/network_photo.dart';
import 'auth/auth_screen.dart';
import 'chat_screen.dart';
import 'photo_viewer_screen.dart';
import 'results_screen.dart';

/// Full listing view. Opened from a tap on a swipe card. Loads the richer
/// `/ads/:id` payload while showing the data we already have from the deck as
/// an instant preview, so the screen never flashes empty.
class AdDetailScreen extends StatefulWidget {
  final int adId;
  final ApiService api;
  final Ad? preview;

  /// Optional signed-in session, so the heart can save to the user's account.
  final AuthService? auth;

  const AdDetailScreen({
    super.key,
    required this.adId,
    required this.api,
    this.preview,
    this.auth,
  });

  @override
  State<AdDetailScreen> createState() => _AdDetailScreenState();
}

/// Height of the photo gallery at rest. Shared by the app bar and the scroll
/// listener, which have to agree or the header swaps at the wrong moment.
const double _kGalleryHeight = 320;

class _AdDetailScreenState extends State<AdDetailScreen> {
  final PageController _gallery = PageController();
  int _photoIndex = 0;

  Ad? _ad;
  String? _error;
  bool _saved = false;
  bool _saving = false;
  bool _descExpanded = false;
  bool _disclaimerExpanded = false;
  bool _showMap = false; // dealer location row, opened out
  bool _showHours = false; // dealer opening hours, opened out
  bool _reviewsExpanded = false;
  bool _calling = false; // revealing/dialling the seller's number
  List<Ad> _dealerStock = const [];
  int _sellerAdCount = 0; // live ads by this seller, for the seller panel
  List<Ad> _similar = const []; // other ads in the same subcategory

  final ScrollController _scroll = ScrollController();
  /// How far the header has collapsed, 0 (photo full height) to 1 (bar only).
  /// Drives the cross-fade between the two headers.
  double _collapse = 0;

  @override
  void initState() {
    super.initState();
    _ad = widget.preview;
    _saved = widget.preview?.isSaved ?? false;
    if (widget.preview != null) RecentlyViewed.add(widget.preview!);
    _scroll.addListener(_onScroll);
    _load();
  }

  /// The last stretch of the collapse is what the swap is keyed to, so the
  /// title only appears as the photo actually leaves. setState is skipped
  /// unless the value has really moved, so this is cheap on a scroll.
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final travel = _kGalleryHeight - kToolbarHeight -
        MediaQuery.paddingOf(context).top;
    final v = (_scroll.offset / (travel <= 0 ? 1 : travel)).clamp(0.0, 1.0);
    if ((v - _collapse).abs() > 0.01) setState(() => _collapse = v);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _gallery.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final full = await widget.api.fetchAd(widget.adId);
      if (!mounted) return;
      setState(() {
        _ad = full;
        _saved = _saved || full.isSaved;
      });
      RecentlyViewed.add(full); // remember it for "Recently Viewed"
      if (full.userId > 0) _loadSellerAds(full);
      _loadSimilar(full);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = widget.preview == null ? e.toString() : null;
      });
    }
  }

  /// Everything else this seller has live: the count for the seller panel, and
  /// for a trader also the "Our stock" strip DoneDeal shows. One request does
  /// both. Best-effort: silent if it fails.
  Future<void> _loadSellerAds(Ad ad) async {
    try {
      final res = await widget.api.search(
        limit: 12,
        filters: {'user_id': ad.userId},
      );
      if (!mounted) return;
      final others = res.ads.where((a) => a.id != ad.id).toList();
      setState(() {
        _sellerAdCount = res.total;
        if (ad.isDealer && others.isNotEmpty) _dealerStock = others;
      });
    } catch (_) {/* non-fatal */}
  }

  /// "Ads you may like": other live ads in the same subcategory. The stored
  /// `categories` is "top,sub", and the last one is the narrow one - matching on
  /// the top level would offer a horsebox to someone looking at a hatchback.
  /// The seller's own ads come out, since they already have a strip of their own.
  Future<void> _loadSimilar(Ad ad) async {
    final parts = (ad.raw['categories'] ?? '')
        .toString()
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return;
    final subCat = int.tryParse(parts.last);
    if (subCat == null) return;
    try {
      // Asked wide on purpose: a trader with a hundred ads in one subcategory
      // fills the first page on their own, and every one of those is dropped
      // below, which would leave the strip empty on their listings.
      final res = await widget.api.search(
        limit: 40,
        categoryId: subCat,
        isVehicle: ad.isVehicle,
      );
      if (!mounted) return;
      final others = res.ads
          .where((a) => a.id != ad.id && a.userId != ad.userId)
          .take(12)
          .toList();
      if (others.isNotEmpty) setState(() => _similar = others);
    } catch (_) {/* non-fatal */}
  }

  void _share(Ad ad) {
    final url = 'https://listit.im/ads/${ad.id}';
    final text = ad.title.isEmpty ? url : '${ad.title}\n$url';
    Share.share(text, subject: ad.title.isEmpty ? 'List it' : ad.title);
  }

  Future<void> _toggleSave(Ad ad) async {
    final auth = widget.auth;
    if (auth == null || !auth.isLoggedIn) {
      // Nudge to sign in, then (if we can) save straight away.
      if (auth == null) {
        _snack('Sign in to save ads.');
        return;
      }
      final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => AuthScreen(auth: auth, reason: 'Sign in to save this ad'),
      ));
      if (ok != true || !mounted) return;
      auth.refreshProfile();
    }
    final user = widget.auth?.user;
    if (user == null || _saving) return;
    final wasSaved = _saved;
    setState(() {
      _saved = !wasSaved;
      _saving = true;
    });
    try {
      if (wasSaved) {
        await widget.api.unsaveAd(userId: user.id, adId: ad.id);
      } else {
        await widget.api.saveAd(userId: user.id, adId: ad.id);
      }
      if (mounted) _snack(wasSaved ? 'Removed from saved' : 'Saved');
    } catch (_) {
      if (mounted) setState(() => _saved = wasSaved); // revert on failure
      _snack('Could not update saved ads.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(m), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (ad == null) {
      return Scaffold(
        appBar: AppBar(),
        body: _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.slate),
                  ),
                ),
              )
            : const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
      );
    }
    return Scaffold(
      body: CustomScrollView(
        controller: _scroll,
        slivers: [
          _galleryAppBar(ad),
          SliverToBoxAdapter(child: _content(ad)),
        ],
      ),
      bottomNavigationBar: _contactBar(ad),
    );
  }

  void _openPhotos(Ad ad, int index) {
    if (ad.images.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PhotoViewerScreen(images: ad.images, initialIndex: index),
    ));
  }

  Widget _galleryAppBar(Ad ad) {
    final photos = ad.images;
    final shut = _collapse > 0.55; // past here the photo has gone
    return SliverAppBar(
      expandedHeight: _kGalleryHeight,
      pinned: true,
      backgroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 2,
      // Over the photo the arrow needs its own scrim to stay visible; against
      // the white collapsed bar it does not.
      leading: shut
          ? null
          : Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _scrimIcon(
                  Icons.arrow_back, () => Navigator.of(context).maybePop()),
            ),
      title: _collapsedTitle(ad),
      titleSpacing: 4,
      actions: [
        if (shut) ...[
          IconButton(
            tooltip: 'Share',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.ios_share_rounded, color: AppColors.ink),
            onPressed: () => _share(ad),
          ),
          IconButton(
            tooltip: 'Save',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              _saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: _saved ? AppColors.danger : AppColors.ink,
            ),
            onPressed: () => _toggleSave(ad),
          ),
        ] else if (photos.isNotEmpty)
          // Top-right tile button: opens the full-screen viewer straight into
          // its grid of every photo, DoneDeal-style.
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _scrimIcon(
              Icons.grid_view_rounded,
              () => _openPhotos(ad, _photoIndex),
            ),
          ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (photos.isEmpty)
              const NetworkPhoto(url: null)
            else
              PageView.builder(
                controller: _gallery,
                itemCount: photos.length,
                onPageChanged: (i) => setState(() => _photoIndex = i),
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => _openPhotos(ad, i),
                  child: NetworkPhoto(url: photos[i]),
                ),
              ),
            // Photo count chip, bottom-left, like DoneDeal - taps into the viewer.
            if (photos.isNotEmpty)
              Positioned(
                left: 12,
                bottom: 12,
                child: GestureDetector(
                  onTap: () => _openPhotos(ad, _photoIndex),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.photo_camera_rounded,
                            size: 15, color: Colors.white),
                        const SizedBox(width: 5),
                        Text('${photos.length}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ),
            if (photos.length > 1)
              Positioned(
                bottom: 12,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    photos.length,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _photoIndex ? 20 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == _photoIndex
                            ? Colors.white
                            : Colors.white54,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// What the header carries once the photo has scrolled away: which ad this
  /// is, and what it costs. Faded in over the back half of the collapse so it
  /// does not appear while the photo is still on screen.
  Widget _collapsedTitle(Ad ad) {
    final t = ((_collapse - 0.55) / 0.45).clamp(0.0, 1.0);
    if (t == 0) return const SizedBox.shrink();
    return Opacity(
      opacity: t,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ad.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
          Text(
            Format.price(ad),
            maxLines: 1,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }

  /// A white icon on a subtle dark scrim so it stays legible over any photo.
  Widget _scrimIcon(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.black.withValues(alpha: 0.4),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  Future<void> _openReport(Ad ad) async {
    final auth = widget.auth;
    if (auth == null || !auth.isLoggedIn) {
      if (auth == null) {
        _snack('Sign in to report an ad.');
        return;
      }
      final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => AuthScreen(auth: auth, reason: 'Sign in to report this ad'),
      ));
      if (ok != true || !mounted) return;
      auth.refreshProfile();
    }
    final user = widget.auth?.user;
    if (user == null || !mounted) return;

    const reasons = [
      'Breach of terms',
      'Suspected fraud',
      'Suspected stolen goods',
      'Suspected counterfeit goods',
      "Can't contact seller",
      'Animal welfare concern',
      'Other',
    ];
    String? reason;
    final commentCtrl = TextEditingController();

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (sheetCtx) {
        var busy = false;
        return StatefulBuilder(builder: (sheetCtx, setSheet) {
          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Report ad',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  const Text('Tell us what\'s wrong and we\'ll take a look.',
                      style: TextStyle(color: AppColors.slate)),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final r in reasons)
                        ChoiceChip(
                          label: Text(r),
                          selected: reason == r,
                          showCheckmark: false,
                          labelStyle: TextStyle(
                            color: reason == r ? Colors.white : AppColors.ink,
                            fontWeight: FontWeight.w600,
                          ),
                          selectedColor: AppColors.primary,
                          backgroundColor: AppColors.surface,
                          side: BorderSide(
                              color: reason == r ? AppColors.primary : AppColors.line),
                          onSelected: (_) => setSheet(() => reason = r),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: commentCtrl,
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Add any details (optional)',
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.control),
                        borderSide: const BorderSide(color: AppColors.line),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.control),
                        borderSide: const BorderSide(color: AppColors.line),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: busy
                          ? null
                          : () async {
                              if (reason == null) {
                                ScaffoldMessenger.of(sheetCtx)
                                  ..hideCurrentSnackBar()
                                  ..showSnackBar(const SnackBar(
                                      content: Text('Please choose a reason.')));
                                return;
                              }
                              setSheet(() => busy = true);
                              final nav = Navigator.of(sheetCtx);
                              final messenger = ScaffoldMessenger.of(sheetCtx);
                              try {
                                final c = commentCtrl.text.trim();
                                await widget.api.reportAd(
                                  adId: ad.id,
                                  ownerId: ad.userId,
                                  userId: user.id,
                                  name: user.name,
                                  email: user.email,
                                  reason: reason!,
                                  comment: c.isEmpty ? reason! : c,
                                );
                                nav.pop(true);
                              } catch (_) {
                                setSheet(() => busy = false);
                                messenger
                                  ..hideCurrentSnackBar()
                                  ..showSnackBar(const SnackBar(
                                      content: Text('Could not send report. Try again.')));
                              }
                            },
                      child: busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Submit report'),
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
    commentCtrl.dispose();
    if (submitted == true) _snack('Thanks — we\'ll review this ad.');
  }

  Widget _content(Ad ad) {
    final old = Format.oldPrice(ad);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sellerHeader(ad),
          const Divider(height: 28),
          Text(
            ad.title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 8),
          _metaLine(ad),
          const SizedBox(height: 14),
          _priceRow(ad, old),
          if (ad.isVehicle) _financeRow(ad),
          _verifiedBox(ad),
          if (ad.isVehicle) _vehicleOverview(ad),
          const Divider(height: 34),
          const Text(
            'Description',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          _description(ad),
          const SizedBox(height: 18),
          _sellerPanel(ad),
          const SizedBox(height: 18),
          _disclaimerBlock(ad),
          const SizedBox(height: 22),
          _reportButton(ad),
          if (_dealerStock.isNotEmpty) _dealerStockSection(ad),
          if (_similar.isNotEmpty) _similarSection(),
        ],
      ),
    );
  }

  /// "More from {dealer}" - a horizontal strip of the trader's other live ads,
  /// mirroring DoneDeal's "Our stock". Tapping one opens it.
  Widget _dealerStockSection(Ad ad) {
    final heading = ad.displayName.isEmpty
        ? 'More from this seller'
        : 'More from ${ad.displayName}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 34),
        Text(heading,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.ink)),
        const SizedBox(height: 12),
        SizedBox(
          height: 196,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: _dealerStock.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) => _stockCard(_dealerStock[i]),
          ),
        ),
      ],
    );
  }

  /// "Ads you may like" - the same card strip as the seller's stock, so the two
  /// read as one pattern rather than two.
  Widget _similarSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 34),
        const Text('Ads you may like',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.ink)),
        const SizedBox(height: 12),
        SizedBox(
          height: 196,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: _similar.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) => _stockCard(_similar[i]),
          ),
        ),
      ],
    );
  }

  Widget _stockCard(Ad ad) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AdDetailScreen(
          adId: ad.id,
          api: widget.api,
          preview: ad,
          auth: widget.auth,
        ),
      )),
      child: SizedBox(
        width: 160,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.control),
              child: SizedBox(
                width: 160,
                height: 110,
                child: NetworkPhoto(url: ad.coverImage),
              ),
            ),
            const SizedBox(height: 6),
            Text(Format.price(ad),
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary)),
            const SizedBox(height: 2),
            Text(ad.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13, height: 1.25, color: AppColors.ink)),
          ],
        ),
      ),
    );
  }

  Widget _metaLine(Ad ad) {
    final parts = <String>[
      Format.timeAgo(ad.createdAt),
      '${ad.viewCount} ${ad.viewCount == 1 ? 'view' : 'views'}',
      ad.location.isEmpty ? 'Isle of Man' : ad.location,
    ];
    return Text(
      parts.join('  ·  '),
      style: const TextStyle(color: AppColors.slate, fontSize: 14),
    );
  }

  Widget _priceRow(Ad ad, String? old) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  Format.price(ad),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              if (old != null) ...[
                const SizedBox(width: 10),
                Text(
                  old,
                  style: const TextStyle(
                    fontSize: 17,
                    color: AppColors.muted,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              ],
            ],
          ),
        ),
        // Share + Heart sit together on the right of the price, DoneDeal-style.
        IconButton(
          tooltip: 'Share',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.ios_share_rounded, color: AppColors.ink),
          onPressed: () => _share(ad),
        ),
        IconButton(
          tooltip: 'Save',
          visualDensity: VisualDensity.compact,
          icon: Icon(
            _saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            color: _saved ? AppColors.danger : AppColors.ink,
          ),
          onPressed: () => _toggleSave(ad),
        ),
      ],
    );
  }

  /// The dealer's finance quote for this car, or null when the seller has not
  /// switched finance on. Worked out on the server by the same calculator the
  /// dealer's own website uses, so the two can never disagree.
  Map? _finance(Ad ad) {
    final f = ad.raw['finance'];
    return f is Map && f['monthly'] != null ? f : null;
  }

  /// "Finance from £303 per month". Nothing at all when there is no quote -
  /// this used to be a Finance button with a "Coming soon" tag on every single
  /// vehicle, which promised something on thousands of listings and delivered
  /// it on none.
  Widget _financeRow(Ad ad) {
    final q = _finance(ad);
    if (q == null) return const SizedBox.shrink();
    final monthly = (q['monthly'] as num).round();
    final apr = q['apr'];
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: InkWell(
        onTap: () => _showFinance(ad, q),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              const Icon(Icons.account_balance_rounded,
                  size: 19, color: AppColors.slate),
              const SizedBox(width: 9),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(
                        fontSize: 15, height: 1.35, color: AppColors.ink),
                    children: [
                      const TextSpan(text: 'Finance from '),
                      TextSpan(
                          text: '£$monthly',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const TextSpan(text: ' per month'),
                      TextSpan(
                          text: '   Representative $apr% APR',
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.slate)),
                    ],
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, size: 20, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }

  /// The representative example. Quoting a monthly payment is advertising
  /// credit, so the figures behind it have to be available, not just the
  /// headline. Same rows and same wording as the dealer's website.
  void _showFinance(Ad ad, Map q) {
    String money(dynamic v) => '£${_grouped((v as num).round())}';
    final rows = <List<String>>[
      ['Cash price', money(q['cash_price'])],
      ['Deposit', money(q['deposit'])],
      ['Amount of credit', money(q['advance'])],
      ['Term', '${q['term_months']} months'],
      ['Monthly payment', money(q['monthly'])],
      ['Total amount payable', money(q['total_payable'])],
      ['Representative APR', '${q['apr']}%'],
    ];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Finance from ${money(q['monthly'])} per month',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink)),
              const SizedBox(height: 12),
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(r[0],
                            style: const TextStyle(
                                fontSize: 14.5, color: AppColors.slate)),
                      ),
                      Text(r[1],
                          style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink)),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              Text(
                'Representative example based on ${q['term_months']} monthly '
                'payments with a ${money(q['deposit'])} deposit. Figures are an '
                'illustration only and are subject to status, affordability and '
                "the lender's own terms. ${ad.displayName.isEmpty ? 'The seller' : ad.displayName} "
                'may receive a commission from lenders. Written quotations on '
                'request.',
                style: const TextStyle(
                    fontSize: 12, height: 1.5, color: AppColors.slate),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// How long the seller has been on Listit, in plain words. Anything under a
  /// year is counted in months, because "0 years" says nothing.
  String _memberFor(dynamic created) {
    final since = DateTime.tryParse('${created ?? ''}');
    if (since == null) return '';
    final days = DateTime.now().difference(since).inDays;
    if (days < 45) return 'New';
    if (days < 365) {
      final m = (days / 30).round();
      return '$m month${m == 1 ? '' : 's'}';
    }
    final y = (days / 365).floor();
    return '$y year${y == 1 ? '' : 's'}';
  }

  /// A one word verdict on a rating, the way DoneDeal labels theirs.
  String _ratingWord(double avg) {
    if (avg >= 4.5) return 'Excellent';
    if (avg >= 4.0) return 'Very good';
    if (avg >= 3.0) return 'Good';
    return 'Mixed';
  }

  /// One line of the verification list: a green tick if we have checked it, a
  /// grey dash if we have not. The dash matters as much as the tick - it is
  /// what tells a buyer the seller has not confirmed that detail.
  Widget _checkLine(String label, bool ok) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(ok ? Icons.check : Icons.remove,
              size: 19, color: ok ? const Color(0xFF16A34A) : AppColors.slate),
          const SizedBox(width: 10),
          Text(label,
              style: TextStyle(
                  fontSize: 15,
                  color: ok ? AppColors.ink : AppColors.slate)),
        ],
      ),
    );
  }

  Widget _statCell(String top, String bottom, {Color? topColor, Widget? icon}) {
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(top,
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: topColor ?? AppColors.ink)),
              if (icon != null) ...[const SizedBox(width: 4), icon],
            ],
          ),
          const SizedBox(height: 2),
          Text(bottom,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.slate)),
        ],
      ),
    );
  }

  /// Rows of the "Visit showroom" block: a grey label, the value on the right,
  /// and a chevron when there is something to open.
  Widget _showroomRow(String label, String value,
      {bool? open, VoidCallback? onTap, Widget? trailing}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Text(label,
                style: const TextStyle(fontSize: 15, color: AppColors.slate)),
            const Spacer(),
            Flexible(
              child: trailing ??
                  Text(value,
                      textAlign: TextAlign.right,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink)),
            ),
            if (open != null)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(
                    open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 22,
                    color: AppColors.ink),
              ),
          ],
        ),
      ),
    );
  }

  /// The town out of a full postal address, for the collapsed location row.
  /// "Manx Car Warehouse, Portway, Ballasalla, Isle of Man" reads better as
  /// "Ballasalla" when the full thing is one tap away on the map.
  String _townOf(String address, String fallback) {
    final parts = address
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty && p.toLowerCase() != 'isle of man')
        .toList();
    if (parts.isEmpty) return fallback;
    // Some addresses end "Isle of Man IM4 2AZ, Isle of Man", so dropping the
    // exact island name is not enough - the postcode chunk still carries it.
    var last = parts.last;
    final lead = RegExp(r'^isle of man\s+', caseSensitive: false);
    if (lead.hasMatch(last)) last = last.replaceFirst(lead, '').trim();
    if (last.isEmpty) {
      return parts.length > 1 ? parts[parts.length - 2] : fallback;
    }
    return last;
  }

  /// Today's hours, and the whole week, from the dealer's opening_hours rows.
  /// Returns null when the trader has not filled any of it in.
  List<List<String>>? _week(dynamic hours) {
    if (hours is! List || hours.isEmpty) return null;
    const names = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday',
                   'Saturday', 'Sunday'];
    final byDay = <String, Map>{};
    for (final h in hours) {
      if (h is Map) byDay[(h['day_of_week'] ?? '').toString().toLowerCase()] = h;
    }
    final out = <List<String>>[];
    for (final n in names) {
      final h = byDay[n.toLowerCase()];
      if (h == null) {
        out.add([n, '']);
        continue;
      }
      if (_truthy(h['is_closed'])) {
        out.add([n, 'Closed']);
        continue;
      }
      final open = (h['open_time'] ?? '').toString();
      final close = (h['close_time'] ?? '').toString();
      out.add([
        n,
        open.length >= 5 && close.length >= 5
            ? '${open.substring(0, 5)} - ${close.substring(0, 5)}'
            : ''
      ]);
    }
    return out.any((r) => r[1].isNotEmpty) ? out : null;
  }

  /// DoneDeal's "Visit showroom": where the trader is, when they are open and
  /// their own site. Everything here is data we already hold; nothing is
  /// invented, and a row with nothing behind it is left out entirely.
  Widget _dealerLines(Map map) {
    final address = (map['business_address'] ?? '').toString().trim();
    final site = (map['website'] ?? '').toString().trim();
    final week = _week(map['opening_hours']);
    final lat = double.tryParse('${map['lat'] ?? ''}');
    final lng = double.tryParse('${map['lng'] ?? ''}');
    final hasMap = lat != null && lng != null;

    if (address.isEmpty && site.isEmpty && week == null) {
      return const SizedBox.shrink();
    }

    final todayIndex = DateTime.now().weekday - 1;
    final todayHours = week == null ? '' : week[todayIndex][1];
    final closedToday = todayHours.isEmpty || todayHours == 'Closed';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        const Center(
          child: Text('Visit showroom',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
                decoration: TextDecoration.underline,
              )),
        ),
        const SizedBox(height: 6),
        if (address.isNotEmpty)
          _showroomRow(
            'Location:',
            _townOf(address, ''),
            open: hasMap ? _showMap : null,
            onTap: hasMap ? () => setState(() => _showMap = !_showMap) : null,
          ),
        if (hasMap && _showMap) ...[
          const SizedBox(height: 2),
          Text(address,
              style: const TextStyle(fontSize: 13.5, color: AppColors.slate)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.image),
            child: SizedBox(
              height: 190,
              child: Stack(
                children: [
                  FlutterMap(
                    options: MapOptions(
                      initialCenter: LatLng(lat, lng),
                      initialZoom: 13,
                      minZoom: 8,
                      maxZoom: 17,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'im.listit.listit_app',
                        maxZoom: 19,
                      ),
                      MarkerLayer(markers: [
                        Marker(
                          point: LatLng(lat, lng),
                          width: 36,
                          height: 36,
                          child: const Icon(Icons.location_pin,
                              size: 36, color: Color(0xFFDC2626)),
                        ),
                      ]),
                    ],
                  ),
                  // OpenStreetMap's licence asks for this wherever tiles show.
                  const Positioned(
                    right: 5,
                    bottom: 3,
                    child: Text('© OpenStreetMap',
                        style: TextStyle(fontSize: 9, color: AppColors.slate)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (week != null)
          _showroomRow(
            closedToday ? 'Closed:' : 'Open today:',
            todayHours.isEmpty ? 'Closed' : todayHours,
            open: _showHours,
            onTap: () => setState(() => _showHours = !_showHours),
          ),
        if (week != null && _showHours)
          for (var i = 0; i < week.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Text(week[i][0],
                      style: TextStyle(
                          fontSize: 15,
                          color: i == todayIndex
                              ? const Color(0xFFDC2626)
                              : AppColors.ink)),
                  const Spacer(),
                  Text(week[i][1].isEmpty ? 'Closed' : week[i][1],
                      style: TextStyle(
                          fontSize: 15,
                          color: i == todayIndex
                              ? const Color(0xFFDC2626)
                              : AppColors.ink)),
                ],
              ),
            ),
        if (site.isNotEmpty)
          _showroomRow(
            'Website:',
            '',
            onTap: () => launchUrl(
              Uri.parse(site.startsWith('http') ? site : 'https://$site'),
              mode: LaunchMode.externalApplication,
            ),
            trailing: Text(
              // Shown the way a person would write it: no scheme, no www, no
              // trailing slash. The link itself still uses the stored value.
              site
                  .replaceFirst(RegExp(r'^https?://', caseSensitive: false), '')
                  .replaceFirst(RegExp(r'^www\.', caseSensitive: false), '')
                  .replaceFirst(RegExp(r'/$'), ''),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, color: AppColors.primary),
            ),
          ),
      ],
    );
  }

  /// The trader's Google reviews. These come down with the ad already and were
  /// never being shown. No overall score is claimed: Google's API hands back
  /// five reviews, not the full history, so an average taken from those would
  /// not be the rating on their Google listing and would read as a wrong
  /// number to anyone who checked.
  Widget _googleReviews(Map map, String name) {
    final raw = map['reviews'];
    if (raw is! List || raw.isEmpty) return const SizedBox.shrink();
    final all = raw.whereType<Map>().where((r) {
      final t = (r['text'] ?? '').toString().trim();
      return t.isNotEmpty;
    }).toList();
    if (all.isEmpty) return const SizedBox.shrink();
    final shown = _reviewsExpanded ? all : all.take(2).toList();
    final rating = double.tryParse('${map['average_rating'] ?? ''}') ?? 0;
    final total = int.tryParse('${map['total_reviews'] ?? ''}') ?? all.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 34),
        Text(name,
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.ink)),
        const SizedBox(height: 6),
        // Google's own rating and total, taken from the dealer record. The
        // reviews listed underneath are the five Google hands back, which is
        // why the count here is larger than the number of reviews shown.
        if (rating > 0)
          Row(
            children: [
              for (var i = 0; i < 5; i++)
                Icon(
                  rating >= i + 1
                      ? Icons.star_rounded
                      : (rating > i
                          ? Icons.star_half_rounded
                          : Icons.star_outline_rounded),
                  size: 19,
                  color: const Color(0xFFF59E0B),
                ),
              const SizedBox(width: 7),
              Text('${rating.toStringAsFixed(1)}/5',
                  style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink)),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                    '\u2022  $total Google review${total == 1 ? '' : 's'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, color: AppColors.slate)),
              ),
            ],
          ),
        const SizedBox(height: 14),
        for (final r in shown) _googleReview(r),
        if (all.length > 2)
          InkWell(
            onTap: () => setState(() => _reviewsExpanded = !_reviewsExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                // Not "see all N": the heading above already says how many
                // reviews the trader has on Google, and Google only hands us
                // five of them, so a second number here reads as a mismatch.
                _reviewsExpanded ? 'Show fewer reviews' : 'See more reviews',
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary),
              ),
            ),
          ),
      ],
    );
  }

  /// True when the dealer's rating came down from Google rather than from
  /// Listit's own review system, which decides who owns the number.
  static bool _hasGoogle(Map map) {
    final raw = map['reviews'];
    return (map['review_id'] ?? '').toString().trim().isNotEmpty &&
        raw is List &&
        raw.isNotEmpty;
  }

  Widget _googleReview(Map r) {
    final author = (r['author_name'] ?? '').toString().trim();
    final when = (r['relative_time_description'] ?? '').toString().trim();
    final text = (r['text'] ?? '').toString().trim();
    final rating = (double.tryParse('${r['rating'] ?? ''}') ?? 0).round();
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: const Color(0xFFE5E7EB),
                child: const Icon(Icons.person, size: 22, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(author.isEmpty ? 'Google user' : author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15.5, color: AppColors.ink)),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        for (var i = 0; i < 5; i++)
                          Icon(
                            i < rating
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            size: 16,
                            color: const Color(0xFFF59E0B),
                          ),
                        if (when.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text('•  $when',
                              style: const TextStyle(
                                  fontSize: 13, color: AppColors.slate)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(text,
              maxLines: _reviewsExpanded ? null : 3,
              overflow:
                  _reviewsExpanded ? TextOverflow.clip : TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 14.5, height: 1.45, color: AppColors.ink)),
        ],
      ),
    );
  }

  /// The seller block DoneDeal puts at the foot of a listing. Only what we hold:
  /// no "payment card verified" and no reply rate, because we do not record
  /// either and a made up figure is worse than a missing one.
  Widget _sellerPanel(Ad ad) {
    final u = ad.raw['userDetails'];
    final map = u is Map ? u : const {};
    final emailOk = _truthy(map['email_verified']);
    final phoneOk = _truthy(map['otp_verified']);
    final avg = double.tryParse('${map['average_rating'] ?? ''}') ?? 0;
    final reviews = int.tryParse('${map['total_reviews'] ?? ''}') ?? 0;
    final member = _memberFor(map['created_at']);
    final dealer = ad.isDealer;
    final type = dealer ? (ad.isProperty ? 'Agent' : 'Trader') : 'Private seller';
    final name = ad.displayName.isEmpty ? 'Private seller' : ad.displayName;
    final where = ad.location.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 34),
        Row(
          children: [
            const Text('SELLER',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: .4,
                    color: AppColors.ink)),
            if (emailOk && phoneOk) ...[
              const SizedBox(width: 6),
              const Icon(Icons.verified, size: 19, color: AppColors.primary),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: AppColors.primary.withValues(alpha: 0.12),
              child: Text(_initials(name),
                  style: const TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink)),
                  const SizedBox(height: 2),
                  Text(where.isEmpty ? type : '$type \u2022 $where',
                      maxLines: 2,
                      style: const TextStyle(
                          fontSize: 14, color: AppColors.slate)),
                ],
              ),
            ),
          ],
        ),
        if (dealer) _dealerLines(map),
        const SizedBox(height: 16),
        _checkLine('Email verified', emailOk),
        _checkLine('Phone verified', phoneOk),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              // A dealer's rating comes from Google, and it is shown under the
              // Google heading below. Repeating it here read as a second,
              // Listit-issued score for the same trader.
              if (reviews > 0 && !_hasGoogle(map)) ...[
                _statCell('${avg.toStringAsFixed(1)}/5', _ratingWord(avg),
                    topColor: AppColors.primary,
                    icon: const Icon(Icons.star_rounded,
                        size: 19, color: Color(0xFFF59E0B))),
                _statCell('$reviews', reviews == 1 ? 'Review' : 'Reviews',
                    topColor: AppColors.primary),
              ] else if (reviews == 0)
                _statCell('\u2014', 'No reviews yet'),
              if (member.isNotEmpty) _statCell(member, 'on Listit'),
            ],
          ),
        ),
        _googleReviews(map, name),
        // The results screen needs a signed-in-or-not auth service; this screen
        // holds a nullable one, so only offer the link when we have it.
        if (_sellerAdCount > 0 && widget.auth != null) ...[
          const SizedBox(height: 12),
          InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ResultsScreen(
                api: widget.api,
                auth: widget.auth!,
                baseFilters: {'user_id': ad.userId},
                titleOverride: name,
              ),
            )),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.edit_note_rounded,
                      size: 20, color: AppColors.slate),
                  const SizedBox(width: 8),
                  Text(
                      '$_sellerAdCount live ad${_sellerAdCount == 1 ? '' : 's'}',
                      style: const TextStyle(
                          fontSize: 15, color: AppColors.ink)),
                  const Spacer(),
                  const Text('View all ads',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary)),
                  const Icon(Icons.chevron_right,
                      size: 20, color: AppColors.primary),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Our take on DoneDeal's green "Greenlight" box: a trust panel shown once a
  /// seller's email and phone are confirmed. Honest about what we actually
  /// check, so buyers know the contact details are real.
  Widget _verifiedBox(Ad ad) {
    final u = ad.raw['userDetails'];
    final map = u is Map ? u : const {};
    final verified =
        _truthy(map['email_verified']) && _truthy(map['otp_verified']);
    if (!verified) return const SizedBox.shrink();
    const green = Color(0xFF16A34A);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1, right: 8),
            child: Icon(Icons.verified_user_rounded, size: 18, color: green),
          ),
          Expanded(
            child: RichText(
              text: const TextSpan(
                style: TextStyle(
                    fontSize: 13.5, height: 1.4, color: AppColors.slate),
                children: [
                  TextSpan(
                      text: 'Verified seller. ',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, color: AppColors.ink)),
                  TextSpan(
                      text: 'Email and phone confirmed with Listit.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Title case that does not wreck car names. Importers store them shouting -
  /// "CX-3 SKYACTIV-G SPORT NAV" - and plain title case turns that into
  /// "Cx-3 Skyactiv-g Sport Nav". Short chunks and anything with a digit in it
  /// are left as they are, so CX-3, TDI and S-Line survive.
  String _carCase(String t) {
    String piece(String w) {
      if (w.isEmpty) return w;
      // Anything with a number in it is left exactly as stored, so "50kWh"
      // stays "50kWh" rather than becoming "50KWH".
      if (RegExp(r'[0-9]').hasMatch(w)) return w;
      if (w.length <= 3) return w.toUpperCase();
      return '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}';
    }
    return t
        .split(' ')
        .map((w) => w.split('-').map(piece).join('-'))
        .join(' ');
  }

  /// Mileage, tidied. It arrives as "167000", "83.000" or "83,000" depending on
  /// who typed it, so take the digits and group them ourselves.
  String _mileage(Map v) {
    final raw = (v['milage'] ?? '').toString();
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';
    final n = int.tryParse(digits);
    final unit = (v['milage_unit'] ?? '').toString().trim();
    return '${n != null ? _grouped(n) : digits} ${unit.isEmpty ? 'mi' : unit}';
  }

  /// A stored attribute worth showing. Sellers and importers leave "-", "0" and
  /// "N/A" behind, and a row that says "-" is worse than no row.
  String _attr(Map v, String key, {bool titled = true}) {
    var t = (v[key] ?? '').toString().trim();
    if (t.isEmpty || t == '-' || t == '0' || t.toUpperCase() == 'N/A') return '';
    if (titled) t = _carCase(t);
    return t;
  }

  /// The full spec table, the way DoneDeal's "Vehicle overview" reads. Rows
  /// with nothing behind them are left out entirely.
  Widget _vehicleOverview(Ad ad) {
    final vd = ad.raw['vehicleData'];
    final v = vd is Map ? vd : const {};
    final rows = <List<String>>[];
    void add(String label, String value) {
      if (value.trim().isNotEmpty) rows.add([label, value]);
    }

    add('Make', _attr(v, 'make'));
    add('Model', _attr(v, 'model'));
    add('Variant', _attr(v, 'variant'));
    add('Year', _attr(v, 'year', titled: false));
    add('Mileage', _mileage(v));
    add('Fuel type', _attr(v, 'fuel_type'));
    add('Transmission', _attr(v, 'transmission'));
    add('Body type', _attr(v, 'body_type'));

    final eng = _attr(v, 'engine_size', titled: false);
    if (eng.isNotEmpty) {
      final cc = int.tryParse(eng);
      add('Engine',
          cc != null && cc >= 100 ? '${(cc / 1000).toStringAsFixed(1)}L' : '$eng cc');
    }
    add('Colour', _attr(v, 'colour'));
    add('Seats', _attr(v, 'number_of_seats', titled: false));
    add('Doors', _attr(v, 'number_of_doors', titled: false));
    add('Drive type', _attr(v, 'drive_type'));
    add('Registration', _attr(v, 'registration_number', titled: false));

    // Dates arrive with a time on the end that nobody needs to read.
    final nct = _attr(v, 'nct_expiry', titled: false);
    if (nct.isNotEmpty) add('NCT expiry', nct.split(' ').first);

    final fee = _attr(v, 'tax_fee', titled: false);
    final dur = _attr(v, 'tax_duration');
    if (fee.isNotEmpty) {
      final amount = double.tryParse(fee);
      final money = amount == null
          ? fee
          : '\u00a3${amount.round()}';
      add('Road tax', dur.isEmpty ? money : '$money / $dur');
    }
    add('CO2', _attr(v, 'co2', titled: false).isEmpty
        ? ''
        : '${_attr(v, 'co2', titled: false)} g/km');

    if (rows.length < 3) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 34),
        Row(
          children: [
            const Text('Vehicle details',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink)),
            if (_truthy((ad.raw['vehicleData'] is Map
                    ? ad.raw['vehicleData'] as Map
                    : const {})['is_vefied'])) ...[
              const Spacer(),
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified_rounded,
                      size: 16, color: Color(0xFF16A34A)),
                  SizedBox(width: 5),
                  Text('Greenlight verified',
                      style: TextStyle(
                          color: Color(0xFF16A34A),
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        for (final r in rows)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.line)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 4,
                  child: Text(r[0],
                      style: const TextStyle(
                          fontSize: 15, color: AppColors.slate)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 5,
                  child: Text(r[1],
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _description(Ad ad) {
    final desc = ad.description.trim().isEmpty
        ? 'No description provided.'
        : ad.description.trim();
    final isLong = desc.length > 180 || '\n'.allMatches(desc).length > 5;
    final collapsed = isLong && !_descExpanded;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          desc,
          maxLines: collapsed ? 6 : null,
          overflow: collapsed ? TextOverflow.ellipsis : TextOverflow.clip,
          style: const TextStyle(fontSize: 15, height: 1.5, color: AppColors.ink),
        ),
        if (isLong)
          InkWell(
            onTap: () => setState(() => _descExpanded = !_descExpanded),
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _descExpanded ? 'Read less' : 'Read more',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// The listing notice. Wording is the client's, supplied in full, and is not
  /// paraphrased or trimmed anywhere - it is a liability notice, so it says
  /// what he wrote or it says nothing.
  ///
  /// Two versions: vehicles get the one about condition and warranty, and
  /// everything else gets the one about ownership, inspection and documents.
  ///
  /// Wrapped in SelectionContainer.disabled so the text cannot be selected,
  /// copied or shared out of the app.
  Widget _disclaimerBlock(Ad ad) {
    const vehicleParas = [
      'Some information displayed on Listit may be provided by third parties '
          'or identified using AI, and may not be fully accurate, complete, or '
          'up to date.',
      'Images may have been digitally edited, enhanced, or generated. Listit '
          'does not verify this content. Buyers and sellers should '
          'independently confirm all details and the condition of the vehicle '
          'before committing to a purchase.',
      'Listit expressly disclaims any liability for losses, damage, or '
          'disputes arising from the content of any advertisement, including '
          'reliance upon images that have been modified, enhanced, or created '
          'using AI or similar technologies.',
      'Listit recommends checking the vehicle description and confirming all '
          'warranty details directly with the seller.',
    ];
    const generalParas = [
      'Some information displayed on Listit may be provided by third parties '
          'or identified or processed using AI, and may not be fully accurate, '
          'complete, or up to date.',
      'Images may have been digitally edited, enhanced, or generated. Listit '
          'does not verify the accuracy or authenticity of images or '
          'information provided in advertisements.',
      'Buyers should independently check all details, specifications, '
          'condition and ownership of an item before committing to a purchase. '
          'Where appropriate, buyers should arrange their own inspection and '
          'verify any relevant documentation.',
      'Listit is a platform that connects buyers and sellers and is not '
          'responsible for the accuracy, completeness or authenticity of '
          'information supplied by advertisers.',
      'Listit accepts no liability for losses, damage, or disputes arising '
          'from reliance on information, images or other content contained '
          'within an advertisement, including content that has been modified, '
          'enhanced or created using AI or similar technologies.',
    ];
    final paras = ad.isVehicle ? vehicleParas : generalParas;

    const body = TextStyle(
        fontSize: 12.5, height: 1.45, color: AppColors.slate);

    return SelectionContainer.disabled(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1, right: 9),
                  child: Icon(Icons.error_outline_rounded,
                      size: 19, color: Color(0xFFD97706)),
                ),
                Expanded(child: Text(paras.first, style: body)),
              ],
            ),
            if (_disclaimerExpanded)
              for (final p in paras.skip(1))
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(p, style: body),
                ),
            if (_disclaimerExpanded) ...[
              const SizedBox(height: 12),
              const Text('Listit — Simple. Safe. Secure.',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink)),
            ],
            const SizedBox(height: 6),
            InkWell(
              onTap: () =>
                  setState(() => _disclaimerExpanded = !_disclaimerExpanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  _disclaimerExpanded ? 'Read less' : 'Read more',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reportButton(Ad ad) {
    return InkWell(
      onTap: () => _openReport(ad),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.outlined_flag_rounded, size: 18, color: AppColors.slate),
            SizedBox(width: 6),
            Text('Report ad',
                style: TextStyle(
                  color: AppColors.slate,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                )),
          ],
        ),
      ),
    );
  }

  static bool _truthy(dynamic v) =>
      v == true || v == 1 || v == '1' || v == 'true';

  /// Compact seller header at the top of the listing, DoneDeal-style: name,
  /// seller type (Verified Agent / Trader / Private seller) and a star rating.
  Widget _sellerHeader(Ad ad) {
    final u = ad.raw['userDetails'];
    final map = u is Map ? u : const {};
    final avg = double.tryParse('${map['average_rating'] ?? ''}') ?? 0;
    final reviews = int.tryParse('${map['total_reviews'] ?? ''}') ?? 0;
    final verified = _truthy(map['email_verified']) && _truthy(map['otp_verified']);
    final dealer = ad.isDealer;
    final type = dealer ? (ad.isProperty ? 'Agent' : 'Trader') : 'Private seller';
    final label = (verified && dealer) ? 'Verified $type' : type;
    final name = ad.displayName.isEmpty ? 'Private seller' : ad.displayName;
    final logo = dealer ? ad.dealerLogo : '';
    return Row(
      children: [
        if (logo.isNotEmpty)
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(color: AppColors.line),
            ),
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.center,
            child: Image.network(
              logo,
              width: 44,
              height: 44,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => Text(
                _initials(name),
                style: const TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.w700),
              ),
            ),
          )
        else
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.primary.withValues(alpha: 0.12),
            child: Text(
              _initials(name),
              style: const TextStyle(
                  color: AppColors.primary, fontWeight: FontWeight.w700),
            ),
          ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink),
                    ),
                  ),
                  if (verified) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.verified, color: AppColors.primary, size: 18),
                  ],
                ],
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.slate,
                          fontWeight: FontWeight.w600)),
                  if (avg > 0) ...[
                    const Text('   ',
                        style: TextStyle(color: AppColors.muted)),
                    _stars(avg),
                    const SizedBox(width: 4),
                    Text('${avg.toStringAsFixed(1)} ($reviews)',
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.slate)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stars(double avg) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final full = i < avg.floor();
        final half = !full && (avg - i) >= 0.5;
        return Icon(
          full
              ? Icons.star_rounded
              : half
                  ? Icons.star_half_rounded
                  : Icons.star_border_rounded,
          color: AppColors.save,
          size: 16,
        );
      }),
    );
  }

  /// The sticky contact bar. What it shows follows the seller's own contact
  /// choice (the website's `allow_contact`): call-only sellers get one big Call
  /// button; sellers who allow messaging get Make offer + Send message. When
  /// both are on, a compact Call sits alongside them.
  Widget _contactBar(Ad ad) {
    final myId = widget.auth?.user?.id;
    final isOwnAd = myId != null && myId == ad.userId;

    Widget bar;
    if (isOwnAd) {
      bar = _barButton(
        label: 'This is your listing',
        icon: Icons.person_rounded,
        filled: false,
        onTap: null,
      );
    } else {
      final calls = ad.allowsCalling;
      final messages = ad.allowsMessaging;

      if (messages) {
        // One "Enquire" button that opens the message / offer (and call)
        // choices in a sheet, DoneDeal-style. A compact Call sits alongside
        // when the seller also takes calls.
        final enquire = Expanded(
          child: _barButton(
            label: 'Enquire',
            icon: Icons.forum_rounded,
            filled: true,
            onTap: () => _showEnquireSheet(ad),
          ),
        );
        // When the seller takes calls too, Call and Enquire share the bar
        // equally (50:50), Call outlined on the left, Enquire filled on the
        // right.
        bar = calls
            ? Row(children: [
                Expanded(
                  child: _barButton(
                    label: 'Call',
                    icon: Icons.call_rounded,
                    filled: false,
                    busy: _calling,
                    onTap: () => _callSeller(ad),
                  ),
                ),
                const SizedBox(width: 10),
                enquire,
              ])
            : Row(children: [enquire]);
      } else {
        // Call-only seller (or nothing but calling left): one big Call button.
        bar = _barButton(
          label: 'Call',
          icon: Icons.call_rounded,
          filled: true,
          busy: _calling,
          onTap: () => _callSeller(ad),
        );
      }
    }

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: bar,
      ),
    );
  }

  /// One button in the contact bar - filled (primary action) or outlined.
  Widget _barButton({
    required String label,
    required IconData icon,
    required bool filled,
    required VoidCallback? onTap,
    bool busy = false,
    bool showIcon = true,
  }) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card));
    final Widget child = busy
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2))
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (showIcon) ...[
                Icon(icon, size: 20),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15.5, fontWeight: FontWeight.w700)),
              ),
            ],
          );
    const tight = EdgeInsets.symmetric(horizontal: 8);
    return SizedBox(
      height: 54,
      width: double.infinity,
      child: filled
          ? ElevatedButton(
              onPressed: busy ? null : onTap,
              style: ElevatedButton.styleFrom(shape: shape, padding: tight),
              child: child,
            )
          : OutlinedButton(
              onPressed: busy ? null : onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                shape: shape,
                padding: tight,
              ),
              child: child,
            ),
    );
  }

  /// The "Enquire" sheet: message / offer (and call) options for this seller.
  void _showEnquireSheet(Ad ad) {
    final offers = ad.allowsMessaging && ad.allowsOffers;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.line,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Enquire about this ad',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            _enquireTile(
              sheetCtx,
              icon: Icons.chat_bubble_rounded,
              label: 'Send a message',
              subtitle: 'Ask the seller a question',
              onTap: () => _startMessage(ad),
            ),
            if (offers)
              _enquireTile(
                sheetCtx,
                icon: Icons.local_offer_rounded,
                label: 'Make an offer',
                subtitle: 'Propose a price to the seller',
                onTap: () => _startOffer(ad),
              ),
            if (ad.allowsCalling)
              _enquireTile(
                sheetCtx,
                icon: Icons.call_rounded,
                label: 'Call the seller',
                subtitle: 'Reveal and dial their number',
                onTap: () => _callSeller(ad),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _enquireTile(
    BuildContext sheetCtx, {
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.primary.withValues(alpha: 0.12),
        child: Icon(icon, color: AppColors.primary),
      ),
      title: Text(label,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
      subtitle: Text(subtitle,
          style: const TextStyle(color: AppColors.slate, fontSize: 12.5)),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
      onTap: () {
        Navigator.of(sheetCtx).pop();
        onTap();
      },
    );
  }

  /// Reveal the seller's number (same source the website's "Show number" uses)
  /// and dial it.
  Future<void> _callSeller(Ad ad) async {
    if (_calling) return;
    setState(() => _calling = true);
    Map<String, String>? d;
    try {
      d = await widget.api.revealDealerPhone(ad.userId);
    } catch (_) {/* handled below */}
    if (!mounted) return;
    setState(() => _calling = false);
    if (d == null) {
      _snack('No contact number on file for this seller.');
      return;
    }
    try {
      await launchUrl(
        Uri.parse('tel:${toIntlPhone(d['number'], d['flag'])}'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      _snack('Could not start the call.');
    }
  }

  /// Make sure there's a signed-in session before a gated action (message /
  /// offer). Returns true once we have one, prompting sign-in if needed.
  Future<bool> _requireAuth(String reason) async {
    final auth = widget.auth;
    if (auth == null) {
      _snack('Sign in to continue.');
      return false;
    }
    if (auth.isLoggedIn) return true;
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => AuthScreen(auth: auth, reason: reason),
    ));
    if (ok == true) {
      auth.refreshProfile();
      return auth.isLoggedIn;
    }
    return false;
  }

  /// Open (or start) the chat thread with the seller.
  Future<void> _startMessage(Ad ad) async {
    if (!await _requireAuth('Sign in to message the seller')) return;
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatScreen(
        api: widget.api,
        auth: widget.auth!,
        ad: ad,
        sellerId: ad.userId,
        otherName: ad.displayName,
      ),
    ));
  }

  /// Make an offer, then drop the buyer into the resulting chat thread.
  Future<void> _startOffer(Ad ad) async {
    if (!await _requireAuth('Sign in to make an offer')) return;
    if (!mounted) return;
    final amount = await showMakeOfferSheet(context, ad);
    if (amount == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      final convId = await widget.api.makeOffer(adId: ad.id, amount: amount);
      if (!mounted) return;
      nav.push(MaterialPageRoute(
        builder: (_) => ChatScreen(
          api: widget.api,
          auth: widget.auth!,
          conversationId: convId > 0 ? convId : null,
          ad: ad,
          sellerId: ad.userId,
          otherName: ad.displayName,
        ),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e.toString()),
        backgroundColor: AppColors.danger,
      ));
    }
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

/// Thousands-separated integer, e.g. 111980 -> "111,980" (used by the vehicle
/// spec grid for mileage).
String _grouped(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}
