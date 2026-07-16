import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../ble/ble_controller.dart';
import '../../core/room_scan_result.dart';
import '../../core/consumer_sound_profile.dart';
import '../../shared/acoustic_timeline.dart';

/// TUNE 탭 — Consumer Acoustic Tune 6-state flow.
/// No DSP, no EQ, no PEQ, no frequency data exposed.
class AiScreen extends ConsumerStatefulWidget {
  final VoidCallback onApplied;
  final void Function(int)? onGoTo;
  const AiScreen({super.key, required this.onApplied, this.onGoTo});

  @override
  ConsumerState<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends ConsumerState<AiScreen> {
  bool _creating = false;

  bool get _isKo => Localizations.localeOf(context).languageCode == 'ko';

  Future<void> _createTune(RoomScanResult scan) async {
    setState(() => _creating = true);
    await Future.delayed(const Duration(milliseconds: 2600));
    if (!mounted) return;
    final ko = _isKo;
    final roomLabel = ko ? roomTypeLabelKo(scan.roomType) : scan.roomType;
    final name = '$roomLabel Acoustic Tune';
    final profile = ConsumerSoundProfile(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      roomType: scan.roomType,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      micProfileName: scan.micProfileName,
      confidence: scan.confidence,
      isActive: false,
      status: ConsumerProfileStatus.ready,
      resultCards: scan.cards,
      soundScoreBefore: 82,
      soundScoreAfter: 94,
      profileType: ConsumerProfileType.tunaiTune,
    );
    await ref.read(consumerSoundProfileProvider.notifier).upsertAndActivate(profile);
    if (!mounted) return;
    setState(() => _creating = false);
    widget.onApplied();
  }

  Future<void> _applyProfile(ConsumerSoundProfile profile) async {
    await ref.read(consumerSoundProfileProvider.notifier).setActive(profile.id);
    widget.onApplied();
  }

  @override
  Widget build(BuildContext context) {
    final ko = _isKo;
    final ble = ref.watch(bleProvider);
    final scan = ref.watch(roomScanResultProvider);
    final profiles = ref.watch(consumerSoundProfileProvider);
    final active = ref.watch(activeConsumerProfileProvider);
    final isConnected = ble.connection == BleConnectionState.connected;

    // State F — active profile exists (shown regardless of BLE connection)
    if (active != null) {
      return _StateF(ko: ko, profile: active, onGoListen: widget.onApplied,
          onReset: () async {
            await ref.read(consumerSoundProfileProvider.notifier).deactivateAll();
          });
    }

    // State A — no BLE AND no scan data: show connection prompt.
    // If scan already exists (e.g. from simulation), skip past State A.
    if (!isConnected && scan == null) {
      return _StateA(ko: ko, onGoConnect: widget.onGoTo != null ? () => widget.onGoTo!(0) : null);
    }

    // State B — BLE connected but no scan yet
    if (scan == null) {
      return _StateB(ko: ko, onGoRoom: widget.onGoTo != null ? () => widget.onGoTo!(1) : null);
    }

    // State D — creating in progress
    if (_creating) {
      return _StateD(ko: ko);
    }

    // State E — ready profile exists (not yet active); visible even without BLE
    final ready = profiles.where((p) => p.status == ConsumerProfileStatus.ready).toList();
    if (ready.isNotEmpty) {
      return _StateE(
        ko: ko,
        profile: ready.first,
        scan: scan,
        isConnected: isConnected,
        onApply: () => _applyProfile(ready.first),
      );
    }

    // State C — scan done, no profile yet; visible even without BLE
    return _StateC(
      ko: ko,
      scan: scan,
      isConnected: isConnected,
      onCreate: () => _createTune(scan),
    );
  }
}

// ── State A — No device, no scan ─────────────────────────────────────────────

class _StateA extends StatelessWidget {
  final bool ko;
  final VoidCallback? onGoConnect;
  const _StateA({required this.ko, this.onGoConnect});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 60, 32, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(flex: 2),
              Text(
                ko ? '먼저 스피커를 연결해 주세요.' : 'Connect your speaker first.',
                style: const TextStyle(color: Colors.white, fontSize: 24,
                    fontWeight: FontWeight.w300, height: 1.4),
              ),
              const SizedBox(height: 16),
              Text(
                ko
                    ? 'TUNAI 스피커와 연결하면 공간을 학습하고\n나만의 사운드 프로파일을 만들 수 있습니다.'
                    : 'Connect your TUNAI speaker to let TUNAI\nlearn your room and create your Sound Profile.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 14, height: 1.65),
              ),
              const SizedBox(height: 36),
              if (onGoConnect != null)
                _TuneBigButton(label: ko ? '스피커 연결하기' : 'Connect Speaker', onTap: onGoConnect!),
              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }
}

