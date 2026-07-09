import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../fine_tune/fine_tune_screen.dart';
import '../community/community_screen.dart';
import '../library/library_screen.dart';
import '../health/speaker_health_screen.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_screen.dart';
import 'factory_screen.dart';
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
                  _MenuItem(label: 'PROFILE LIBRARY', description: 'Sound profiles for your rooms',
                      icon: Icons.library_music_outlined,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LibraryScreen()))),
                  _MenuItem(label: 'FINE TUNE', description: 'Acoustic Tune 위에 취향을 더합니다.',
                      icon: Icons.tune,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FineTuneScreen()))),
                  _MenuItem(label: 'SYSTEM HEALTH', description: 'Speaker Protection · Volume Safety · Sound Profile',
                      icon: Icons.health_and_safety_outlined,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SpeakerHealthScreen()))),
                  _MenuItem(label: 'COMMUNITY', description: '프리셋 공유 · 다운로드',
                      icon: Icons.people_outline,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CommunityScreen()))),
                  _TunaiProMenuItem(),
                  _MenuItem(
                    label: 'ABOUT TUNAI',
                    description: 'Our approach to room-matched sound',
                    icon: Icons.info_outline,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutTunaiScreen())),
                  ),
                  const Divider(color: Colors.white12, height: 32),
                  _FactoryMenuItem(),
                  const SizedBox(height: 10),
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


/// TUNAI PRO — intentionally disabled "coming soon" menu item
class _TunaiProMenuItem extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ko = Localizations.localeOf(context).languageCode == 'ko';
    return GestureDetector(
      onTap: () => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text('TUNAI PRO',
              style: TextStyle(color: Colors.white, fontSize: 15, letterSpacing: 2)),
          content: Text(
            ko
                ? 'TUNAI PRO는 추후 제공될 예정입니다.'
                : 'TUNAI PRO will be available in a later release.',
            style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('확인', style: TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          const Icon(Icons.settings_input_component_outlined, color: Colors.white24, size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Text('TUNAI PRO',
                    style: TextStyle(color: Colors.white54, fontSize: 14, letterSpacing: 1)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white12),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    ko ? '준비 중' : 'coming soon',
                    style: const TextStyle(color: Colors.white24, fontSize: 9, letterSpacing: 0.5),
                  ),
                ),
              ]),
              const SizedBox(height: 2),
              Text(
                ko ? '고급 음향 튜닝' : 'Advanced acoustic tuning',
                style: const TextStyle(color: Colors.white24, fontSize: 11),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// FACTORY MODE 항목 — PIN 입력 후 FactoryScreen으로 이동
class _FactoryMenuItem extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showPinDialog(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
            border: Border.all(color: Colors.white12),
            borderRadius: BorderRadius.circular(8)),
        child: const Row(children: [
          Icon(Icons.settings_suggest_outlined, color: Colors.white24, size: 20),
          SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('FACTORY MODE',
                  style: TextStyle(color: Colors.white54, fontSize: 14, letterSpacing: 1)),
              SizedBox(height: 2),
              Text('고급 스피커 설정 (PIN 보호)',
                  style: TextStyle(color: Colors.white24, fontSize: 11)),
            ]),
          ),
          Icon(Icons.lock_outline, color: Colors.white24, size: 16),
        ]),
      ),
    );
  }

  Future<void> _showPinDialog(BuildContext context) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Factory 모드',
            style: TextStyle(color: Colors.white, fontSize: 15)),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'PIN 입력',
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white70)),
          ),
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소',
                  style: TextStyle(color: Colors.white38))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('확인',
                  style: TextStyle(color: Colors.white70))),
        ],
      ),
    );
    if (ok == true && controller.text == '1234') {
      if (!context.mounted) return;
      Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const FactoryScreen()));
    } else if (ok == true) {
      if (!context.mounted) return;
      // Show error in a new dialog scoped to Factory Mode — avoid bleeding into other screens
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text('Factory 모드', style: TextStyle(color: Colors.white, fontSize: 15)),
          content: const Text('PIN이 올바르지 않습니다.', style: TextStyle(color: Colors.white60, fontSize: 13)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('확인', style: TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      );
    }
  }
}
