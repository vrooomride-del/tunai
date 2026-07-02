import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_service.dart';
import '../../core/audio_analyzer.dart';
import '../../core/enclosure_hash.dart';
import '../../core/my_tune_storage.dart';
import '../../core/speaker_profile.dart';
import '../ble/ble_controller.dart';
import '../dsp/dsp_compiler.dart';
import '../community/community_screen.dart';
import '../fine_tune/fine_tune_screen.dart';
import '../fine_tune/taste_preset.dart';
import '../../core/ai_tuning_service.dart';
import '../../shared/widgets.dart';

/// LIBRARY 탭 — Factory Presets / My Presets / Community Best.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});
  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  List<dynamic> _communityBest = [];
  bool _loadingCommunity = true;
  bool _matchMySpeaker = false;

  @override
  void initState() {
    super.initState();
    _loadCommunity();
  }

  String? _myHash() {
    final profile = ref.read(speakerProfileProvider);
    if (profile == null) return null;
    return EnclosureHash.fromProfile(
      volumeL: profile.enclosureVolume,
      portLengthMm: profile.portLength,
      portDiamMm: profile.portDiameter,
    );
  }

  Future<void> _loadCommunity() async {
    setState(() => _loadingCommunity = true);
    final res = _matchMySpeaker
        ? await ApiService.getPresets(hash: _myHash())
        : await ApiService.getTrending();
    if (!mounted) return;
    setState(() {
      _communityBest = (res['status'] == 'ok') ? (res['data'] ?? []).take(3).toList() : [];
      _loadingCommunity = false;
    });
  }

  Future<void> _downloadAndApply(Map<String, dynamic> preset) async {
    final fps = preset['fps_json'] as List?;
    if (fps == null || fps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('필터 데이터가 없는 프리셋입니다.')));
      return;
    }
    final peaks = fps.map((f) => ResonancePeak(
      frequency: (f['frequency'] ?? f['f'] ?? 1000).toDouble(),
      gain: (f['gain'] ?? f['g'] ?? -6).toDouble(),
      q: (f['q'] ?? 2.0).toDouble(),
    )).toList();
    final isConnected = ref.read(bleProvider).connection == BleConnectionState.connected;
    if (!isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${preset['title']} — CONNECT 탭에서 연결 후 다시 시도하세요')));
      return;
    }
    final packets = DspCompiler.compileAll(peaks);
    final ok = await ref.read(bleProvider.notifier).sendPackets(packets);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? '✓ ${preset['title']} 적용 완료' : '전송 실패 — BLE 연결 확인')));
  }

  Future<void> _applyMyTune() async {
    final peaks = await MyTuneStorage.load();
    if (peaks == null) return;
    final isConnected = ref.read(bleProvider).connection == BleConnectionState.connected;
    if (!isConnected) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('CONNECT 탭에서 연결 후 다시 시도하세요')));
      return;
    }
    final packets = DspCompiler.compileAll(peaks);
    final ok = await ref.read(bleProvider.notifier).sendPackets(packets);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? '✓ My Tune 적용 완료' : '전송 실패 — BLE 연결 확인')));
  }

  @override
  Widget build(BuildContext context) {
    final aiResult = ref.watch(lastAiResultProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            const TunaiTopBar(subtitle: 'LIBRARY'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                children: [
                  const _SectionTitle('📚 Factory Presets'),
                  const SizedBox(height: 8),
                  ...kTastePresets.map((p) => _LibraryRow(
                        title: p.label,
                        subtitle: p.description,
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FineTuneScreen())),
                      )),
                  const SizedBox(height: 20),
                  const _SectionTitle('My Presets'),
                  const SizedBox(height: 8),
                  if (aiResult != null)
                    _LibraryRow(title: 'AI Tune', subtitle: '가장 최근 AI 튜닝 결과 · ${aiResult.bands.length}개 밴드',
                        icon: Icons.auto_awesome_outlined, onTap: null),
                  FutureBuilder<DateTime?>(
                    future: MyTuneStorage.loadSavedAt(),
                    builder: (context, snap) {
                      if (!snap.hasData || snap.data == null) {
                        if (aiResult == null) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text('저장된 프리셋이 없습니다 — 상단 프리셋 바의 저장 버튼을 사용하세요',
                                style: TextStyle(color: Colors.white24, fontSize: 11)),
                          );
                        }
                        return const SizedBox.shrink();
                      }
                      final savedAt = snap.data!;
                      final label = '${savedAt.year}-${savedAt.month.toString().padLeft(2, '0')}-${savedAt.day.toString().padLeft(2, '0')}';
                      return _LibraryRow(title: 'My Tune', subtitle: '저장한 날짜: $label',
                          icon: Icons.bookmark_outline, onTap: _applyMyTune);
                    },
                  ),
                  const SizedBox(height: 20),
                  Row(children: [
                    const Expanded(child: _SectionTitle('Community Best')),
                    GestureDetector(
                      onTap: () {
                        setState(() => _matchMySpeaker = !_matchMySpeaker);
                        _loadCommunity();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          border: Border.all(color: _matchMySpeaker ? Colors.white : Colors.white12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text('내 스피커와 동일 규격',
                            style: TextStyle(color: _matchMySpeaker ? Colors.white : Colors.white38, fontSize: 10)),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  if (_loadingCommunity)
                    const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Center(child: CircularProgressIndicator(strokeWidth: 1, color: Colors.white38)))
                  else if (_communityBest.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('표시할 프리셋이 없습니다', style: TextStyle(color: Colors.white24, fontSize: 11)),
                    )
                  else
                    ..._communityBest.map((preset) => _CommunityRow(
                          preset: preset,
                          onDownload: () => _downloadAndApply(Map<String, dynamic>.from(preset)),
                        )),
                  const SizedBox(height: 8),
                  Center(
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CommunityScreen())),
                      child: const Text('COMMUNITY 전체 보기 →', style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 2));
}

class _LibraryRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  const _LibraryRow({required this.title, required this.subtitle, this.icon = Icons.music_note_outlined, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(border: Border.all(color: Colors.white12), borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          Icon(icon, color: Colors.white38, size: 16),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 13, letterSpacing: 1)),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ]),
          ),
          if (onTap != null) const Icon(Icons.play_circle_outline, color: Colors.white24, size: 18),
        ]),
      ),
    );
  }
}

class _CommunityRow extends StatelessWidget {
  final Map<String, dynamic> preset;
  final VoidCallback onDownload;
  const _CommunityRow({required this.preset, required this.onDownload});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(border: Border.all(color: Colors.white12), borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${preset['title'] ?? '제목 없음'}', style: const TextStyle(color: Colors.white, fontSize: 13, letterSpacing: 1)),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.star, color: Colors.amber, size: 12),
              const SizedBox(width: 2),
              Text('${preset['likes'] ?? 0}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
              const SizedBox(width: 10),
              const Icon(Icons.download, color: Colors.white24, size: 12),
              const SizedBox(width: 2),
              Text('${preset['downloads'] ?? 0}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ]),
          ]),
        ),
        GestureDetector(
          onTap: onDownload,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(border: Border.all(color: Colors.white24), borderRadius: BorderRadius.circular(4)),
            child: const Text('APPLY', style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1)),
          ),
        ),
      ]),
    );
  }
}
