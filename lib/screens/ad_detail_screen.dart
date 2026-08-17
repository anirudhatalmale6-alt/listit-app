import 'package:flutter/material.dart';
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

class _AdDetailScreenState extends State<AdDetailScreen> {
  final PageController _gallery = PageController();
  int _photoIndex = 0;

  Ad? _ad;
  String? _error;
  bool _saved = false;
  bool _saving = false;
  bool _descExpanded = false;
  bool _disclaimerExpanded = false;
  bool _calling = false; // revealing/dialling the seller's number
  List<Ad> _dealerStock = const [];

  @override
  void initState() {
    super.initState();
    _ad = widget.preview;
    _saved = widget.preview?.isSaved ?? false;
    if (widget.preview != null) RecentlyViewed.add(widget.preview!);
    _load();
  }

  @override
  void dispose() {
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
      if (full.isDealer && full.userId > 0) _loadDealerStock(full);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = widget.preview == null ? e.toString() : null;
      });
    }
  }

  /// A dealer's other live listings - the "Our stock" strip DoneDeal shows on
  /// trader ads. Best-effort: silent if it fails or the dealer has none.
  Future<void> _loadDealerStock(Ad ad) async {
    try {
      final res = await widget.api.search(
        limit: 12,
        filters: {'user_id': ad.userId},
      );
      if (!mounted) return;
      final others = res.ads.where((a) => a.id != ad.id).toList();
      if (others.isNotEmpty) setState(() => _dealerStock = others);
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
    return SliverAppBar(
      expandedHeight: 320,
      pinned: true,
      backgroundColor: Colors.white,
      actions: [
        if (photos.isNotEmpty)
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
          if (ad.isVehicle) _vehicleSpecs(ad),
          const Divider(height: 34),
          const Text(
            'Description',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          _description(ad),
          const SizedBox(height: 18),
          _disclaimerBlock(),
          const SizedBox(height: 22),
          _reportButton(ad),
          if (_dealerStock.isNotEmpty) _dealerStockSection(ad),
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
                fontWeight: FontWeight.w700,
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

  /// Vehicle finance teaser - a button with a "Coming soon" tag beside it, the
  /// way DoneDeal surfaces "Get finance approval". Tapping just flags it's on
  /// the way for now.
  Widget _financeRow(Ad ad) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        children: [
          OutlinedButton.icon(
            onPressed: () =>
                _snack('Vehicle finance is coming soon to Listit.'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
            ),
            icon: const Icon(Icons.account_balance_rounded, size: 18),
            label: const Text('Finance',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.save.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppRadius.image),
            ),
            child: const Text('Coming soon',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFB45309))),
          ),
        ],
      ),
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
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: green.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(color: green, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: const Icon(Icons.verified_user_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Listit Verified seller',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: green)),
                SizedBox(height: 3),
                Text(
                    'This seller\'s email and phone number have been confirmed with Listit.',
                    style: TextStyle(
                        fontSize: 13, height: 1.35, color: AppColors.slate)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The vehicle spec grid DoneDeal shows on car ads - year, mileage, fuel,
  /// transmission, engine, body - read from the ad's `vehicleData`.
  Widget _vehicleSpecs(Ad ad) {
    final vd = ad.raw['vehicleData'];
    final v = vd is Map ? vd : const {};
    String s(dynamic x) => (x ?? '').toString().trim();
    String titleCase(String t) => t.isEmpty
        ? t
        : t
            .toLowerCase()
            .split(' ')
            .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
            .join(' ');

    final specs = <List<dynamic>>[]; // [icon, label, value]
    void add(IconData icon, String label, String value) {
      if (value.trim().isNotEmpty) specs.add([icon, label, value]);
    }

    add(Icons.event_rounded, 'Year', s(v['year']));
    final mil = s(v['milage']);
    if (mil.isNotEmpty) {
      final n = int.tryParse(mil);
      final unit = s(v['milage_unit']).isEmpty ? 'mi' : s(v['milage_unit']);
      add(Icons.speed_rounded, 'Mileage',
          '${n != null ? _grouped(n) : mil} $unit');
    }
    add(Icons.local_gas_station_rounded, 'Fuel', titleCase(s(v['fuel_type'])));
    add(Icons.settings_rounded, 'Transmission', titleCase(s(v['transmission'])));
    final eng = s(v['engine_size']);
    if (eng.isNotEmpty) {
      final cc = int.tryParse(eng);
      add(Icons.tune_rounded, 'Engine',
          cc != null && cc >= 100 ? '${(cc / 1000).toStringAsFixed(1)}L' : '$eng cc');
    }
    add(Icons.directions_car_rounded, 'Body', titleCase(s(v['body_type'])));

    if (specs.isEmpty) return const SizedBox.shrink();

    final greenlight = _truthy(v['is_vefied']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 34),
        Row(
          children: [
            const Text('Vehicle details',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink)),
            if (greenlight) ...[
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF16A34A),
                  borderRadius: BorderRadius.circular(AppRadius.image),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_rounded, size: 15, color: Colors.white),
                    SizedBox(width: 4),
                    Text('Greenlight verified',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, c) {
            final w = (c.maxWidth - 12) / 2;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final sp in specs)
                  SizedBox(
                    width: w,
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(AppRadius.control),
                          ),
                          child: sp[1] == 'Engine'
                              // Material Icons has no engine glyph, so use our
                              // own engine mark, tinted to match the others.
                              ? Padding(
                                  padding: const EdgeInsets.all(9),
                                  child: Image.asset(
                                    'assets/engine.png',
                                    color: AppColors.primary,
                                    colorBlendMode: BlendMode.srcIn,
                                  ),
                                )
                              : Icon(sp[0] as IconData,
                                  size: 20, color: AppColors.primary),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(sp[1] as String,
                                  style: const TextStyle(
                                      fontSize: 12, color: AppColors.slate)),
                              Text(sp[2] as String,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.ink)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
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

  /// The DoneDeal-style collapsible disclaimer + "Stay Safe" block. Collapsed
  /// to a one-liner with "Read more"; expands to the full notice and safety
  /// tips. Wording supplied by the client.
  Widget _disclaimerBlock() {
    const disclaimer =
        'Images and listing details may have been edited, enhanced, '
        'ai-generated, or supplied by third parties. Listit does not verify '
        'every listing. Please inspect items, confirm all details, and satisfy '
        'yourself as to the condition and authenticity before buying or '
        'selling. Listit is not liable for any loss or disputes arising from '
        'the use of listing content.';
    const tips = [
      'Verify the seller or buyer.',
      'Inspect items before payment.',
      'Never send money without being satisfied.',
      'Report suspicious listings immediately.',
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            disclaimer,
            maxLines: _disclaimerExpanded ? null : 2,
            overflow: _disclaimerExpanded
                ? TextOverflow.clip
                : TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 12.5, height: 1.45, color: AppColors.slate),
          ),
          if (_disclaimerExpanded) ...[
            const SizedBox(height: 14),
            Row(
              children: const [
                Text('🛡️', style: TextStyle(fontSize: 15)),
                SizedBox(width: 6),
                Text('Stay Safe on Listit.im',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink)),
              ],
            ),
            const SizedBox(height: 8),
            for (final t in tips)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.check_circle_rounded,
                          size: 15, color: AppColors.primary),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(t,
                          style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.4,
                              color: AppColors.slate)),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 6),
          InkWell(
            onTap: () =>
                setState(() => _disclaimerExpanded = !_disclaimerExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                _disclaimerExpanded ? 'See less' : 'Read more',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ],
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