// ── State B — No Room Scan ────────────────────────────────────────────────────

class _StateB extends StatelessWidget {
  final bool ko;
  final VoidCallback? onGoRoom;
  const _StateB({required this.ko, this.onGoRoom});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 60, 32, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(flex: 2),
              Text(
                ko ? '아직 공간 스캔이 없습니다.' : 'No Room Scan yet.',
                style: const TextStyle(color: Colors.white, fontSize: 24,
                    fontWeight: FontWeight.w300, height: 1.4),
              ),
              const SizedBox(height: 16),
              Text(
                ko
                    ? 'Room Scan을 먼저 완료하면\nAcoustic Tune을 만들 수 있습니다.'
                    : 'Run a Room Scan first to create\nyour Acoustic Tune.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 14, height: 1.65),
              ),
              const SizedBox(height: 36),
              if (onGoRoom != null)
                _TuneBigButton(label: ko ? 'Room Scan 시작' : 'Start Room Scan', onTap: onGoRoom!),
              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }
}

// ── State C — Room scan done, no profile ─────────────────────────────────────

class _StateC extends StatelessWidget {
  final bool ko;
  final RoomScanResult scan;
  final VoidCallback onCreate;
  final bool isConnected;
  const _StateC({required this.ko, required this.scan, required this.onCreate, this.isConnected = true});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ko ? 'Room Scan 완료' : 'Room Scan Complete',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 11, letterSpacing: 2),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      ko
                          ? '공간에 맞는\nAcoustic Tune을 만들 준비가 됐습니다.'
                          : 'Ready to create your\nAcoustic Tune for this room.',
                      style: const TextStyle(color: Colors.white, fontSize: 26,
                          fontWeight: FontWeight.w300, height: 1.35, letterSpacing: -0.2),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      ko
                          ? 'TUNAI가 공간 특성에 맞는 안전한 사운드 프로파일을 만듭니다.\n복잡한 설정 없이, 그저 좋은 소리를 들으면 됩니다.'
                          : 'TUNAI creates a safe, room-matched Sound Profile.\nNo complex settings — just better sound.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 14, height: 1.65),
                    ),
                    const SizedBox(height: 32),
                    _ScanSummaryCard(ko: ko, scan: scan),
                    if (!isConnected) ...[
                      const SizedBox(height: 16),
                      _ConnectionNotice(ko: ko),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
              child: _TuneBigButton(
                label: ko ? 'Acoustic Tune 만들기' : 'Create Acoustic Tune',
                onTap: onCreate,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanSummaryCard extends StatelessWidget {
  final bool ko;
  final RoomScanResult scan;
  const _ScanSummaryCard({required this.ko, required this.scan});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(ko ? '스캔 결과' : 'Scan Result',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.35),
                fontSize: 10, letterSpacing: 1.5)),
        const SizedBox(height: 10),
        Row(children: [
          _ScanChip(text: ko ? roomTypeLabelKo(scan.roomType) : scan.roomType),
          const SizedBox(width: 8),
          _ScanChip(text: ko ? '마이크: ${micProfileLabelKo(scan.micProfileName)}' : 'Mic: ${scan.micProfileName}'),
        ]),
      ]),
    );
  }
}

class _ScanChip extends StatelessWidget {
  final String text;
  const _ScanChip({required this.text});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(border: Border.all(color: Colors.white12), borderRadius: BorderRadius.circular(3)),
    child: Text(text, style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 10)),
  );
}

// ── State D — Creating ────────────────────────────────────────────────────────

