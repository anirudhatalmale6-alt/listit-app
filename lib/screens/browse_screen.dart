import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../models/category.dart';
import '../models/weather.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/weather_service.dart';
import '../theme.dart';
import '../widgets/network_photo.dart';
import 'auth/auth_screen.dart';
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

/// The Browse tab, modelled on DoneDeal's marketplace home: brand header, a
/// search bar, a prominent Discover call-to-action, then every marketplace
/// section as a thumbnail list with live listing counts. Tapping a section
/// drops you into its swipe deck.
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
  late Future<List<Category>> _future;
  final TextEditingController _search = TextEditingController();

  final WeatherService _weatherService = WeatherService();
  Weather? _weather;

  @override
  void initState() {
    super.initState();
    _future = widget.api.fetchTopCategories();
    _loadWeather();
  }

  @override
  void dispose() {
    _search.dispose();
    _weatherService.dispose();
    super.dispose();
  }

  Future<void> _loadWeather() async {
    try {
      final w = await _weatherService.fetchCurrent();
      if (mounted) setState(() => _weather = w);
    } catch (_) {
      // Weather is a nice-to-have; if it fails we just hide the line.
    }
  }

  void _reload() =>
      setState(() => _future = widget.api.fetchTopCategories());

  void _openCategory(Category c) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SwipeScreen(api: widget.api, auth: widget.auth, category: c),
      ),
    );
  }

  Future<void> _openAuth() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AuthScreen(auth: widget.auth)),
    );
    if (ok == true) widget.auth.refreshProfile();
  }

  void _submitSearch(String term) {
    final q = term.trim();
    if (q.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SwipeScreen(
          api: widget.api,
          auth: widget.auth,
          filters: {'keyword': q},
          titleOverride: '"$q"',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async => _reload(),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _BrandHeader(
                  auth: widget.auth,
                  weather: _weather,
                  onLogin: _openAuth,
                ),
              ),
              SliverToBoxAdapter(child: _searchBar()),
              SliverToBoxAdapter(child: _discoverBanner()),
              SliverToBoxAdapter(child: _sectionLabel('Browse by category')),
              _list(),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0F1B2430),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: TextField(
          controller: _search,
          textInputAction: TextInputAction.search,
          onSubmitted: _submitSearch,
          decoration: InputDecoration(
            hintText: 'Search Listit',
            hintStyle: const TextStyle(color: AppColors.muted),
            prefixIcon: const Icon(Icons.search, color: AppColors.slate),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 0),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
            ),
          ),
        ),
      ),
    );
  }

  Widget _discoverBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Material(
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onDiscover,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.style_rounded,
                      color: AppColors.primary, size: 24),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Discover',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Swipe through everything on the island',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios,
                    color: Colors.white70, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 16,
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
        if (snap.connectionState == ConnectionState.waiting) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            ),
          );
        }
        if (snap.hasError) {
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
        final cats = snap.data ?? const [];
        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) => _CategoryRow(
              category: cats[i],
              onTap: () => _openCategory(cats[i]),
            ),
            childCount: cats.length,
          ),
        );
      },
    );
  }
}

class _BrandHeader extends StatelessWidget {
  final AuthService auth;
  final Weather? weather;
  final VoidCallback onLogin;
  const _BrandHeader({
    required this.auth,
    required this.weather,
    required this.onLogin,
  });

  /// A warm, time-of-day greeting - personalised with the user's first name
  /// once they are signed in. Keeps the home screen feeling personal rather
  /// than a wall of listings.
  static String _greeting(AppUser? user) {
    final h = DateTime.now().hour;
    final String part;
    final String emoji;
    if (h < 12) {
      part = 'Good morning';
      emoji = '🌞';
    } else if (h < 17) {
      part = 'Good afternoon';
      emoji = '🌤️';
    } else {
      part = 'Good evening';
      emoji = '🌙';
    }
    if (user != null) {
      final first = user.displayName.trim().split(RegExp(r'\s+')).first;
      return '$part, $first $emoji';
    }
    return '$part $emoji';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset(
                'assets/listit_logo.png',
                height: 30,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
              const Spacer(),
              ListenableBuilder(
                listenable: auth,
                builder: (context, _) {
                  if (!auth.isLoggedIn) {
                    return OutlinedButton(
                      onPressed: onLogin,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary, width: 1.4),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Log in'),
                    );
                  }
                  final u = auth.user!;
                  return Container(
                    width: 34,
                    height: 34,
                    decoration: const BoxDecoration(
                        color: AppColors.primary, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Text(
                      u.initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          ListenableBuilder(
            listenable: auth,
            builder: (context, _) => Text(
              _greeting(auth.user),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
                letterSpacing: -0.3,
              ),
            ),
          ),
          if (weather != null)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                _weatherLine(weather!),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  color: AppColors.slate,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _weatherLine(Weather w) {
    final desc = w.description.isNotEmpty ? ' · ${w.description}' : '';
    return '${w.emoji}  ${w.tempRounded}°C · ${w.place}$desc';
  }
}

class _CategoryRow extends StatelessWidget {
  final Category category;
  final VoidCallback onTap;
  const _CategoryRow({required this.category, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.line)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.line),
              ),
              clipBehavior: Clip.antiAlias,
              padding: const EdgeInsets.all(6),
              child: NetworkPhoto(
                url: category.imageUrl,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                category.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            if (category.adCount > 0)
              Container(
                margin: const EdgeInsets.only(right: 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF3FF),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _grouped(category.adCount),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            const Icon(Icons.arrow_forward_ios,
                size: 15, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}
