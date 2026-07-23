import 'package:flutter/material.dart';

import '../models/category.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/network_photo.dart';
import 'auth/auth_screen.dart';
import 'swipe_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _future = widget.api.fetchTopCategories();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
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
                child: _BrandHeader(auth: widget.auth, onLogin: _openAuth),
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        controller: _search,
        textInputAction: TextInputAction.search,
        onSubmitted: _submitSearch,
        decoration: InputDecoration(
          hintText: 'Search Listit',
          hintStyle: const TextStyle(color: AppColors.muted),
          prefixIcon: const Icon(Icons.search, color: AppColors.slate),
          filled: true,
          fillColor: AppColors.surface,
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
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
  final VoidCallback onLogin;
  const _BrandHeader({required this.auth, required this.onLogin});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
      child: Row(
        children: [
          RichText(
            text: const TextSpan(
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
              children: [
                TextSpan(text: 'list', style: TextStyle(color: AppColors.ink)),
                TextSpan(text: 'it', style: TextStyle(color: AppColors.primary)),
              ],
            ),
          ),
          const Spacer(),
          ListenableBuilder(
            listenable: auth,
            builder: (context, _) {
              if (!auth.isLoggedIn) {
                return TextButton(
                  onPressed: onLogin,
                  child: const Text(
                    'Log In',
                    style: TextStyle(
                      color: AppColors.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }
              final u = auth.user!;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Hi, ${u.displayName.split(' ').first}',
                    style: const TextStyle(
                      color: AppColors.slate,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
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
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: NetworkPhoto(
                url: category.imageUrl,
                width: 48,
                height: 48,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  if (category.adCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '${category.adCount} listings',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.slate,
                        ),
                      ),
                    ),
                ],
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