class _StateD extends StatelessWidget {
  final bool ko;
  const _StateD({required this.ko});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 60, 32, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ko
                    ? '이 공간에 맞는 안전한\n사운드 프로파일을 만들고 있습니다.'
                    : 'Creating a safe Sound Profile\nfor this room.',
                style: const TextStyle(color: Colors.white, fontSize: 24,
                    fontWeight: FontWeight.w300, height: 1.4),
              ),
              const Spacer(),
              const LinearProgressIndicator(
                backgroundColor: Colors.white12,
                color: Colors.white38,
                minHeight: 1.5,
              ),
              const SizedBox(height: 24),
              Text(
                ko
                    ? '공간 특성을 분석하고 있습니다...'
                    : 'Analysing room characteristics...',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 12, letterSpacing: 0.5),
              ),
              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }
}

// ── State E — Profile ready ───────────────────────────────────────────────────

class _StateE extends StatelessWidget {
  final bool ko;
  final ConsumerSoundProfile profile;
  final RoomScanResult scan;
  final VoidCallback onApply;
  final bool isConnected;
  const _StateE({required this.ko, required this.profile, required this.scan,
      required this.onApply, this.isConnected = true});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(width: 8, height: 8,
                          decoration: const BoxDecoration(color: Color(0xFF69F0AE), shape: BoxShape.circle)),
                      const SizedBox(width: 10),
                      Text(ko ? '공간 맞춤' : 'Room Matched',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 11, letterSpacing: 1.5)),
                    ]),
                    const SizedBox(height: 20),
                    Text(
                      ko
                          ? '사운드 프로파일이 준비되었습니다.'
                          : 'Your Sound Profile is ready.',
                      style: const TextStyle(color: Colors.white, fontSize: 26,
                          fontWeight: FontWeight.w300, height: 1.35, letterSpacing: -0.2),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      ko
                          ? '이 공간에 맞게 안전하게 조정된 사운드 프로파일입니다.\n적용하면 바로 들을 수 있습니다.'
                          : 'A safe, room-matched Sound Profile has been created.\nApply it to start listening.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 14, height: 1.65),
                    ),
                    const SizedBox(height: 32),
                    if (profile.soundScoreBefore != null && profile.soundScoreAfter != null) ...[
                      _SoundScoreCard(
                        ko: ko,
                        before: profile.soundScoreBefore!,
                        after: profile.soundScoreAfter!,
                      ),
                      const SizedBox(height: 24),
                    ],
                    AcousticTimeline(
                      currentStep: AcousticTimelineStep.listen,
                      ko: ko,
                    ),
                    const SizedBox(height: 28),
                    Text(
                      ko ? 'TUNAI가 발견한 것' : 'What TUNAI found',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.35),
                          fontSize: 11, letterSpacing: 1.5),
                    ),
                    const SizedBox(height: 12),
                    ...profile.resultCards.map((card) => _ResultCard(card: card, ko: ko)),
                    if (!isConnected) ...[
                      const SizedBox(height: 16),
                      _ConnectionNotice(ko: ko),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
              child: _TuneBigButton(
                label: ko ? 'Sound Profile 적용' : 'Apply Sound Profile',
                onTap: onApply,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final RoomScanResultCard card;
  final bool ko;
  const _ResultCard({required this.card, required this.ko});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 6, height: 6,
              decoration: const BoxDecoration(color: Color(0xFF69F0AE), shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(card.label(ko: ko),
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w300)),
        ]),
        const SizedBox(height: 6),
        Text(card.description(ko: ko),
            style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12, height: 1.5)),
      ]),
    );
  }
}

// ── State F — Profile active ──────────────────────────────────────────────────

