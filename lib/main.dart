import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/connect/connect_screen.dart';
import 'features/measure/measure_screen.dart';
import 'features/ai/ai_screen.dart';
import 'features/listen/listen_screen.dart';
import 'features/more/more_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'core/dsp_safety_notice.dart';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  await Firebase.initializeApp();
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
      scaffoldMessengerKey: DspSafetyNotice.scaffoldMessengerKey,
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
  bool? _done;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final done = await isOnboardingComplete();
    setState(() => _done = done);
  }

  @override
  Widget build(BuildContext context) {
    if (_done == null) return const Scaffold(backgroundColor: Color(0xFF0A0A0A));
    if (!_done!) {
      return OnboardingScreen(onComplete: () => setState(() => _done = true));
    }
    return const RootScreen();
  }
}

/// 현재 활성 탭 인덱스 — 탭을 벗어났을 때 자동 정지해야 하는 화면(LISTEN Loop 등)이
/// 참고할 수 있도록 전역으로 노출. IndexedStack은 비활성 탭도 dispose하지 않으므로
/// 이 provider 없이는 "다른 화면으로 이동" 여부를 알 수 없다.
final currentTabIndexProvider = StateProvider<int>((ref) => 0);

class RootScreen extends ConsumerStatefulWidget {
  const RootScreen({super.key});

  @override
  ConsumerState<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends ConsumerState<RootScreen> {
  int _currentIndex = 0;

  void _goTo(int i) {
    setState(() => _currentIndex = i);
    ref.read(currentTabIndexProvider.notifier).state = i;
  }

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
