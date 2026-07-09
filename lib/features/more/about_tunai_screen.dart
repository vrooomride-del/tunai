import 'package:flutter/material.dart';

/// Read-only replay of the TUNAI onboarding philosophy — accessible from MORE.
class AboutTunaiScreen extends StatelessWidget {
  const AboutTunaiScreen({super.key});

  bool _isKo(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'ko';

  @override
  Widget build(BuildContext context) {
    final ko = _isKo(context);
    final slides = [
      (
        ko ? '공간이 소리를 바꿉니다.' : 'Your room changes everything.',
        ko
            ? '스피커는 공장에서 끝나지 않습니다.\n당신이 듣는 방에서 다시 완성됩니다.'
            : 'A speaker is not finished at the factory.\nIt becomes complete in the room where you listen.',
      ),
      (
        ko ? 'TUNAI가 공간을 이해합니다.' : 'TUNAI learns your space.',
        ko
            ? 'Room Scan은 스피커와 청취 위치 주변의\n소리 변화를 파악합니다.'
            : 'Room Scan listens to how sound behaves\naround your speaker and your listening position.',
      ),
      (
        ko ? '복잡한 설정 없이, 더 좋은 소리.' : 'Better sound, without the complexity.',
        ko
            ? 'Acoustic Tune은 공간에 맞는 안전한\n사운드 프로파일을 만들고,\n사용자는 그저 음악을 들으면 됩니다.'
            : 'Acoustic Tune creates a safe, room-matched\nSound Profile so you can simply listen.',
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 8, 0),
            child: Row(children: [
              const Text('TUNAI',
                  style: TextStyle(color: Colors.white, fontSize: 13, letterSpacing: 5, fontWeight: FontWeight.w300)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white38, size: 20),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(32, 32, 32, 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ko ? 'TUNAI 소개' : 'About TUNAI',
                    style: const TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 3),
                  ),
                  const SizedBox(height: 32),
                  ...slides.asMap().entries.map((e) {
                    final i = e.key;
                    final (title, subtitle) = e.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 36),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(
                            '${i + 1}',
                            style: const TextStyle(color: Colors.white12, fontSize: 11, letterSpacing: 1),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w300,
                                    height: 1.35,
                                    letterSpacing: -0.2,
                                  )),
                              const SizedBox(height: 12),
                              Text(subtitle,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.45),
                                    fontSize: 14,
                                    height: 1.7,
                                  )),
                            ]),
                          ),
                        ]),
                        if (i < slides.length - 1) ...[
                          const SizedBox(height: 28),
                          Container(height: 0.5, color: Colors.white12),
                        ],
                      ]),
                    );
                  }),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
