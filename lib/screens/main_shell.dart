import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme.dart';
import 'browse_screen.dart';
import 'swipe_screen.dart';
import 'placeholder_screen.dart';

/// The app shell: a persistent bottom toolbar (DoneDeal-style) that keeps each
/// tab's state alive via an IndexedStack. Discover - the swipe deck - sits
/// right in the toolbar as its own destination, as Chris asked.
class MainShell extends StatefulWidget {
  final ApiService api;
  const MainShell({super.key, required this.api});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  late final List<Widget> _tabs = [
    BrowseScreen(api: widget.api, onDiscover: () => _select(1)),
    SwipeScreen(api: widget.api), // Discover
    const PlaceholderScreen(
      icon: Icons.add_circle_outline,
      title: 'Place an ad',
      message:
          'Quick-list in under two minutes - snap a photo, set a price, done.\nArrives in the next phase.',
    ),
    const PlaceholderScreen(
      icon: Icons.chat_bubble_outline_rounded,
      title: 'Messages',
      message:
          'Chat with buyers and sellers, make and accept offers.\nArrives in the next phase alongside accounts.',
    ),
    const PlaceholderScreen(
      icon: Icons.person_outline_rounded,
      title: 'My profile',
      message:
          'Your listings, saved items, ratings and verification.\nArrives in the next phase alongside accounts.',
    ),
  ];

  void _select(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: _BottomBar(index: _index, onTap: _select),
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
    _NavItem('Sell', Icons.local_offer_outlined),
    _NavItem('Messages', Icons.chat_bubble_outline_rounded),
    _NavItem('Profile', Icons.person_outline_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.ink,
        boxShadow: [
          BoxShadow(color: Color(0x22000000), blurRadius: 8, offset: Offset(0, -2)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
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
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(item.icon, color: color, size: 24),
          const SizedBox(height: 3),
          Text(
            item.label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
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
