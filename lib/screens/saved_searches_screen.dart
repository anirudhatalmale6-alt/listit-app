import 'package:flutter/material.dart';

import '../models/saved_search.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import 'auth/auth_screen.dart';
import 'results_screen.dart';

/// The user's starred (saved) searches - re-run any of them in a tap. Mirrors
/// the list on the Search screen, as a standalone destination for the home
/// button and the profile menu.
class SavedSearchesScreen extends StatefulWidget {
  final ApiService api;
  final AuthService auth;
  const SavedSearchesScreen({super.key, required this.api, required this.auth});

  @override
  State<SavedSearchesScreen> createState() => _SavedSearchesScreenState();
}

class _SavedSearchesScreenState extends State<SavedSearchesScreen> {
  List<SavedSearch> _saved = const [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!widget.auth.isLoggedIn) return;
    setState(() => _loading = true);
    try {
      final s = await widget.api.listSavedSearches(userId: widget.auth.user!.id);
      if (mounted) setState(() => _saved = s);
    } catch (_) {
      // best-effort
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signIn() async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) =>
          AuthScreen(auth: widget.auth, reason: 'Sign in to see your saved searches'),
    ));
    if (ok == true) {
      widget.auth.refreshProfile();
      _load();
    }
  }

  void _run(SavedSearch s) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ResultsScreen(
        api: widget.api,
        auth: widget.auth,
        baseFilters: s.toFilters(),
        titleOverride: s.title.isEmpty ? null : s.title,
      ),
    ));
  }

  Future<void> _delete(SavedSearch s) async {
    setState(() => _saved = _saved.where((e) => e.id != s.id).toList());
    try {
      await widget.api.deleteSavedSearch(id: s.id);
    } catch (_) {
      _load(); // restore on failure
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Saved Searches')),
      body: !widget.auth.isLoggedIn
          ? _prompt()
          : _loading && _saved.isEmpty
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary))
              : _saved.isEmpty
                  ? _empty()
                  : RefreshIndicator(
                      color: AppColors.primary,
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: _saved.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, indent: 16, endIndent: 16),
                        itemBuilder: (context, i) => _row(_saved[i]),
                      ),
                    ),
    );
  }

  Widget _row(SavedSearch s) {
    final subtitle = [
      if (s.category.isNotEmpty) 'Section',
      if (s.location.isNotEmpty) s.location,
    ].join(' · ');
    return Container(
      color: Colors.white,
      child: ListTile(
        leading: const Icon(Icons.bookmark_rounded, color: AppColors.primary),
        title: Text(
          s.title.isEmpty ? (s.keyword.isEmpty ? 'Saved search' : s.keyword) : s.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink),
        ),
        subtitle: subtitle.isEmpty
            ? null
            : Text(subtitle,
                style: const TextStyle(fontSize: 12.5, color: AppColors.slate)),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline_rounded, color: AppColors.muted),
          onPressed: () => _delete(s),
        ),
        onTap: () => _run(s),
      ),
    );
  }

  Widget _empty() => const _Message(
      icon: Icons.bookmark_border_rounded,
      text:
          'No saved searches yet.\nRun a search, then tap "Save search" at the top to star it.');

  Widget _prompt() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bookmark_border_rounded,
                  size: 48, color: AppColors.muted),
              const SizedBox(height: 16),
              const Text('Sign in to see your saved searches.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.slate, fontSize: 15)),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: _signIn, child: const Text('Sign in')),
            ],
          ),
        ),
      );
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Message({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.muted),
            const SizedBox(height: 16),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.slate, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}
