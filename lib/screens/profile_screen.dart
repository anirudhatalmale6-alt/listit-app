import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/network_photo.dart';
import 'auth/auth_screen.dart';
import 'auth/verify_screen.dart';
import 'edit_profile_screen.dart';
import 'messages_screen.dart';
import 'my_listings_screen.dart';
import 'recently_viewed_screen.dart';
import 'saved_ads_screen.dart';
import 'saved_searches_screen.dart';
import 'settings_screens.dart';
import 'social_media_screen.dart';

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
                      borderRadius: BorderRadius.circular(AppRadius.control)),
                ),
                child: const Text('Sign in or create account',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 28),
            _handednessTile(),
            const SizedBox(height: 20),
            const _VersionLabel(),
          ],
        ),
      ),
    );
  }

  /// Handedness: moves tick boxes / controls to the left (right-hand use) or
  /// right (left-hand use) for easier one-handed reach. A device setting, so
  /// it's available signed in or out.
  Widget _handednessTile() {
    return Container(
      color: Colors.white,
      child: ValueListenableBuilder<bool>(
        valueListenable: AppSettings.leftHanded,
        builder: (context, left, _) => SwitchListTile(
          secondary: const Icon(Icons.back_hand_outlined, color: AppColors.slate),
          activeThumbColor: AppColors.primary,
          title: const Text('Left-hand mode',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink)),
          subtitle: const Text(
              'Moves the tick boxes to the left, nearer your left thumb',
              style: TextStyle(fontSize: 12.5, color: AppColors.slate)),
          value: left,
          onChanged: (v) => AppSettings.setLeftHanded(v),
        ),
      ),
    );
  }

  /// The DoneDeal-style "settings & support" block: notifications, consent,
  /// help, support, legal and data requests. Links open the matching pages on
  /// the website; notifications and consent are on-device preference screens.
  List<Widget> _settingsTiles(BuildContext context) {
    return [
      _tile(
        icon: Icons.notifications_none_rounded,
        label: 'Notifications',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const NotificationsScreen()),
        ),
      ),
      _tile(
        icon: Icons.privacy_tip_outlined,
        label: 'Consent options',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ConsentScreen()),
        ),
      ),
      _tile(
        icon: Icons.public_rounded,
        label: 'Social media',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SocialMediaScreen()),
        ),
      ),
      _tile(
        icon: Icons.gavel_rounded,
        label: 'Legal policies',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const LegalPoliciesScreen()),
        ),
      ),
      _tile(
        icon: Icons.download_outlined,
        label: 'Data requests',
        onTap: () => ListitLinks.open(ListitLinks.dataRequest),
      ),
      _tile(
        icon: Icons.help_outline_rounded,
        label: 'Help',
        onTap: () => ListitLinks.open(ListitLinks.help),
      ),
      _tile(
        icon: Icons.support_agent_rounded,
        label: 'Customer support',
        onTap: () => ListitLinks.open(ListitLinks.contact),
      ),
    ];
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
                          fontWeight: FontWeight.w700,
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
        _verifyTile(context, u.fullyVerified, u.emailVerified, u.phoneVerified),
        const SizedBox(height: 12),
        _tile(
          icon: Icons.edit_outlined,
          label: 'Edit profile',
          onTap: () async {
            final ok = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => EditProfileScreen(auth: auth, api: api),
              ),
            );
            if (ok == true) auth.refreshProfile();
          },
        ),
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
          icon: Icons.bookmark_border_rounded,
          label: 'Saved searches',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SavedSearchesScreen(api: api, auth: auth),
            ),
          ),
        ),
        _tile(
          icon: Icons.history_rounded,
          label: 'Recently viewed',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => RecentlyViewedScreen(api: api),
            ),
          ),
        ),
        _tile(
          icon: Icons.local_offer_outlined,
          label: 'My listings',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MyListingsScreen(api: api, auth: auth),
            ),
          ),
        ),
        _tile(
          icon: Icons.chat_bubble_outline_rounded,
          label: 'Messages',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MessagesScreen(api: api, auth: auth),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _handednessTile(),
        const SizedBox(height: 12),
        ..._settingsTiles(context),
        const SizedBox(height: 12),
        _tile(
          icon: Icons.logout_rounded,
          label: 'Log out',
          danger: true,
          onTap: () => auth.logout(),
        ),
        const SizedBox(height: 16),
        const Center(child: _VersionLabel()),
        const SizedBox(height: 24),
      ],
    );
  }

  Future<void> _openVerify(BuildContext context) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => VerifyScreen(auth: auth, api: api)),
    );
  }

  /// Account verification status + shortcut. Green and reassuring when done;
  /// a gentle amber nudge with what's still outstanding when not.
  Widget _verifyTile(
      BuildContext context, bool done, bool email, bool phone) {
    final color = done ? AppColors.success : AppColors.save;
    final subtitle = done
        ? 'Email and phone verified'
        : 'Verify ${!email && !phone ? 'email & phone' : !email ? 'your email' : 'your phone'} to post ads';
    return Container(
      color: Colors.white,
      child: ListTile(
        leading: Icon(
            done ? Icons.verified_rounded : Icons.gpp_maybe_outlined,
            color: color),
        title: Text(done ? 'Account verified' : 'Verify your account',
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink)),
        subtitle: Text(subtitle,
            style: const TextStyle(fontSize: 12.5, color: AppColors.slate)),
        trailing: const Icon(Icons.arrow_forward_ios,
            size: 15, color: AppColors.muted),
        onTap: () => _openVerify(context),
      ),
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

/// Shows the installed app version (read from the build), so it's easy to
/// confirm you're on the latest.
class _VersionLabel extends StatefulWidget {
  const _VersionLabel();

  @override
  State<_VersionLabel> createState() => _VersionLabelState();
}

class _VersionLabelState extends State<_VersionLabel> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = info.version);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_version.isEmpty) return const SizedBox(height: 16);
    return Text('Listit v$_version',
        style: const TextStyle(color: AppColors.muted, fontSize: 12.5));
  }
}
