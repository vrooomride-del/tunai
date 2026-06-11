import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'features/home/home_screen.dart';
import 'features/community/community_screen.dart';
import 'features/history/history_screen.dart';
import 'features/enclosure/enclosure_screen.dart';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  WidgetsFlutterBinding.ensureInitialized();
  await SharedPreferences.getInstance();
  FlutterNativeSplash.remove();
  runApp(const ProviderScope(child: TunaiApp()));
}

class TunaiApp extends StatelessWidget {
  const TunaiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TUNAI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          surface: Color(0xFF111111),
        ),
        useMaterial3: true,
      ),
      home: const RootScreen(),
    );
  }
}

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  int _currentIndex = 0;

  final _screens = const [
    HomeScreen(),
    CommunityScreen(),
    HistoryScreen(),
    EnclosureScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: _screens[_currentIndex],
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Colors.white12, width: 0.5)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (i) => setState(() => _currentIndex = i),
          backgroundColor: const Color(0xFF0A0A0A),
          selectedItemColor: Colors.white,
          unselectedItemColor: Colors.white24,
          selectedLabelStyle: const TextStyle(fontSize: 10, letterSpacing: 1),
          unselectedLabelStyle: const TextStyle(fontSize: 10, letterSpacing: 1),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.speaker, size: 20),
              label: 'TUNE',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.people_outline, size: 20),
              label: 'COMMUNITY',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.history, size: 20),
              label: 'HISTORY',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.speaker, size: 20),
              label: 'ENCLOSURE',
            ),
          ],
        ),
      ),
    );
  }
}
