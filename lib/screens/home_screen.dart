import 'package:flutter/material.dart';

import 'package:oagents/screens/chat_screen.dart';
import 'package:oagents/screens/runtime_screen.dart';
import 'package:oagents/screens/sessions_screen.dart';

/// Home dengan NavigationBar 3 tab: Chat, Sesi, Runtime.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tabIndex = 0;

  static const List<Widget> _tabs = <Widget>[
    ChatScreen(),
    SessionsScreen(),
    RuntimeScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _tabIndex, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_open_outlined),
            selectedIcon: Icon(Icons.folder_open),
            label: 'Sesi',
          ),
          NavigationDestination(
            icon: Icon(Icons.memory_outlined),
            selectedIcon: Icon(Icons.memory),
            label: 'Runtime',
          ),
        ],
      ),
    );
  }
}
