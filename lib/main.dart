import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/connect/connect_screen.dart';
import 'features/measure/measure_screen.dart';
import 'features/ai/ai_screen.dart';
import 'features/listen/listen_screen.dart';
import 'features/more/more_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/splash/splash_screen.dart';
import 'core/dsp_safety_notice.dart';

void main() {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  debugPrint('[ SPLASH ] native splash preserved, calling runApp()');
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
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ko', 'KR'), Locale('en')],
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          surface: Color(0xFF111111),
        ),
        useMaterial3: true,
      ),
      home: const _LaunchGate(),
    );
  }
}

/// 앱 진입점 — cold start 시 한 번만 브랜드 Splash를 보여준 뒤
/// 기존 Onboarding/Root 흐름으로 넘어간다.
///
/// Navigator에 push하지 않고 내부 state로 화면을 교체하므로(기존
/// `_OnboardingGate` 패턴과 동일) 뒤로 가기로 Splash에 복귀할 수 없고,
/// 앱이 백그라운드에서 복귀해도 이 위젯 자체가 다시 생성되지 않는 한
/// Splash가 재실행되지 않는다.
class _LaunchGate extends StatefulWidget {
  const _LaunchGate();

  @override
  State<_LaunchGate> createState() => _LaunchGateState();
}

class _LaunchGateState extends State<_LaunchGate> {
  bool _splashDone = false;

  @override
  void initState() {
    super.initState();
    // Official flutter_native_splash pattern: remove the native splash only
    // once Flutter has actually painted its first frame (here, the first
    // frame of SplashScreen itself), not before runApp(). Removing it any
    // earlier risks the native splash being torn down before there is
    // anything for it to hand off to.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint(
          '[ SPLASH ] first Flutter frame drawn, removing native splash');
      FlutterNativeSplash.remove();
    });
    // Firebase init no longer blocks runApp()/the first frame — it proceeds
    // in the background while the Splash motion plays. Nothing in the
    // BLE/Onboarding/Room Scan/Tune/Apply/LISTEN flow depends on Firebase
    // being ready before the app UI mounts: AiTuningService (the other
    // Firebase user, called from AiTuneOrchestrator during Tune creation)
    // already falls back to the rule-based TunePlan on any failure,
    // including "not ready yet".
    unawaited(_initializeFirebase());
    // Deliberately NOT warmed up here. Both real playback sites (Speaker
    // Audio Check's confirmation tone and Room Scan's pink-noise measurement
    // signal) each explicitly AWAIT TunaiPlaybackAudioSession.ensureActive()
    // themselves immediately before playing, which is what actually
    // guarantees the session is configured+active — a fire-and-forget warm-up
    // call here would only race that (see tunai_playback_audio_session.dart's
    // history for why a fire-and-forget-only config used to silently lose
    // the race to whichever playback ran first). Beyond that, calling it here
    // would also consume the session's one-time first-activation settle
    // delay seconds before the user has even connected a speaker, defeating
    // its purpose for the confirmation tone that actually needs it.
  }

  Future<void> _initializeFirebase() async {
    try {
      await Firebase.initializeApp();
      debugPrint('[ SPLASH ] Firebase init done');
    } catch (error, stackTrace) {
      // Non-fatal: Firebase is not required for Splash, Onboarding, or the
      // core BLE/Tune flow to function.
      debugPrint('[ SPLASH ] Firebase init failed: $error\n$stackTrace');
    }
  }

  void _onSplashFinished() {
    if (!mounted || _splashDone) return;
    setState(() => _splashDone = true);
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('[ SPLASH ] LaunchGate build (splashDone=$_splashDone)');
    if (!_splashDone) {
      return SplashScreen(onFinished: _onSplashFinished);
    }
    return const _OnboardingGate();
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
    if (_done == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0A0A),
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(32, 60, 32, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TUNAI',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w200,
                        letterSpacing: 10)),
                SizedBox(height: 32),
                Text('Sound that understands\nyour room.',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w300,
                        height: 1.35)),
                SizedBox(height: 16),
                Text('당신의 공간을 이해하는 소리.',
                    style: TextStyle(color: Color(0x66FFFFFF), fontSize: 14)),
                SizedBox(height: 24),
                Text('Powered by TUNAI Acoustic Intelligence',
                    style: TextStyle(
                        color: Color(0x33FFFFFF),
                        fontSize: 11,
                        letterSpacing: 1)),
              ],
            ),
          ),
        ),
      );
    }
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
      ConnectScreen(onConnected: () => _goTo(1), onGoTo: _goTo),
      MeasureScreen(onMeasured: () => _goTo(2)),
      AiScreen(onApplied: () => _goTo(3), onGoTo: _goTo),
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
              label: 'ROOM',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.auto_awesome_outlined, size: 20),
              label: 'TUNE',
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
