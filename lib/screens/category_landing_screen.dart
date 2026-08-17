import 'package:flutter/material.dart';

import '../models/category.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import 'results_screen.dart';

/// A DoneDeal-style category landing page: when a section has sub-areas
/// (Property -> Houses, Apartments, To Let, ...) we show the clean sub-category
/// list first, with a "See all in X" shortcut, then drill into the filtered
/// results. Sections with no sub-areas skip straight to the results list.
class CategoryLandingScreen extends StatefulWidget {
  final ApiService api;
  final AuthService auth;
  final Category category;

  const CategoryLandingScreen({
    super.key,
    required this.api,
    required this.auth,
    required this.category,
  });

  @override
  State<CategoryLandingScreen> createState() => _CategoryLandingScreenState();
}

class _CategoryLandingScreenState extends State<CategoryLandingScreen> {
  List<Category>? _all;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final all = await widget.api.fetchAllCategories();
      if (!mounted) return;
      final children =
          all.where((c) => c.parentId == widget.category.id).toList();
      // No sub-areas: this section is a plain results list, so go straight there.
      if (children.isEmpty) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => ResultsScreen(
              api: widget.api, auth: widget.auth, category: widget.category),
        ));
        return;
      }
      setState(() => _all = all);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  List<Category> _childrenOf(int id) {
    final list = (_all ?? []).where((c) => c.parentId == id).toList();
    list.sort((a, b) => b.adCount.compareTo(a.adCount));
    return list;
  }

  void _openResults(Category c) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          ResultsScreen(api: widget.api, auth: widget.auth, category: c),
    ));
  }

  void _openChild(Category c) {
    final hasKids = _childrenOf(c.id).isNotEmpty;
    if (hasKids) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CategoryLandingScreen(
            api: widget.api, auth: widget.auth, category: c),
      ));
    } else {
      _openResults(c);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: Text(widget.category.name)),
      body: _error != null
          ? _errorState()
          : _all == null
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary))
              : _list(),
    );
  }

  Widget _list() {
    final children = _childrenOf(widget.category.id);
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        // "See all in X" shortcut into the full results list for this section.
        Container(
          margin: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.line),
          ),
          child: ListTile(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.card)),
            leading: const Icon(Icons.grid_view_rounded,
                color: AppColors.primary),
            title: Text('See all in ${widget.category.name}',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: AppColors.ink)),
            trailing:
                const Icon(Icons.arrow_forward_ios, size: 15, color: AppColors.muted),
            onTap: () => _openResults(widget.category),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text('Browse by type',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.slate)),
        ),
        for (final c in children)
          InkWell(
            onTap: () => _openChild(c),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.line)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(c.name,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink)),
                  ),
                  if (_childrenOf(c.id).isNotEmpty)
                    const Text('›',
                        style: TextStyle(
                            fontSize: 20, color: AppColors.muted, height: 1)),
                  const SizedBox(width: 6),
                  const Icon(Icons.arrow_forward_ios,
                      size: 15, color: AppColors.muted),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 44, color: AppColors.muted),
            const SizedBox(height: 14),
            const Text('Could not load this section.',
                style: TextStyle(color: AppColors.slate)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
