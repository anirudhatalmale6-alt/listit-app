import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/network_photo.dart';
import 'auth/auth_screen.dart';
import 'saved_ads_screen.dart';

/// The Profile tab. Reacts to the auth session: a friendly sign-in prompt when
/// signed out, and the account (avatar, saved ads, log out) once signed in.
class ProfileScreen extends StatelessWidget {
  final AuthService auth;
  final ApiService api;
  const ProfileScreen({super.key, required this.auth, required this.api});

  Future<void> _openAuth(BuildContext context) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AuthScreen(auth: auth)),
    );
    if (ok == true) auth.refreshProfile();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('My profile')),
      body: ListenableBuilder(
        listenable: auth,
        builder: (context, _) {
          if (!auth.isLoggedIn) return _signedOut(context);
          return _signedIn(context);
        },
      ),
    );
  }

  Widget _signedOut(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person_outline_rounded,
                  size: 40, color: AppColors.primary),
            ),
            const SizedBox(height: 20),
            const Text(
              'Sign in to Listit',
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.ink),
            ),
            const SizedBox(height: 10),
            const Text(
              'Save the ads you love, message sellers and\nlist your own items in a couple of taps.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, height: 1.5, color: AppColors.slate),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => _openAuth(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Sign in or create account',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _signedIn(BuildContext context) {
    final u = auth.user!;
    return ListView(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Row(
            children: [
              _avatar(u.avatar, u.initials),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      u.displayName,
                      style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(u.email,
                        style: const TextStyle(
                            fontSize: 14, color: AppColors.slate)),
                    if (u.isDealer && u.reviews > 0) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.star_rounded,
                              size: 18, color: AppColors.save),
                          const SizedBox(width: 4),
                          Text('${u.rating.toStringAsFixed(1)} (${u.reviews})',
                              style: const TextStyle(
                                  fontSize: 13, color: AppColors.slate)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _tile(
          icon: Icons.bookmark_border_rounded,
          label: 'Saved ads',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SavedAdsScreen(api: api, userId: u.id),
            ),
          ),
        ),
        _tile(
          icon: Icons.local_offer_outlined,
          label: 'My listings',
          trailing: 'Coming soon',
          onTap: null,
        ),
        _tile(
          icon: Icons.chat_bubble_outline_rounded,
          label: 'Messages',
          trailing: 'Coming soon',
          onTap: null,
        ),
        const SizedBox(height: 12),
        _tile(
          icon: Icons.logout_rounded,
          label: 'Log out',
          danger: true,
          onTap: () => auth.logout(),
        ),
      ],
    );
  }

  Widget _avatar(String? url, String initials) {
    if (url != null && url.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: NetworkPhoto(url: url, width: 60, height: 60),
      );
    }
    return Container(
      width: 60,
      height: 60,
      decoration: const BoxDecoration(
          color: AppColors.primary, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(initials,
          style: const TextStyle(
              color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
    );
  }

  Widget _tile({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
    String? trailing,
    bool danger = false,
  }) {
    final color = danger ? AppColors.danger : AppColors.ink;
    return Container(
      color: Colors.white,
      child: ListTile(
        leading: Icon(icon, color: danger ? AppColors.danger : AppColors.slate),
        title: Text(label,
            style: TextStyle(
                color: color, fontSize: 15, fontWeight: FontWeight.w600)),
        trailing: trailing != null
            ? Text(trailing,
                style: const TextStyle(color: AppColors.muted, fontSize: 13))
            : (onTap != null
                ? const Icon(Icons.arrow_forward_ios,
                    size: 15, color: AppColors.muted)
                : null),
        enabled: onTap != null,
        onTap: onTap,
      ),
    );
  }
}
