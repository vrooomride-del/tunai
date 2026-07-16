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
        ko ? '오디오의 패러다임이 바뀝니다.' : 'The audio paradigm is changing.',
        ko
            ? '오랫동안 우리는\n스피커 안에 갇힌 소리를 들어왔습니다.\n\n공간이 바뀌어도,\n위치가 바뀌어도,\n취향이 달라져도,\n스피커는 처음의 소리에 머물렀습니다.'
            : 'For too long,\nwe listened to sound locked inside the speaker.\n\nEven as spaces changed,\nplacement changed,\nand taste changed,\nthe speaker stayed fixed to its first sound.',
      ),
      (
        ko ? 'TUNAI는 그 소리를 다시 엽니다.' : 'TUNAI opens that sound again.',
        ko
            ? '스피커가 놓인 환경,\n청취 위치,\n그리고 당신이 좋아하는 소리까지.\n\nRoom Scan과 Acoustic Tune은\n당신의 공간과 취향을 읽고\nSound Profile을 만듭니다.'
            : 'The environment around the speaker,\nthe place where you listen,\nand the sound you prefer.\n\nRoom Scan and Acoustic Tune read your space and taste\nto create your Sound Profile.',
      ),
      (
        ko ? '좋은 소리를 찾는 일을\n더 이상 당신에게 떠넘기지 않습니다.' : 'Finding good sound should no longer\nbe left to you.',
        ko
            ? '복잡한 조작도,\n끝없는 매칭도 필요 없습니다.\n\nTUNAI는 당신의 환경에 맞춰지고,\n당신의 취향으로 발전합니다.\n\n이제 스피커는\n듣는 사람과 함께 진화합니다.'
            : 'No complex controls.\nNo endless matching.\n\nTUNAI adapts to your environment\nand evolves with your taste.\n\nNow the speaker evolves\nwith the listener.',
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
