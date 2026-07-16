import 'package:flutter/material.dart';

class AboutTunaiScreen extends StatelessWidget {
  const AboutTunaiScreen({super.key});

  bool _isKo(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'ko';

  @override
  Widget build(BuildContext context) {
    final ko = _isKo(context);

    final slides = [
      (
        ko ? 'TUNAI ONE의 소리는\n공장에서 완성됩니다.' : 'TUNAI ONE begins with\na factory-tuned sound.',
        ko
            ? '그 기본 성향은 변경의 대상이 아니라 기준입니다.\n\n달라지는 것은 공간의 울림과 배치,\n그리고 청취 위치입니다.'
            : 'That original character is the foundation, not something to redesign.\n\nWhat changes is the room, placement,\nand listening position.',
      ),
      (
        ko ? '완성된 기본 사운드에서 시작합니다.' : 'It starts with the factory-tuned sound.',
        ko
            ? 'Room Scan은 공간의 울림과 스피커 배치,\n평소 듣는 위치를 확인합니다.\n\nAcoustic Tune은 기본 성향을 유지하면서\n그 환경에 맞춘 Sound Profile을 만듭니다.'
            : 'Room Scan learns the room, speaker placement,\nand where you normally listen.\n\nAcoustic Tune preserves the original character\nwhile creating a profile for that environment.',
      ),
      (
        ko ? '좋은 소리를 찾는 일을\n더 이상 당신에게 떠넘기지 않습니다.' : 'Finding good sound should no longer\nbe left to you.',
        ko
            ? 'TUNAI ONE은 공장에서 완성된 기본 성향을 유지합니다.\n\nRoom Scan은 공간의 울림과 배치를 확인하고,\nAcoustic Tune은 청취 위치에 맞게 소리를 정리합니다.\n\n취향 조정은 그 위에 개인의 선호를 더합니다.'
            : 'TUNAI ONE preserves its factory-tuned character.\n\nRoom Scan learns the room and placement.\nAcoustic Tune adapts that sound to your listening position.\n\nPreference Adjustment adds your taste on top.',
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
                    final (title, body) = e.value;
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
                                    height: 1.4,
                                    letterSpacing: -0.2,
                                  )),
                              const SizedBox(height: 14),
                              Text(body,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.45),
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
