import 'package:flutter/material.dart';
import 'factory_access.dart';

class AboutTunaiScreen extends StatelessWidget {
  const AboutTunaiScreen({super.key});

  bool _isKo(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'ko';

  @override
  Widget build(BuildContext context) {
    final ko = _isKo(context);

    final slides = [
      (
        ko ? '좋은 소리는 공간에서 완성됩니다.' : 'Great sound is completed by your space.',
        ko
            ? '같은 스피커도 놓인 공간과\n듣는 위치에 따라 다르게 들립니다.\n\nTUNAI는 당신이 실제로 듣는 자리에서\n더 좋은 소리를 시작합니다.'
            : 'The same speaker sounds different\nin every space and listening position.\n\nTUNAI begins where you actually listen.',
      ),
      (
        ko ? '당신의 공간을 위한 사운드.' : 'Sound made for your space.',
        ko
            ? '공간 분석은 스피커와 청취 위치를 이해하고,\n그 결과로 나만의 사운드를 완성합니다.\n\n복잡한 설정 없이\n당신의 음악에 더 가까워집니다.'
            : 'Space Analysis understands your speaker\nand listening position, then shapes Your Sound.\n\nNo complex setup—just sound that brings you\ncloser to your music.',
      ),
      (
        ko ? '설정보다, 듣는 즐거움에 집중하세요.' : 'Less setup. More listening.',
        ko
            ? '연결하고, 공간을 분석하고,\n나의 사운드를 들어보세요.\n\nTUNAI는 기술을 드러내기보다\n좋은 소리의 경험을 남깁니다.'
            : 'Connect, understand your space,\nand listen to Your Sound.\n\nTUNAI keeps the technology quiet\nso the music can come forward.',
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
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      letterSpacing: 5,
                      fontWeight: FontWeight.w300)),
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
                  GestureDetector(
                    key: const Key('factory_hidden_access'),
                    onLongPress: () => requestFactoryModeAccess(context),
                    child: Text(
                      ko ? 'TUNAI 소개' : 'About TUNAI',
                      style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                          letterSpacing: 3),
                    ),
                  ),
                  const SizedBox(height: 32),
                  ...slides.asMap().entries.map((e) {
                    final i = e.key;
                    final (title, body) = e.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 36),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${i + 1}',
                                    style: const TextStyle(
                                        color: Colors.white12,
                                        fontSize: 11,
                                        letterSpacing: 1),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(title,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 20,
                                                fontWeight: FontWeight.w300,
                                                height: 1.4,
                                                letterSpacing: -0.2,
                                              )),
                                          const SizedBox(height: 14),
                                          Text(body,
                                              style: TextStyle(
                                                color: Colors.white
                                                    .withValues(alpha: 0.45),
                                                fontSize: 14,
                                                height: 1.75,
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
