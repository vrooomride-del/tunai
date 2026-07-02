import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'features/connect/connect_screen.dart';
import 'features/measure/measure_screen.dart';
import 'features/ai/ai_screen.dart';
import 'features/listen/listen_screen.dart';
import 'features/more/more_screen.dart';
import 'features/device/device_screen.dart';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  await Firebase.initializeApp();
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
      home: const _OnboardingGate(),
    );
  }
}


class _OnboardingGate extends StatefulWidget {
  const _OnboardingGate();
  @override
  State<_OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<_OnboardingGate> {
  bool? _registered;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _registered = prefs.getString('registered_device') != null);
  }

  @override
  Widget build(BuildContext context) {
    if (_registered == null) return const Scaffold(backgroundColor: Color(0xFF0A0A0A));
    if (!_registered!) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: SafeArea(
          child: Column(children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 48, 24, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('TUNAI', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w200, letterSpacing: 8)),
                SizedBox(height: 8),
                Text('스피커를 등록하고 시작하세요', style: TextStyle(color: Colors.white38, fontSize: 13)),
              ]),
            ),
            Expanded(child: DeviceScreen(onRegistered: () => setState(() => _registered = true))),
          ]),
        ),
      );
    }
    return const RootScreen();
  }
}

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  int _currentIndex = 0;

  void _goTo(int i) => setState(() => _currentIndex = i);

  @override
  Widget build(BuildContext context) {
    final screens = [
      ConnectScreen(onConnected: () => _goTo(1)),
      MeasureScreen(onMeasured: () => _goTo(2)),
      AiScreen(onApplied: () => _goTo(3)),
      const ListenScreen(),
      const MoreScreen(),
    ];
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: IndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Colors.white12, width: 0.5)),
        ),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: _currentIndex,
          onTap: _goTo,
          backgroundColor: const Color(0xFF0A0A0A),
          selectedItemColor: Colors.white,
          unselectedItemColor: Colors.white24,
          selectedLabelStyle: const TextStyle(fontSize: 10, letterSpacing: 1),
          unselectedLabelStyle: const TextStyle(fontSize: 10, letterSpacing: 1),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.bluetooth, size: 20),
              label: 'CONNECT',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.mic_none, size: 20),
              label: 'MEASURE',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.auto_awesome_outlined, size: 20),
              label: 'AI',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.headphones, size: 20),
              label: 'LISTEN',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.more_horiz, size: 20),
              label: 'MORE',
            ),
          ],
        ),
      ),
    );
  }
}
