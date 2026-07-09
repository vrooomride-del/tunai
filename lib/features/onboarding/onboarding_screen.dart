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
    titleEn: 'Your room changes everything.',
    titleKo: '공간이 소리를 바꿉니다.',
    subtitleEn: 'A speaker is not finished at the factory.\nIt becomes complete in the room where you listen.',
    subtitleKo: '스피커는 공장에서 끝나지 않습니다.\n당신이 듣는 방에서 다시 완성됩니다.',
    btnEn: 'Continue',
    btnKo: '계속',
  ),
  _OnboardingPage(
    titleEn: 'TUNAI learns your space.',
    titleKo: 'TUNAI가 공간을 이해합니다.',
    subtitleEn: 'Room Scan listens to how sound behaves around your speaker and your listening position.',
    subtitleKo: 'Room Scan은 스피커와 청취 위치 주변의\n소리 변화를 파악합니다.',
    btnEn: 'Continue',
    btnKo: '계속',
  ),
  _OnboardingPage(
    titleEn: 'Better sound,\nwithout the complexity.',
    titleKo: '복잡한 설정 없이,\n더 좋은 소리.',
    subtitleEn: 'Acoustic Tune creates a safe, room-matched Sound Profile so you can simply listen.',
    subtitleKo: 'Acoustic Tune은 공간에 맞는 안전한 사운드 프로파일을 만들고,\n사용자는 그저 음악을 들으면 됩니다.',
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
