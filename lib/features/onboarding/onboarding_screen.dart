import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 최초 1회 온보딩 완료 여부 키
const _kOnboardingComplete = 'first_run_complete';

Future<bool> isOnboardingComplete() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_kOnboardingComplete) ?? false;
}

Future<void> markOnboardingComplete() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kOnboardingComplete, true);
}

// ── 언어 헬퍼 ────────────────────────────────────────────────────────────────
bool _isKo(BuildContext context) {
  final lang = Localizations.localeOf(context).languageCode;
  return lang == 'ko';
}

class _OnboardingPage {
  final String titleEn;
  final String titleKo;
  final String subtitleEn;
  final String subtitleKo;
  final String btnEn;
  final String btnKo;

  const _OnboardingPage({
    required this.titleEn,
    required this.titleKo,
    required this.subtitleEn,
    required this.subtitleKo,
    required this.btnEn,
    required this.btnKo,
  });

  String title(BuildContext ctx) => _isKo(ctx) ? titleKo : titleEn;
  String subtitle(BuildContext ctx) => _isKo(ctx) ? subtitleKo : subtitleEn;
  String btn(BuildContext ctx) => _isKo(ctx) ? btnKo : btnEn;
}

const _pages = [
  _OnboardingPage(
    titleEn: 'The audio paradigm is changing.',
    titleKo: '오디오의 패러다임이 바뀝니다.',
    subtitleEn: 'Your speaker already has its sound.\n\nTUNAI preserves that factory-tuned character\nand helps it arrive correctly at your listening position.',
    subtitleKo: '스피커의 사운드는 공장에서 이미 완성됩니다.\n\nTUNAI는 그 기본 성향을 유지하면서\n청취 위치에 맞게 소리가 도달하도록 돕습니다.',
    btnEn: 'Continue',
    btnKo: '계속',
  ),
  _OnboardingPage(
    titleEn: 'Space changes.\nPlacement changes.\nTaste changes.',
    titleKo: '공간도, 위치도, 취향도 달라집니다.',
    subtitleEn: 'TUNAI reads the environment around the speaker\nand the place where you listen.\n\nRoom Scan understands your listening environment.',
    subtitleKo: 'TUNAI는 스피커가 놓인 환경과\n당신이 듣는 자리를 읽습니다.\n\nRoom Scan으로 청취 환경을 이해합니다.',
    btnEn: 'Continue',
    btnKo: '계속',
  ),
  _OnboardingPage(
    titleEn: 'The controls disappear.\nThe sound remains.',
    titleKo: '설정은 사라지고,\n좋은 소리만 남습니다.',
    subtitleEn: 'Acoustic Tune creates\nyour Sound Profile.\n\nNow the speaker evolves\nwith the listener.',
    subtitleKo: 'Acoustic Tune이\n당신만의 Sound Profile을 만듭니다.\n\n이제 스피커는\n듣는 사람과 함께 진화합니다.',
    btnEn: 'Get Started',
    btnKo: '시작하기',
  ),
];

class OnboardingScreen extends StatefulWidget {
  /// 온보딩 완료 후 호출 — 메인 루트로 전환
  final VoidCallback onComplete;
  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_page < _pages.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    } else {
      await markOnboardingComplete();
      widget.onComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            // ── 상단 TUNAI 로고 ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 40, 32, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'TUNAI',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 16,
                    fontWeight: FontWeight.w200,
                    letterSpacing: 10,
                  ),
                ),
              ),
            ),

            // ── PageView ─────────────────────────────────────────────
            Expanded(
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                itemCount: _pages.length,
                itemBuilder: (ctx, i) => _PageContent(page: _pages[i]),
              ),
            ),

            // ── 닷 인디케이터 ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pages.length, (i) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _page ? 20 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ),

            // ── CTA 버튼 ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
              child: _OnboardingButton(
                label: _pages[_page].btn(context),
                onTap: _next,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageContent extends StatelessWidget {
  final _OnboardingPage page;
  const _PageContent({required this.page});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(flex: 2),

          // 타이틀
          Text(
            page.title(context),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w300,
              height: 1.4,
              letterSpacing: -0.2,
            ),
          ),

          const SizedBox(height: 32),

          // 서브타이틀
          Text(
            page.subtitle(context),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 15,
              height: 1.7,
              letterSpacing: 0.1,
            ),
          ),

          const Spacer(flex: 3),
        ],
      ),
    );
  }
}

class _OnboardingButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _OnboardingButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }
}
