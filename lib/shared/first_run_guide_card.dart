import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/first_run_state.dart';

/// 퍼스트런 단계 안내 카드 — CONNECT 탭 상단에 자연스럽게 배치.
/// 팝업/모달 금지, premium dark card style.
class FirstRunGuideCard extends ConsumerWidget {
  /// 탭 인덱스로 이동: 0=CONNECT 1=ROOM 2=TUNE 3=LISTEN
  final void Function(int) onGoTo;
  const FirstRunGuideCard({super.key, required this.onGoTo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(firstRunStateProvider);
    final ko = Localizations.localeOf(context).languageCode == 'ko';
    final data = _cardData(state, ko);
    if (data == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(32, 0, 32, 24),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 단계 뱃지
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white24),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                _stepLabel(state, ko),
                style: const TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 1.5),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          // 타이틀
          Text(
            data.title,
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w300, height: 1.4),
          ),
          if (data.subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              data.subtitle!,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12, height: 1.55),
            ),
          ],
          const SizedBox(height: 16),
          // 버튼들
          ...data.buttons.map((btn) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _GuideButton(label: btn.label, primary: btn.primary, onTap: () => onGoTo(btn.tabIndex)),
          )),
        ],
      ),
    );
  }

  String _stepLabel(FirstRunState s, bool ko) {
    switch (s) {
      case FirstRunState.noDeviceConnected:         return ko ? '1단계 · 연결' : 'STEP 1 · CONNECT';
      case FirstRunState.deviceConnectedNoRoomScan: return ko ? '2단계 · 공간 스캔' : 'STEP 2 · ROOM SCAN';
      case FirstRunState.roomScanCompleteNoTune:    return ko ? '3단계 · 어쿠스틱 튠' : 'STEP 3 · ACOUSTIC TUNE';
      case FirstRunState.acousticTuneReadyNotApplied: return ko ? '4단계 · 적용' : 'STEP 4 · APPLY';
      case FirstRunState.acousticTuneApplied:       return ko ? '완료' : 'COMPLETE';
    }
  }

  _CardData? _cardData(FirstRunState state, bool ko) {
    switch (state) {
      case FirstRunState.noDeviceConnected:
        return _CardData(
          title: ko ? 'TUNAI 스피커를 연결해주세요.' : 'Connect your TUNAI speaker to begin.',
          buttons: [
            _BtnData(label: ko ? '스피커 연결' : 'Connect Speaker', tabIndex: 0, primary: true),
          ],
        );
      case FirstRunState.deviceConnectedNoRoomScan:
        return _CardData(
          title: ko ? 'TUNAI ONE이 연결되었습니다.' : 'TUNAI ONE is connected.',
          subtitle: ko
              ? '이제 당신의 공간에 맞는 사운드 프로파일을 만들어보세요.'
              : 'Now let\'s create a Sound Profile for your room.',
          buttons: [
            _BtnData(label: ko ? '공간 스캔 시작' : 'Start Room Scan', tabIndex: 1, primary: true),
          ],
        );
      case FirstRunState.roomScanCompleteNoTune:
        return _CardData(
          title: ko ? '공간 스캔이 완료되었습니다.' : 'Room Scan complete.',
          subtitle: ko
              ? '이제 어쿠스틱 튠을 생성할 수 있습니다.'
              : 'TUNAI can now create your Acoustic Tune.',
          buttons: [
            _BtnData(label: ko ? '어쿠스틱 튠 생성' : 'Create Acoustic Tune', tabIndex: 2, primary: true),
          ],
        );
      case FirstRunState.acousticTuneReadyNotApplied:
        return _CardData(
          title: ko ? '어쿠스틱 튠이 준비되었습니다.' : 'Your Acoustic Tune is ready.',
          subtitle: ko
              ? '적용하기 전에 차이를 들어보세요.'
              : 'Hear the difference before applying it.',
          buttons: [
            _BtnData(label: ko ? 'Before·After 듣기' : 'Hear Before / After', tabIndex: 3, primary: false),
            _BtnData(label: ko ? '사운드 프로파일 적용' : 'Apply Sound Profile', tabIndex: 2, primary: true),
          ],
        );
      case FirstRunState.acousticTuneApplied:
        return _CardData(
          title: ko ? '어쿠스틱 튠이 적용되었습니다.' : 'Acoustic Tune applied.',
          subtitle: ko
              ? '이제 스피커가 이 공간에 맞춰졌습니다.'
              : 'Your speaker is now matched to this room.',
          buttons: [
            _BtnData(label: ko ? '듣기 화면으로 이동' : 'Go to Listen', tabIndex: 3, primary: true),
          ],
        );
    }
  }
}

class _CardData {
  final String title;
  final String? subtitle;
  final List<_BtnData> buttons;
  const _CardData({required this.title, this.subtitle, required this.buttons});
}

class _BtnData {
  final String label;
  final int tabIndex;
  final bool primary;
  const _BtnData({required this.label, required this.tabIndex, required this.primary});
}

class _GuideButton extends StatelessWidget {
  final String label;
  final bool primary;
  final VoidCallback onTap;
  const _GuideButton({required this.label, required this.primary, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: primary ? Colors.white : Colors.transparent,
          border: Border.all(color: primary ? Colors.transparent : Colors.white38),
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: primary ? Colors.black : Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}
