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

  bool _shouldShowAds(int index) => index == 0 || index == 3 || index == 4;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          MountainBackground(pageIndex: _selectedIndex),
          Positioned.fill(child: _pages[_selectedIndex]),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_shouldShowAds(_selectedIndex))
            const AdBanner(adUnitId: _bannerId),
          BottomNavigationBar(
            currentIndex: _selectedIndex,
            selectedItemColor: Theme.of(context).primaryColor,
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
