import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../fine_tune/fine_tune_screen.dart';
import '../advanced/advanced_screen.dart';
import '../community/community_screen.dart';
import '../library/library_screen.dart';
import '../health/speaker_health_screen.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_screen.dart';
import '../../shared/widgets.dart';

/// MORE 탭 — FINE TUNE / ADVANCED / COMMUNITY / LIBRARY / PROFILE 진입점 메뉴.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            const TunaiTopBar(subtitle: 'MORE'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                children: [
                  _MenuItem(label: 'FINE TUNE', description: '취향에 맞게 미세 조정',
                      icon: Icons.tune,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FineTuneScreen()))),
                  _MenuItem(label: 'LIBRARY', description: 'Factory / My Presets / Community Best',
                      icon: Icons.library_music_outlined,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LibraryScreen()))),
                  _MenuItem(label: 'ADVANCED', description: 'PEQ · 크로스오버 · 보드 선택 · Driver',
                      icon: Icons.settings_input_component_outlined,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdvancedScreen()))),
                  _MenuItem(label: 'COMMUNITY', description: '프리셋 공유 · 다운로드',
                      icon: Icons.people_outline,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CommunityScreen()))),
                  _MenuItem(label: 'SPEAKER HEALTH', description: 'DSP Load · Amplifier · Limiter 상태',
                      icon: Icons.health_and_safety_outlined,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SpeakerHealthScreen()))),
                  const Divider(color: Colors.white12, height: 32),
                  _MenuItem(
                    label: auth.isLoggedIn ? (auth.nickname ?? 'MY PROFILE') : 'LOGIN',
                    description: auth.isLoggedIn ? '로그아웃' : '로그인 / 회원가입',
                    icon: Icons.person_outline,
                    onTap: () {
                      if (auth.isLoggedIn) {
                        ref.read(authProvider.notifier).logout();
                      } else {
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AuthScreen()));
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final String label;
  final String description;
  final IconData icon;
  final VoidCallback onTap;
  const _MenuItem({required this.label, required this.description, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(border: Border.all(color: Colors.white12), borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          Icon(icon, color: Colors.white38, size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 14, letterSpacing: 1)),
              const SizedBox(height: 2),
              Text(description, style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ]),
          ),
          const Icon(Icons.chevron_right, color: Colors.white24, size: 18),
        ]),
      ),
    );
  }
}
