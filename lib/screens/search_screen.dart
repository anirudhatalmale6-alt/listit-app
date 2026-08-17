import 'package:flutter/material.dart';

import '../models/category.dart';
import '../models/saved_search.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/recent_searches.dart';
import '../theme.dart';
import 'results_screen.dart';

/// A dedicated Search screen, DoneDeal-style: type a term, or pick one of your
/// recent searches or a saved (starred) search to re-run it. [scope] narrows
/// the search to one section (e.g. Cars & Motors) when set from a home tab.
class SearchScreen extends StatefulWidget {
  final ApiService api;
  final AuthService auth;
  final Category? scope;

  /// Filters always applied to searches from here (e.g. Marketplace forces
  /// private sellers only, like the website).
  final Map<String, dynamic> baseFilters;
  const SearchScreen(
      {super.key,
      required this.api,
      required this.auth,
      this.scope,
      this.baseFilters = const {}});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  List<String> _recent = const [];
  List<SavedSearch> _saved = const [];
  bool _loadingSaved = false;

  @override
  void initState() {
    super.initState();
    _loadRecent();
    _loadSaved();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    final r = await RecentSearches.load();
    if (mounted) setState(() => _recent = r);
  }

  Future<void> _loadSaved() async {
    if (!widget.auth.isLoggedIn) return;
    setState(() => _loadingSaved = true);
    try {
      final s = await widget.api.listSavedSearches(userId: widget.auth.user!.id);
      if (mounted) setState(() => _saved = s);
    } catch (_) {
      // best-effort
    } finally {
      if (mounted) setState(() => _loadingSaved = false);
    }
  }

  Future<void> _runKeyword(String term) async {
    final q = term.trim();
    final scope = widget.scope;
    if (q.isEmpty) {
      // DoneDeal-style: hitting search with nothing typed browses the whole
      // section (or the whole site), newest first (same order as the website).
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ResultsScreen(
          api: widget.api,
          auth: widget.auth,
          category: scope,
          baseFilters: widget.baseFilters,
          titleOverride: scope == null ? 'All ads' : null,
        ),
      ));
      return;
    }
    await RecentSearches.add(q);
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ResultsScreen(
        api: widget.api,
        auth: widget.auth,
        category: scope,
        baseFilters: {...widget.baseFilters, 'keyword': q},
        titleOverride: '"$q"',
      ),
    ));
    _loadRecent();
  }

  void _runSaved(SavedSearch s) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ResultsScreen(
        api: widget.api,
        auth: widget.auth,
        baseFilters: s.toFilters(),
        titleOverride: s.title.isEmpty ? null : s.title,
      ),
    ));
  }

  Future<void> _deleteSaved(SavedSearch s) async {
    setState(() => _saved = _saved.where((e) => e.id != s.id).toList());
    try {
      await widget.api.deleteSavedSearch(id: s.id);
    } catch (_) {
      _loadSaved(); // restore on failure
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        titleSpacing: 0,
        title: Container(
          height: 42,
          margin: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: TextField(
            controller: _ctrl,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: _runKeyword,
            decoration: InputDecoration(
              hintText: widget.scope == null
                  ? 'Search Listit'
                  : 'Search ${widget.scope!.name}',
              prefixIcon: const Icon(Icons.search, color: AppColors.slate),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (_recent.isNotEmpty) ...[
            _sectionHeader('Recent searches',
                action: TextButton(
                  onPressed: () async {
                    await RecentSearches.clear();
                    _loadRecent();
                  },
                  child: const Text('Clear all'),
                )),
            for (final term in _recent) _recentRow(term),
            const SizedBox(height: 20),
          ],
          _sectionHeader('Saved searches'),
          if (!widget.auth.isLoggedIn)
            _hint('Sign in to save your searches and access them anytime.')
          else if (_loadingSaved && _saved.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_saved.isEmpty)
            _hint(
                'No saved searches yet. Run a search, then tap "Save search" at the top to star it.')
          else
            for (final s in _saved) _savedRow(s),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, {Widget? action}) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Row(
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink)),
          const Spacer(),
          ?action,
        ],
      ),
    );
  }

  Widget _recentRow(String term) {
    return InkWell(
      onTap: () => _runKeyword(term),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.history_rounded, color: AppColors.muted, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Text(term,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, color: AppColors.ink)),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.muted),
              onPressed: () async {
                await RecentSearches.remove(term);
                _loadRecent();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _savedRow(SavedSearch s) {
    final subtitle = [
      if (s.category.isNotEmpty) 'Section',
      if (s.location.isNotEmpty) s.location,
    ].join(' · ');
    return InkWell(
      onTap: () => _runSaved(s),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.bookmark_rounded, color: AppColors.primary, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.title.isEmpty ? (s.keyword.isEmpty ? 'Saved search' : s.keyword) : s.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink)),
                  if (subtitle.isNotEmpty)
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 12.5, color: AppColors.slate)),
                ],
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline_rounded,
                  size: 20, color: AppColors.muted),
              onPressed: () => _deleteSaved(s),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hint(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text(text,
            style: const TextStyle(color: AppColors.slate, height: 1.35)),
      );
}