class _StateF extends StatelessWidget {
  final bool ko;
  final ConsumerSoundProfile profile;
  final VoidCallback onGoListen;
  final VoidCallback onReset;
  const _StateF({required this.ko, required this.profile, required this.onGoListen, required this.onReset});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(width: 8, height: 8,
                          decoration: const BoxDecoration(color: Color(0xFF69F0AE), shape: BoxShape.circle)),
                      const SizedBox(width: 10),
                      Text(ko ? '사운드 프로파일 활성화됨' : 'Sound Profile Active',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 11, letterSpacing: 1.5)),
                    ]),
                    const SizedBox(height: 20),
                    Text(
                      ko ? '들을 준비 완료.' : 'Ready to listen.',
                      style: const TextStyle(color: Colors.white, fontSize: 26,
                          fontWeight: FontWeight.w300, height: 1.35, letterSpacing: -0.2),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      ko
                          ? '${profile.name}이(가) 활성화되어 있습니다.\nLISTEN 탭에서 Before / After를 비교해보세요.'
                          : '${profile.name} is active.\nGo to LISTEN to compare before and after.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 14, height: 1.65),
                    ),
                    const SizedBox(height: 32),
                    if (profile.soundScoreBefore != null && profile.soundScoreAfter != null) ...[
                      _SoundScoreCard(
                        ko: ko,
                        before: profile.soundScoreBefore!,
                        after: profile.soundScoreAfter!,
                      ),
                      const SizedBox(height: 24),
                    ],
                    AcousticTimeline(
                      currentStep: AcousticTimelineStep.savedProfile,
                      ko: ko,
                    ),
                    const SizedBox(height: 28),
                    Text(
                      ko ? '적용된 조정' : 'Applied adjustments',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.35),
                          fontSize: 11, letterSpacing: 1.5),
                    ),
                    const SizedBox(height: 12),
                    ...profile.resultCards.map((card) => _ResultCard(card: card, ko: ko)),
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: () => _confirmReset(context),
                      child: Center(
                        child: Text(
                          ko ? '다시 만들기' : 'Create new profile',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.3),
                            fontSize: 12,
                            decoration: TextDecoration.underline,
                            decorationColor: Colors.white.withValues(alpha: 0.15),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
              child: _TuneBigButton(
                label: ko ? 'LISTEN으로 이동' : 'Go to LISTEN',
                onTap: onGoListen,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context) async {
    final ko = Localizations.localeOf(context).languageCode == 'ko';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(ko ? '프로파일 초기화' : 'Reset Profile',
            style: const TextStyle(color: Colors.white, fontSize: 15)),
        content: Text(
          ko ? '현재 사운드 프로파일을 비활성화하고 새로 만들겠습니까?' : 'Deactivate the current Sound Profile and create a new one?',
          style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text(ko ? '취소' : 'Cancel', style: const TextStyle(color: Colors.white38))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: Text(ko ? '확인' : 'Confirm', style: const TextStyle(color: Colors.white70))),
        ],
      ),
    );
    if (ok == true) onReset();
  }
}

// ── Connection notice (no hardware) ──────────────────────────────────────────

class _ConnectionNotice extends StatelessWidget {
  final bool ko;
  const _ConnectionNotice({required this.ko});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(children: [
        const Icon(Icons.bluetooth_disabled, color: Colors.white24, size: 14),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            ko
                ? 'Sound Profile이 준비되었습니다. 스피커를 연결하면 이 설정으로 들을 수 있습니다.'
                : 'Sound Profile is ready. Connect your speaker to listen with this profile.',
            style: const TextStyle(color: Colors.white38, fontSize: 11, height: 1.5),
          ),
        ),
      ]),
    );
  }
}

// ── Sound Score card ─────────────────────────────────────────────────────────

class _SoundScoreCard extends StatelessWidget {
  final bool ko;
  final int before;
  final int after;
  const _SoundScoreCard({required this.ko, required this.before, required this.after});

  @override
  Widget build(BuildContext context) {
    final improvement = after - before;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF69F0AE).withValues(alpha: 0.04),
        border: Border.all(color: const Color(0xFF69F0AE).withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          ko ? 'Sound Score' : 'Sound Score',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 10, letterSpacing: 1.5),
        ),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text('$before', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 22, fontWeight: FontWeight.w300)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Icon(Icons.arrow_forward, color: Colors.white.withValues(alpha: 0.25), size: 14),
          ),
          Text('$after', style: const TextStyle(color: Color(0xFF69F0AE), fontSize: 28, fontWeight: FontWeight.w300)),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF69F0AE).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '+$improvement',
              style: const TextStyle(color: Color(0xFF69F0AE), fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
        ]),
      ]),
    );
  }
}

// ── Common button ─────────────────────────────────────────────────────────────

class _TuneBigButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _TuneBigButton({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: enabled ? Colors.white : Colors.transparent,
          border: !enabled ? Border.all(color: Colors.white24) : null,
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: enabled ? Colors.black : Colors.white.withValues(alpha: 0.45),
            fontSize: 14,
            fontWeight: FontWeight.w500,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}
