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

class _MainShellState extends State<MainShell> {
  int _index = 0;

  late final List<Widget> _tabs = [
    BrowseScreen(api: widget.api, auth: widget.auth, onDiscover: () => _select(1)),
    SwipeScreen(api: widget.api, auth: widget.auth), // Discover
    SellFlowScreen(api: widget.api, auth: widget.auth),
    MessagesScreen(api: widget.api, auth: widget.auth),
    ProfileScreen(api: widget.api, auth: widget.auth),
  ];

  void _select(int i) => setState(() => _index = i);

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
        bottomNavigationBar: _BottomBar(index: _index, onTap: _select),
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
  const _BottomBar({required this.index, required this.onTap});

  static const _items = <_NavItem>[
    _NavItem('Browse', Icons.search),
    _NavItem('Discover', Icons.style_rounded),
    _NavItem('New Ad', Icons.add, raised: true),
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
  const _BottomBarButton({
    required this.item,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? Colors.white : const Color(0xFF97A2AE);
    // The "New Ad" action gets a raised blue circle with a + so it reads as the
    // primary call-to-action, DoneDeal-style.
    if (item.raised) {
      return InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 21),
            ),
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
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(item.icon, color: color, size: 22),
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
  final bool raised;
  const _NavItem(this.label, this.icon, {this.raised = false});
}
