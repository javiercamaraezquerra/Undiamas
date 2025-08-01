import 'package:flutter/material.dart';

import 'ad_banner.dart';
import '../screens/home_screen.dart';
import '../screens/journal_screen.dart';
import '../screens/reflection_screen.dart';
import '../screens/resources_screen.dart';
import '../screens/profile_screen.dart';
import 'mountain_background.dart';

const _bannerId = 'ca-app-pub-4402835110551152/9099084606';

class BottomNavBar extends StatefulWidget {
  const BottomNavBar({super.key});
  @override
  State<BottomNavBar> createState() => _BottomNavBarState();
}

class _BottomNavBarState extends State<BottomNavBar> {
  int _selectedIndex = 0;

  static const _pages = <Widget>[
    HomeScreen(),
    JournalScreen(),
    ReflectionScreen(),
    ResourcesScreen(),
    ProfileScreen(),
  ];

  void _onItemTapped(int index) => setState(() => _selectedIndex = index);

  bool _shouldShowAds(int i) => i == 0 || i == 1 || i == 3 || i == 4;

  Color _barColor(BuildContext ctx) =>
      Theme.of(ctx).brightness == Brightness.dark
          ? Colors.black54
          : Colors.white70;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          MountainBackground(pageIndex: _selectedIndex),
          // ► cross‑fade entre páginas (elimina destello)
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, anim) =>
                  FadeTransition(opacity: anim, child: child),
              child: KeyedSubtree(
                key: ValueKey<int>(_selectedIndex),
                child: _pages[_selectedIndex],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_shouldShowAds(_selectedIndex))
            const AdBanner(adUnitId: _bannerId),
          BottomNavigationBar(
            type: BottomNavigationBarType.fixed,
            backgroundColor: _barColor(context),
            elevation: 0,
            currentIndex: _selectedIndex,
            selectedItemColor: Theme.of(context).colorScheme.primary,
            unselectedItemColor: Colors.grey,
            onTap: _onItemTapped,
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Inicio'),
              BottomNavigationBarItem(icon: Icon(Icons.edit), label: 'Diario'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.auto_stories), label: 'Reflexión'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.lightbulb_outline), label: 'Recursos'),
              BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Perfil'),
            ],
          ),
        ],
      ),
    );
  }
}
