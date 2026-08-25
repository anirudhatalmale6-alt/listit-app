import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/app_user.dart';
import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../services/auth_service.dart';
import '../services/recently_viewed.dart';
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

/// The Profile tab: one flat menu of rows, signed in or out.
///
/// Signed out shows the same menu rather than a sign-in poster with the menu
/// hidden behind it - tapping a row that needs an account asks for one on the
/// way. Keeping both states the same shape is what stops the screen reading as
/// a landing page.
class ProfileScreen extends StatefulWidget {
  final AuthService auth;
  final ApiService api;

  /// Jumps to the New Ad tab from the header button.
  final VoidCallback? onPlaceAd;

  const ProfileScreen({
    super.key,
    required this.auth,
    required this.api,
    this.onPlaceAd,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int? _myAds;
  int? _savedAds;
  int? _savedSearches;
  int? _viewed;

  @override
  void initState() {
    super.initState();
    widget.auth.addListener(_onAuthChanged);
    _countsFor = widget.auth.user?.id;
    _loadCounts();
  }

  @override
  void dispose() {
    widget.auth.removeListener(_onAuthChanged);
    super.dispose();
  }

  int? _countsFor;

  /// Auth notifies on every profile refresh, not only on sign in/out, and each
  /// reload costs three requests - so only refetch when the account actually
  /// changed.
  void _onAuthChanged() {
    final id = widget.auth.user?.id;
    if (id == _countsFor) return;
    _countsFor = id;
    _loadCounts();
  }

  /// The numbers beside Saved ads / My listings. Best-effort: a count that
  /// fails to load is left off the row rather than shown as a zero, because a
  /// wrong zero reads as "you have nothing saved".
  Future<void> _loadCounts() async {
    final viewed = await RecentlyViewed.load();
    if (mounted) setState(() => _viewed = viewed.length);

    final u = widget.auth.user;
    if (u == null) {
      if (mounted) {
        setState(() {
          _myAds = null;
          _savedAds = null;
          _savedSearches = null;
        });
      }
      return;
    }

    widget.api
        .listMyAds(userId: u.id, limit: 1)
        .then((r) => mounted ? setState(() => _myAds = r.total) : null)
        .catchError((_) {});
    widget.api
        .listSavedAds(userId: u.id)
        .then((l) => mounted ? setState(() => _savedAds = l.length) : null)
        .catchError((_) {});
    widget.api
        .listSavedSearches(userId: u.id)
        .then((l) => mounted ? setState(() => _savedSearches = l.length) : null)
        .catchError((_) {});
  }

  Future<void> _openAuth(BuildContext context, {String? reason}) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AuthScreen(auth: widget.auth, reason: reason),
      ),
    );
    if (ok == true) {
      widget.auth.refreshProfile();
      _loadCounts();
    }
  }

  /// Opens [builder], asking for an account first if there isn't one. Signed
  /// out, the row still works - it just goes through the sign-in screen.
  Future<void> _openGated(
    BuildContext context,
    String reason,
    Widget Function() builder,
  ) async {
    if (!widget.auth.isLoggedIn) {
      await _openAuth(context, reason: reason);
      if (!widget.auth.isLoggedIn || !mounted) return;
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => builder()));
    _loadCounts();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // A white header, so the clock and signal bars have to be drawn dark -
      // the Browse tab sets them light for its navy bar and the two tabs would
      // otherwise fight over it.
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: Column(
          children: [
            _topBar(),
            Expanded(
              child: ListenableBuilder(
                listenable: widget.auth,
                builder: (context, _) => _menu(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    final mq = MediaQuery.of(context);
    final topPad = mq.padding.top > 0 ? mq.padding.top : mq.viewPadding.top;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      padding: EdgeInsets.fromLTRB(16, topPad + 10, 8, 10),
      child: Row(
        children: [
          Image.asset(
            'assets/listit_logo.png',
            height: 26,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            color: AppColors.primary,
            colorBlendMode: BlendMode.srcIn,
          ),
          const Spacer(),
          TextButton(
            onPressed: widget.onPlaceAd,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.ink,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: const Text('Place Ad',
                style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _menu(BuildContext context) {
    final u = widget.auth.user;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        u == null ? _signInHeader(context) : _accountHeader(context, u),
        const SizedBox(height: 10),
        if (u != null) ...[
          _group([
            _verifyRow(context, u.fullyVerified, u.emailVerified, u.phoneVerified),
          ]),
          const SizedBox(height: 10),
        ],
        _group([
          if (u != null)
            _MenuRow(
              icon: Icons.person_outline_rounded,
              label: 'Profile',
              onTap: () async {
                final ok = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) =>
                        EditProfileScreen(auth: widget.auth, api: widget.api),
                  ),
                );
                if (ok == true) widget.auth.refreshProfile();
              },
            ),
          _MenuRow(
            icon: Icons.edit_note_rounded,
            label: 'My ads',
            count: _myAds,
            onTap: () => _openGated(context, 'Sign in to see your ads',
                () => MyListingsScreen(api: widget.api, auth: widget.auth)),
          ),
          _MenuRow(
            icon: Icons.favorite_border_rounded,
            label: 'Saved ads',
            count: _savedAds,
            onTap: () => _openGated(
                context,
                'Sign in to see your saved ads',
                () => SavedAdsScreen(
                    api: widget.api, userId: widget.auth.user?.id ?? 0)),
          ),
          _MenuRow(
            icon: Icons.star_border_rounded,
            label: 'Saved searches',
            count: _savedSearches,
            onTap: () => _openGated(
                context,
                'Sign in to see your saved searches',
                () => SavedSearchesScreen(api: widget.api, auth: widget.auth)),
          ),
          _MenuRow(
            icon: Icons.access_time_rounded,
            label: 'Browsing history',
            // Kept on the device, so this one works signed out too.
            count: _viewed == 0 ? null : _viewed,
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => RecentlyViewedScreen(api: widget.api)));
              _loadCounts();
            },
          ),
          _MenuRow(
            icon: Icons.chat_bubble_outline_rounded,
            label: 'Messages',
            onTap: () => _openGated(context, 'Sign in to see your messages',
                () => MessagesScreen(api: widget.api, auth: widget.auth)),
          ),
        ]),
        const SizedBox(height: 10),
        _group([_handednessRow()]),
        const SizedBox(height: 10),
        _group(_settingsRows(context)),
        if (u != null) ...[
          const SizedBox(height: 10),
          _group([
            _MenuRow(
              icon: Icons.logout_rounded,
              label: 'Log out',
              iconColor: AppColors.danger,
              labelColor: AppColors.danger,
              onTap: () => widget.auth.logout(),
            ),
          ]),
        ],
        const SizedBox(height: 18),
        const Center(child: _VersionLabel()),
        const SizedBox(height: 24),
      ],
    );
  }

  /// Signed out. Same block, same height and same position as the account
  /// block - one row at the top of the menu, not a page of its own.
  Widget _signInHeader(BuildContext context) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () => _openAuth(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                    color: AppColors.surface, shape: BoxShape.circle),
                child: const Icon(Icons.person_rounded,
                    size: 30, color: AppColors.muted),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sign in or create account',
                        style: TextStyle(
                            fontSize: 17.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink)),
                    SizedBox(height: 3),
                    Text('Save ads, message sellers and post your own',
                        style: TextStyle(fontSize: 13.5, color: AppColors.slate)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios,
                  size: 15, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _accountHeader(BuildContext context, AppUser u) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
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
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink),
                ),
                const SizedBox(height: 2),
                Text(u.email,
                    style:
                        const TextStyle(fontSize: 14, color: AppColors.slate)),
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
    );
  }

  /// Handedness: moves tick boxes / controls nearer the left thumb. A device
  /// setting, so it's here signed in or out.
  Widget _handednessRow() {
    return ValueListenableBuilder<bool>(
      valueListenable: AppSettings.leftHanded,
      builder: (context, left, _) => _MenuRow(
        icon: Icons.back_hand_outlined,
        label: 'Left-hand mode',
        subtitle: 'Moves the tick boxes nearer your left thumb',
        onTap: () => AppSettings.setLeftHanded(!left),
        trailing: Switch(
          value: left,
          activeThumbColor: AppColors.primary,
          onChanged: (v) => AppSettings.setLeftHanded(v),
        ),
      ),
    );
  }

  /// Settings & support: notifications, consent, help, support, legal and data
  /// requests. Links open the matching pages on the website.
  List<Widget> _settingsRows(BuildContext context) {
    return [
      _MenuRow(
        icon: Icons.notifications_none_rounded,
        label: 'Notifications',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const NotificationsScreen()),
        ),
      ),
      _MenuRow(
        icon: Icons.privacy_tip_outlined,
        label: 'Consent options',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ConsentScreen()),
        ),
      ),
      _MenuRow(
        icon: Icons.public_rounded,
        label: 'Social media',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SocialMediaScreen()),
        ),
      ),
      _MenuRow(
        icon: Icons.gavel_rounded,
        label: 'Legal policies',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const LegalPoliciesScreen()),
        ),
      ),
      _MenuRow(
        icon: Icons.download_outlined,
        label: 'Data requests',
        onTap: () => ListitLinks.open(ListitLinks.dataRequest),
      ),
      _MenuRow(
        icon: Icons.help_outline_rounded,
        label: 'Help',
        onTap: () => ListitLinks.open(ListitLinks.help),
      ),
      _MenuRow(
        icon: Icons.support_agent_rounded,
        label: 'Customer support',
        onTap: () => ListitLinks.open(ListitLinks.contact),
      ),
    ];
  }

  Future<void> _openVerify(BuildContext context) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
          builder: (_) => VerifyScreen(auth: widget.auth, api: widget.api)),
    );
  }

  /// Account verification status + shortcut. Green and reassuring when done; a
  /// gentle amber nudge with what's still outstanding when not.
  Widget _verifyRow(
      BuildContext context, bool done, bool email, bool phone) {
    final color = done ? AppColors.success : AppColors.save;
    final subtitle = done
        ? 'Email and phone verified'
        : 'Verify ${!email && !phone ? 'email & phone' : !email ? 'your email' : 'your phone'} to post ads';
    return _MenuRow(
      icon: done ? Icons.verified_rounded : Icons.gpp_maybe_outlined,
      iconColor: color,
      label: done ? 'Account verified' : 'Verify your account',
      subtitle: subtitle,
      onTap: () => _openVerify(context),
    );
  }

  /// A white block of rows with hairlines between them - no card, no rounding,
  /// edge to edge, the way the marketplace apps draw their menus.
  Widget _group(List<Widget> rows) {
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) {
        children.add(const Divider(
            height: 1, thickness: 1, indent: 0, color: AppColors.line));
      }
      children.add(rows[i]);
    }
    return Container(color: Colors.white, child: Column(children: children));
  }

  Widget _avatar(String? url, String initials) {
    if (url != null && url.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: NetworkPhoto(url: url, width: 52, height: 52),
      );
    }
    return Container(
      width: 52,
      height: 52,
      decoration: const BoxDecoration(
          color: AppColors.primary, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(initials,
          style: const TextStyle(
              color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
    );
  }
}

/// One menu row: icon, label, optional count on the right. No chevron - a menu
/// of twelve of them turns into a column of arrows, which is exactly what the
/// apps Chris compared us against don't do.
class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final int? count;
  final Color? iconColor;
  final Color? labelColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _MenuRow({
    required this.icon,
    required this.label,
    this.subtitle,
    this.count,
    this.iconColor,
    this.labelColor,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 14, trailing != null ? 12 : 20, 14),
          child: Row(
            children: [
              Icon(icon, size: 23, color: iconColor ?? AppColors.ink),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w500,
                            color: labelColor ?? AppColors.ink)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!,
                          style: const TextStyle(
                              fontSize: 12.5, color: AppColors.slate)),
                    ],
                  ],
                ),
              ),
              if (count != null)
                Text('$count',
                    style: const TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.slate)),
              ?trailing,
            ],
          ),
        ),
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
