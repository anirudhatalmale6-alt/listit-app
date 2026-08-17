import 'package:flutter/material.dart';

import '../models/featured_dealer.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import 'network_photo.dart';
import '../screens/results_screen.dart';

/// A DoneDeal-style "Featured Dealer" banner: ONE featured business at a time,
/// shown as a big photo card with the dealer's logo, name and stock count.
/// The dealer rotates each hour so every paid business gets a turn in the
/// spotlight. Tapping it opens that business's full stock. Renders nothing
/// while loading or if the section has no featured businesses, so it never
/// leaves an empty header.
class FeaturedDealersStrip extends StatefulWidget {
  final ApiService api;
  final AuthService auth;

  /// `motors` or `property`.
  final String sector;

  /// Heading shown above the banner (e.g. "Featured Dealer" / "Featured Estate
  /// Agent").
  final String title;

  /// Horizontal inset for the heading and banner. Defaults to 16 (home); pass a
  /// smaller value when it already sits inside a padded list.
  final double edgeInset;

  const FeaturedDealersStrip({
    super.key,
    required this.api,
    required this.auth,
    required this.sector,
    required this.title,
    this.edgeInset = 16,
  });

  @override
  State<FeaturedDealersStrip> createState() => _FeaturedDealersStripState();
}

class _FeaturedDealersStripState extends State<FeaturedDealersStrip> {
  List<FeaturedDealer> _dealers = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(FeaturedDealersStrip old) {
    super.didUpdateWidget(old);
    if (old.sector != widget.sector) {
      setState(() => _loading = true);
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final d = await widget.api.fetchFeaturedDealers(sector: widget.sector);
      if (mounted) {
        setState(() {
          _dealers = d;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _dealers = const [];
          _loading = false;
        });
      }
    }
  }

  void _openStock(FeaturedDealer d) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ResultsScreen(
        api: widget.api,
        auth: widget.auth,
        baseFilters: {'user_id': d.id},
        titleOverride: d.name.isEmpty ? 'Dealer stock' : d.name,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _dealers.isEmpty) return const SizedBox.shrink();
    // One featured business at a time, rotating hourly so each paid dealer
    // gets a turn - mirrors the website's rotation.
    final d = _dealers[DateTime.now().hour % _dealers.length];
    return Padding(
      padding: EdgeInsets.fromLTRB(widget.edgeInset, 14, widget.edgeInset, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 8),
            child: Row(
              children: [
                const Icon(Icons.workspace_premium_rounded,
                    size: 18, color: AppColors.save),
                const SizedBox(width: 6),
                Text(widget.title,
                    style: const TextStyle(
                        fontSize: AppText.section,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink)),
              ],
            ),
          ),
          _BannerCard(dealer: d, onTap: () => _openStock(d)),
        ],
      ),
    );
  }
}

class _BannerCard extends StatelessWidget {
  final FeaturedDealer dealer;
  final VoidCallback onTap;
  const _BannerCard({required this.dealer, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.card),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            AspectRatio(
              aspectRatio: 16 / 7,
              child: dealer.bannerImage.isEmpty
                  ? Container(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      alignment: Alignment.center,
                      child: const Icon(Icons.storefront_rounded,
                          size: 42, color: AppColors.primary),
                    )
                  : NetworkPhoto(url: dealer.bannerImage, fit: BoxFit.cover),
            ),
            // Dark gradient so the logo + name stay readable over the photo.
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x00000000),
                      Color(0x00000000),
                      Color(0xD9000000)
                    ],
                    stops: [0.0, 0.45, 1.0],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Row(
                children: [
                  _logoBox(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          dealer.name.isEmpty ? 'Featured dealer' : dealer.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: AppText.listing + 1,
                              fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              '${dealer.stock} ${dealer.stock == 1 ? 'ad' : 'ads'}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600),
                            ),
                            if (dealer.rating > 0) ...[
                              const SizedBox(width: 10),
                              const Icon(Icons.star_rounded,
                                  size: 15, color: AppColors.save),
                              const SizedBox(width: 2),
                              Text(
                                dealer.rating.toStringAsFixed(1),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios,
                      size: 15, color: Colors.white),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _logoBox() {
    Widget box(Widget child) => Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.image),
          ),
          clipBehavior: Clip.antiAlias,
          alignment: Alignment.center,
          child: child,
        );
    if (dealer.logo.isEmpty) {
      return box(const Icon(Icons.storefront_rounded,
          size: 26, color: AppColors.primary));
    }
    return box(Padding(
      padding: const EdgeInsets.all(4),
      child: Image.network(
        dealer.logo,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const Icon(Icons.storefront_rounded,
            size: 26, color: AppColors.primary),
      ),
    ));
  }
}
