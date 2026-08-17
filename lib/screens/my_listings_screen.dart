import 'package:flutter/material.dart';

import '../models/ad.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/network_photo.dart';
import 'ad_detail_screen.dart';
import 'auth/auth_screen.dart';
import 'sell/sell_flow_screen.dart';

/// "My listings" - the signed-in user's own ads across every status, newest
/// first, each with a live/sold/pending chip. Tapping one opens it.
class MyListingsScreen extends StatefulWidget {
  final ApiService api;
  final AuthService auth;
  const MyListingsScreen({super.key, required this.api, required this.auth});

  @override
  State<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends State<MyListingsScreen> {
  List<Ad> _ads = const [];
  bool _loading = true;
  String? _error;

  int get _me => widget.auth.user?.id ?? 0;

  @override
  void initState() {
    super.initState();
    if (widget.auth.isLoggedIn) {
      _load();
    } else {
      _loading = false;
    }
  }

  Future<void> _load() async {
    if (!widget.auth.isLoggedIn) return;
    setState(() => _loading = true);
    try {
      final res = await widget.api.listMyAds(userId: _me, limit: 50);
      if (!mounted) return;
      setState(() {
        _ads = res.ads;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _createListing() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SellFlowScreen(api: widget.api, auth: widget.auth),
    ));
    if (widget.auth.isLoggedIn) _load(); // a new ad may have been posted
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('My listings',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: _body(),
      bottomNavigationBar: widget.auth.isLoggedIn
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: _createListing,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.card)),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 24),
                    label: const Text('Create a listing',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _body() {
    if (!widget.auth.isLoggedIn) {
      return _empty(
        icon: Icons.lock_outline_rounded,
        title: 'Sign in to see your listings',
        message: 'Your posted ads live here once you\'re signed in.',
        action: FilledButton(
          onPressed: () async {
            await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => AuthScreen(auth: widget.auth),
            ));
            if (widget.auth.isLoggedIn) _load();
          },
          child: const Text('Sign in'),
        ),
      );
    }
    if (_loading && _ads.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _ads.isEmpty) {
      return _empty(
        icon: Icons.wifi_off_rounded,
        title: 'Couldn\'t load your listings',
        message: _error!,
        action: FilledButton(onPressed: _load, child: const Text('Retry')),
      );
    }
    if (_ads.isEmpty) {
      return _empty(
        icon: Icons.local_offer_outlined,
        title: 'No listings yet',
        message:
            'Ads you post show up here, where you can keep an eye on views and status. Tap the "+" to create your first one.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        itemCount: _ads.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _tile(_ads[i]),
      ),
    );
  }

  Widget _tile(Ad ad) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.card),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AdDetailScreen(
            adId: ad.id,
            api: widget.api,
            preview: ad,
            auth: widget.auth,
          ),
        )),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.line),
          ),
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.control),
                child: SizedBox(
                  width: 84,
                  height: 84,
                  child: NetworkPhoto(url: ad.coverImage),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _statusChip(ad),
                        const Spacer(),
                        const Icon(Icons.remove_red_eye_outlined,
                            size: 15, color: AppColors.muted),
                        const SizedBox(width: 3),
                        Text('${ad.viewCount}',
                            style: const TextStyle(
                                fontSize: 12.5, color: AppColors.slate)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(ad.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                            height: 1.2)),
                    const SizedBox(height: 4),
                    Text(Format.price(ad),
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusChip(Ad ad) {
    Color c;
    switch (ad.status) {
      case 1:
        c = AppColors.success;
        break;
      case 2:
      case 5:
        c = AppColors.primary;
        break;
      case 3:
      case 4:
        c = AppColors.danger;
        break;
      default:
        c = AppColors.save;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(ad.statusLabel,
          style: TextStyle(
              color: c, fontSize: 11.5, fontWeight: FontWeight.w700)),
    );
  }

  Widget _empty({
    required IconData icon,
    required String title,
    required String message,
    Widget? action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.primary, size: 34),
            ),
            const SizedBox(height: 18),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.slate, height: 1.35)),
            if (action != null) ...[
              const SizedBox(height: 20),
              action,
            ],
          ],
        ),
      ),
    );
  }
}
