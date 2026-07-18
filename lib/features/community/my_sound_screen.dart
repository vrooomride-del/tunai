import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/consumer_sound_profile.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_screen.dart';

class MySoundScreen extends ConsumerWidget {
  const MySoundScreen({super.key});

  bool _isKo(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'ko';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ko = _isKo(context);
    final auth = ref.watch(authProvider);
    final profiles = ref.watch(consumerSoundProfileProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 8, 0),
            child: Row(children: [
              Text(
                ko ? '나의 사운드' : 'MY SOUND',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    letterSpacing: 5,
                    fontWeight: FontWeight.w300),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white38, size: 20),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ]),
          ),
          Expanded(
            child: auth.isLoggedIn
                ? _LoggedInView(ko: ko, profiles: profiles, auth: auth)
                : _GuestPrompt(ko: ko),
          ),
        ]),
      ),
    );
  }
}

class _LoggedInView extends StatelessWidget {
  final bool ko;
  final List<ConsumerSoundProfile> profiles;
  final AuthState auth;

  const _LoggedInView(
      {required this.ko, required this.profiles, required this.auth});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
      children: [
        Text(
          auth.nickname ?? auth.email ?? '',
          style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w300,
              letterSpacing: -0.2),
        ),
        const SizedBox(height: 4),
        Text(
          auth.email ?? '',
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
        const SizedBox(height: 32),
        Text(
          ko ? '저장된 사운드' : 'Saved Sounds',
          style: const TextStyle(
              color: Colors.white38, fontSize: 10, letterSpacing: 3),
        ),
        const SizedBox(height: 12),
        if (profiles.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Text(
              ko
                  ? '아직 저장된 사운드가 없습니다.\n공간을 측정하고 나만의 사운드를 만들어보세요.'
                  : 'No sounds saved yet.\nMeasure your space to create Your Sound.',
              style: const TextStyle(
                  color: Colors.white24, fontSize: 13, height: 1.7),
            ),
          )
        else
          ...profiles.map((p) => _SoundProfileTile(profile: p, ko: ko)),
      ],
    );
  }
}

class _SoundProfileTile extends StatelessWidget {
  final ConsumerSoundProfile profile;
  final bool ko;
  const _SoundProfileTile({required this.profile, required this.ko});

  @override
  Widget build(BuildContext context) {
    final label = ko ? profile.roomTypeLabel : profile.roomTypeLabelEn;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        const Icon(Icons.graphic_eq, color: Colors.white38, size: 18),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              profile.name,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ]),
        ),
        if (profile.isActive)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white24, width: 0.5),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              ko ? '현재 적용' : 'Active',
              style:
                  const TextStyle(color: Colors.white54, fontSize: 9, letterSpacing: 1),
            ),
          ),
      ]),
    );
  }
}

class _GuestPrompt extends StatelessWidget {
  final bool ko;
  const _GuestPrompt({required this.ko});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 48),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          ko ? '나만의 사운드를 저장하세요.' : 'Save Your Sound.',
          style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w300,
              height: 1.4),
        ),
        const SizedBox(height: 16),
        Text(
          ko
              ? '계정을 만들면 공간별 사운드를 저장하고\n언제든지 다시 적용할 수 있습니다.'
              : 'Create an account to save Your Sound\nfor each space and reapply anytime.',
          style: const TextStyle(
              color: Colors.white38, fontSize: 13, height: 1.7),
        ),
        const SizedBox(height: 48),
        GestureDetector(
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AuthScreen())),
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white54),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                ko ? '로그인 / 계정 만들기' : 'Sign In / Create Account',
                style: const TextStyle(
                    color: Colors.white, fontSize: 13, letterSpacing: 1),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Center(
            child: Text(
              ko ? '나중에 하기' : 'Maybe later',
              style: const TextStyle(
                  color: Colors.white24,
                  fontSize: 12,
                  decoration: TextDecoration.underline),
            ),
          ),
        ),
      ]),
    );
  }
}
