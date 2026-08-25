import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import 'browse_screen.dart';
import 'swipe_screen.dart';
import 'messages_screen.dart';
import 'profile_screen.dart';
import 'sell/sell_flow_screen.dart';

/// The app shell: a persistent bottom toolbar (DoneDeal-style) that keeps each
/// tab's state alive via an IndexedStack. Discover - the swipe deck - sits
/// right in the toolbar as its own destination.
class MainShell extends StatefulWidget {
  final ApiService api;
  final AuthService auth;
  const MainShell({super.key, required this.api, required this.auth});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _index = 0;
  int _unread = 0;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.auth.addListener(_refreshUnread);
    _refreshUnread();
    // Light enough not to matter on battery, often enough that a reply shows up
    // while you are still in the app.
    _poll = Timer.periodic(const Duration(seconds: 45), (_) => _refreshUnread());
  }

  @override
  void dispose() {
    _poll?.cancel();
    widget.auth.removeListener(_refreshUnread);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshUnread();
  }

  /// Total unread across every conversation, from whichever side of it I am on.
  /// Silent by design: a failure here must never interrupt what you were doing.
  Future<void> _refreshUnread() async {
    final me = widget.auth.user?.id ?? 0;
    if (me == 0) {
      if (mounted && _unread != 0) setState(() => _unread = 0);
      return;
    }
    try {
      final list = await widget.api.listConversations(userId: me);
      var total = 0;
      for (final c in list) {
        total += c.unreadFor(me);
      }
      if (mounted && total != _unread) setState(() => _unread = total);
    } catch (_) {/* leave the badge as it was */}
  }

  late final List<Widget> _tabs = [
    BrowseScreen(api: widget.api, auth: widget.auth, onDiscover: () => _select(1)),
    SwipeScreen(api: widget.api, auth: widget.auth), // Discover
    SellFlowScreen(api: widget.api, auth: widget.auth),
    MessagesScreen(api: widget.api, auth: widget.auth),
    ProfileScreen(
        api: widget.api, auth: widget.auth, onPlaceAd: () => _select(2)),
  ];

  void _select(int i) {
    final leavingMessages = _index == 3 && i != 3;
    setState(() => _index = i);
    // Reading them is what clears them, so re-check on the way out.
    if (leavingMessages || i == 3) _refreshUnread();
  }

  @override
  Widget build(BuildContext context) {
    // Back on any tab other than Browse returns to Browse instead of dropping
    // out of the app - so pressing back from Discover doesn't close Listit.
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(0);
      },
      child: Scaffold(
        body: IndexedStack(index: _index, children: _tabs),
        bottomNavigationBar:
            _BottomBar(index: _index, onTap: _select, unread: _unread),
      ),
    );
  }
}

/// Custom dark toolbar modelled on DoneDeal's - navy background, white active
/// item, muted inactive. Kept custom (rather than NavigationBar) so the dark
/// styling and the 5th "Discover" destination sit exactly right.
class _BottomBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final int unread;
  const _BottomBar({
    required this.index,
    required this.onTap,
    this.unread = 0,
  });

  static const _items = <_NavItem>[
    _NavItem('Browse', Icons.search),
    _NavItem('Discover', Icons.style_rounded),
    // Flat, like its neighbours. A raised blue circle in the middle of a tab
    // bar is the single most template-looking thing in mobile design, and
    // DoneDeal's bar does not have one.
    _NavItem('New Ad', Icons.sell_outlined),
    _NavItem('Messages', Icons.chat_bubble_outline_rounded),
    _NavItem('Profile', Icons.person_outline_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      // Flat navy with a hairline on top instead of a drop shadow - the bar
      // should sit under the page, not hover over it.
      decoration: const BoxDecoration(
        color: AppColors.ink,
        border: Border(top: BorderSide(color: Color(0xFF2C3846))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(
                  child: _BottomBarButton(
                    item: _items[i],
                    active: i == index,
                    onTap: () => onTap(i),
                    badge: _items[i].label == 'Messages' ? unread : 0,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomBarButton extends StatelessWidget {
  final _NavItem item;
  final bool active;
  final VoidCallback onTap;
  final int badge;
  const _BottomBarButton({
    required this.item,
    required this.active,
    required this.onTap,
    this.badge = 0,
  });

  /// The red count sitting on the corner of the icon. Capped at 99+ so a long
  /// silence cannot stretch the toolbar.
  Widget _withBadge(Widget icon) {
    if (badge <= 0) return icon;
    final text = badge > 99 ? '99+' : '$badge';
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          right: -9,
          top: -5,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            constraints: const BoxConstraints(minWidth: 17),
            decoration: BoxDecoration(
              color: const Color(0xFFE11D48),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: AppColors.ink, width: 1.5),
            ),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = active ? Colors.white : const Color(0xFF97A2AE);
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _withBadge(Icon(item.icon, color: color, size: 22)),
          const SizedBox(height: 3),
          Text(
            item.label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem {
  final String label;
  final IconData icon;
  const _NavItem(this.label, this.icon);
}
