import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../fine_tune/fine_tune_screen.dart';
import '../library/library_screen.dart';
import '../health/speaker_health_screen.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_screen.dart';
import 'about_tunai_screen.dart';
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
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20, top: 4),
                    child: Builder(builder: (ctx) {
                      final ko = Localizations.localeOf(ctx).languageCode == 'ko';
                      return Text(
                        ko ? '프로파일, 시스템 상태, 설정을 관리합니다.' : 'Manage profiles, system health, and settings.',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 12, height: 1.5),
                      );
                    }),
                  ),
                  _MenuItem(
                    label: 'PROFILE LIBRARY', labelKo: '프로파일 보관함',
                    description: 'Sound profiles for your rooms', descriptionKo: '공간별 사운드 프로파일',
                    icon: Icons.library_music_outlined,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LibraryScreen())),
                  ),
                  _MenuItem(
                    label: 'FINE TUNE', labelKo: '취향 조정',
                    description: 'Add your personal touch to Acoustic Tune', descriptionKo: 'Acoustic Tune 위에 취향을 더합니다.',
                    icon: Icons.tune,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FineTuneScreen())),
                  ),
                  _MenuItem(
                    label: 'SYSTEM HEALTH', labelKo: '시스템 상태',
                    description: 'Speaker protection · Volume safety', descriptionKo: '스피커 보호 · 볼륨 안전',
                    icon: Icons.health_and_safety_outlined,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SpeakerHealthScreen())),
                  ),
                  _MenuItem(
                    label: 'ABOUT TUNAI', labelKo: 'TUNAI 소개',
                    description: 'Our approach to room-matched sound', descriptionKo: '공간 맞춤 소리에 대한 TUNAI의 철학',
                    icon: Icons.info_outline,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutTunaiScreen())),
                  ),
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
  final String? labelKo;
  final String description;
  final String? descriptionKo;
  final IconData icon;
  final VoidCallback onTap;
  const _MenuItem({required this.label, this.labelKo, required this.description, this.descriptionKo, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final ko = Localizations.localeOf(context).languageCode == 'ko';
    final displayLabel = ko && labelKo != null ? labelKo! : label;
    final displayDesc = ko && descriptionKo != null ? descriptionKo! : description;
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
              Text(displayLabel, style: const TextStyle(color: Colors.white, fontSize: 14, letterSpacing: 1)),
              const SizedBox(height: 2),
              Text(displayDesc, style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ]),
          ),
          const Icon(Icons.chevron_right, color: Colors.white24, size: 18),
        ]),
      ),
    );
  }
}
