import 'package:flutter/material.dart';

import '../../shared/widgets.dart';
import '../device/consumer_device_screen.dart';
import '../library/library_screen.dart';
import 'about_tunai_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ko = Localizations.localeOf(context).languageCode == 'ko';
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(children: [
          const TunaiTopBar(subtitle: 'MORE'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
              children: [
                Text(
                  ko
                      ? '스피커와 나만의 사운드를 관리합니다.'
                      : 'Manage your speaker and personal sound.',
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 12, height: 1.5),
                ),
                const SizedBox(height: 20),
                _MenuItem(
                  label: ko ? '연결된 기기' : 'CONNECTED DEVICE',
                  description: ko
                      ? '스피커 연결 및 재연결 설정'
                      : 'Connection and reconnect settings',
                  icon: Icons.speaker_outlined,
                  onTap: () => _open(context, const ConsumerDeviceScreen()),
                ),
                _MenuItem(
                  label: ko ? '나의 사운드' : 'SOUND PROFILES',
                  description:
                      ko ? '공간별로 저장된 나의 사운드' : 'Your saved sound for each room',
                  icon: Icons.library_music_outlined,
                  onTap: () => _open(context, const LibraryScreen()),
                ),
                _MenuItem(
                  label: ko ? '도움말 및 지원' : 'HELP & SUPPORT',
                  description:
                      ko ? '사용 안내 및 고객 지원' : 'Guides and customer support',
                  icon: Icons.help_outline,
                  onTap: () => _open(
                      context,
                      ConsumerInfoScreen(
                        title: ko ? '도움말 및 지원' : 'Help & Support',
                        body: ko
                            ? '연결, 공간 분석, 나만의 사운드 만들기에 대한 도움을 확인하세요.'
                            : 'Find help with connection, Room Analysis, and creating your sound.',
                      )),
                ),
                _MenuItem(
                  label: ko ? 'TUNAI 소개' : 'ABOUT TUNAI',
                  description:
                      ko ? 'TUNAI와 공간 맞춤 사운드' : 'TUNAI and room-matched sound',
                  icon: Icons.info_outline,
                  onTap: () => _open(context, const AboutTunaiScreen()),
                ),
                _MenuItem(
                  label: ko ? '설정' : 'SETTINGS',
                  description: ko ? '앱 및 개인정보 설정' : 'App and privacy settings',
                  icon: Icons.settings_outlined,
                  onTap: () => _open(
                      context,
                      ConsumerInfoScreen(
                        title: ko ? '설정' : 'Settings',
                        body: ko
                            ? '추가 설정은 향후 업데이트에서 제공됩니다.'
                            : 'Additional settings will be available in a future update.',
                      )),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  void _open(BuildContext context, Widget screen) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => screen),
      );
}

class _MenuItem extends StatelessWidget {
  final String label;
  final String description;
  final IconData icon;
  final VoidCallback onTap;
  const _MenuItem(
      {required this.label,
      required this.description,
      required this.icon,
      required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            Icon(icon, color: Colors.white38, size: 20),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 14, letterSpacing: 1)),
                const SizedBox(height: 3),
                Text(description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 11, height: 1.4)),
              ],
            )),
            const Icon(Icons.chevron_right, color: Colors.white24, size: 18),
          ]),
        ),
      );
}

class ConsumerInfoScreen extends StatelessWidget {
  final String title;
  final String body;
  const ConsumerInfoScreen(
      {super.key, required this.title, required this.body});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        appBar: AppBar(
            backgroundColor: const Color(0xFF0A0A0A), title: Text(title)),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(body,
              style: const TextStyle(
                  color: Colors.white60, fontSize: 14, height: 1.6)),
        ),
      );
}
