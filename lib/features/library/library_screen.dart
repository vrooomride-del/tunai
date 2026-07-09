import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/audio_analyzer.dart';
import '../../core/consumer_sound_profile.dart';
import '../../core/sound_profile_store.dart';
import '../ble/ble_controller.dart';
import '../dsp/dsp_compiler.dart';
import '../../shared/widgets.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  /// ROOM 탭(index 1)으로 이동하는 콜백 (optional — Library를 독립 push로 열 수도 있음)
  final VoidCallback? onGoToRoomScan;
  const LibraryScreen({super.key, this.onGoToRoomScan});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  bool _isKo(BuildContext ctx) =>
      Localizations.localeOf(ctx).languageCode == 'ko';

  Future<void> _applyProfile(UiSoundProfile profile) async {
    final ko = _isKo(context);
    final isConnected = ref.read(bleProvider).connection == BleConnectionState.connected;
    if (!isConnected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ko ? 'CONNECT 탭에서 스피커를 먼저 연결해주세요.' : 'Connect your speaker first (CONNECT tab).'),
          backgroundColor: const Color(0xFF1A1A1A),
        ));
      }
      return;
    }
    if (profile.bands.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ko ? '이 프로파일에는 음향 데이터가 없습니다.' : 'No acoustic data in this profile.'),
          backgroundColor: const Color(0xFF1A1A1A),
        ));
      }
      return;
    }
    final peaks = profile.bands
        .where((b) => b['enabled'] != false)
        .map((b) => ResonancePeak(
              frequency: (b['frequency'] as num).toDouble(),
              gain: (b['gainDb'] as num).toDouble(),
              q: (b['q'] as num).toDouble(),
            ))
        .toList();
    final packets = DspCompiler.compileAll(peaks);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ref.read(bleProvider.notifier).sendPackets(packets);
    if (!mounted) return;
    if (ok) {
      await ref.read(soundProfileStoreProvider.notifier).markApplied(profile.id);
      messenger.showSnackBar(SnackBar(
        content: Text(ko ? '사운드 프로파일이 안전하게 적용되었습니다.' : 'Sound Profile applied safely.'),
        backgroundColor: const Color(0xFF1A1A1A),
      ));
    } else {
      messenger.showSnackBar(SnackBar(
        content: Text(ko ? '전송 실패 — BLE 연결 상태를 확인하세요.' : 'Send failed — check BLE connection.'),
        backgroundColor: const Color(0xFF1A1A1A),
      ));
    }
  }

  Future<void> _renameProfile(UiSoundProfile profile) async {
    final ko = _isKo(context);
    final ctrl = TextEditingController(text: profile.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(ko ? '이름 변경' : 'Rename', style: const TextStyle(color: Colors.white, fontSize: 15)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: const InputDecoration(
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white70)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ko ? '취소' : 'Cancel', style: const TextStyle(color: Colors.white38))),
          TextButton(
            onPressed: () { final n = ctrl.text.trim(); if (n.isNotEmpty) Navigator.pop(ctx, n); },
            child: Text(ko ? '저장' : 'Save', style: const TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
    if (name != null) {
      await ref.read(soundProfileStoreProvider.notifier).rename(profile.id, name);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ko ? '프로파일 이름이 변경되었습니다.' : 'Profile renamed.'),
          backgroundColor: const Color(0xFF1A1A1A),
        ));
      }
    }
  }

  Future<void> _deleteProfile(UiSoundProfile profile) async {
    final ko = _isKo(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(ko ? '이 사운드 프로파일을 삭제할까요?' : 'Delete this Sound Profile?',
            style: const TextStyle(color: Colors.white, fontSize: 15)),
        content: Text(ko ? '이 작업은 되돌릴 수 없습니다.' : 'This cannot be undone.',
            style: const TextStyle(color: Colors.white54, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ko ? '취소' : 'Cancel', style: const TextStyle(color: Colors.white38))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(soundProfileStoreProvider.notifier).delete(profile.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ko ? '프로파일이 삭제되었습니다.' : 'Profile deleted.'),
          backgroundColor: const Color(0xFF1A1A1A),
        ));
      }
    }
  }

  void _showActions(UiSoundProfile profile) {
    final ko = _isKo(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(width: 36, height: 3, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          _ActionTile(
            icon: Icons.play_circle_outline,
            label: ko ? '적용' : 'Apply',
            onTap: () { Navigator.pop(ctx); _applyProfile(profile); },
          ),
          _ActionTile(
            icon: Icons.drive_file_rename_outline,
            label: ko ? '이름 변경' : 'Rename',
            onTap: () { Navigator.pop(ctx); _renameProfile(profile); },
          ),
          _ActionTile(
            icon: Icons.delete_outline,
            label: ko ? '삭제' : 'Delete',
            color: Colors.redAccent,
            onTap: () { Navigator.pop(ctx); _deleteProfile(profile); },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ko = _isKo(context);
    final profiles = ref.watch(soundProfileStoreProvider);
    final consumerProfiles = ref.watch(consumerSoundProfileProvider);

    final hasAny = profiles.isNotEmpty || consumerProfiles.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            TunaiTopBar(subtitle: ko ? '프로파일 보관함' : 'PROFILE LIBRARY'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
                children: [
                  if (!hasAny) ...[
                    const SizedBox(height: 60),
                    _EmptyLibraryState(ko: ko, onGoToRoomScan: widget.onGoToRoomScan),
                  ] else ...[
                    // ── Consumer Sound Profiles (from Acoustic Tune flow) ──
                    if (consumerProfiles.isNotEmpty) ...[
                      Text(
                        ko ? 'Acoustic Tune 프로파일' : 'Acoustic Tune Profiles',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11, letterSpacing: 1.5),
                      ),
                      const SizedBox(height: 12),
                      ...consumerProfiles.map((p) => _ConsumerProfileCard(profile: p, ko: ko)),
                      if (profiles.isNotEmpty) const SizedBox(height: 20),
                    ],
                    // ── PRO Sound Profiles (from advanced tuning) ─────────
                    if (profiles.isNotEmpty) ...[
                      Text(
                        ko ? '고급 사운드 프로파일' : 'Advanced Sound Profiles',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11, letterSpacing: 1.5),
                      ),
                      const SizedBox(height: 12),
                      ...profiles.reversed.map((p) => _ProfileCard(
                            profile: p,
                            ko: ko,
                            onTap: () => _showActions(p),
                            onApply: () => _applyProfile(p),
                          )),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Consumer Profile Card ─────────────────────────────────────────────────────

class _ConsumerProfileCard extends StatelessWidget {
  final ConsumerSoundProfile profile;
  final bool ko;
  const _ConsumerProfileCard({required this.profile, required this.ko});

  String _statusLabel(bool ko) {
    switch (profile.status) {
      case ConsumerProfileStatus.active:
        return ko ? '사용 중' : 'Active';
      case ConsumerProfileStatus.ready:
        return ko ? '준비됨' : 'Ready';
      case ConsumerProfileStatus.draft:
        return ko ? '초안' : 'Draft';
    }
  }

  Color get _statusColor => profile.status == ConsumerProfileStatus.active
      ? const Color(0xFF69F0AE)
      : Colors.white38;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: profile.isActive ? Colors.white.withValues(alpha: 0.04) : const Color(0xFF111111),
        border: Border.all(color: profile.isActive ? Colors.white24 : Colors.white.withValues(alpha: 0.09)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                profile.name,
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w300),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _statusColor.withValues(alpha: 0.12),
                border: Border.all(color: _statusColor.withValues(alpha: 0.35)),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _statusLabel(ko),
                style: TextStyle(color: _statusColor, fontSize: 9, letterSpacing: 1),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _MetaChip(text: profile.roomType),
            const SizedBox(width: 8),
            _MetaChip(text: profile.confidence),
            const SizedBox(width: 8),
            _MetaChip(text: ko ? 'Acoustic Tune' : 'Acoustic Tune'),
          ]),
          if (profile.resultCards.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...profile.resultCards.take(2).map((card) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                Container(width: 5, height: 5,
                    decoration: const BoxDecoration(color: Color(0xFF69F0AE), shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(card.label(ko: ko),
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11)),
              ]),
            )),
            if (profile.resultCards.length > 2)
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 13),
                child: Text(
                  ko ? '+${profile.resultCards.length - 2}개 더' : '+${profile.resultCards.length - 2} more',
                  style: const TextStyle(color: Colors.white24, fontSize: 10),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ── Profile Card ─────────────────────────────────────────────────────────────

class _ProfileCard extends StatelessWidget {
  final UiSoundProfile profile;
  final bool ko;
  final VoidCallback onTap;
  final VoidCallback onApply;
  const _ProfileCard({required this.profile, required this.ko, required this.onTap, required this.onApply});

  String _createdLabel(bool ko) {
    final diff = DateTime.now().difference(profile.createdAt);
    if (diff.inDays == 0) return ko ? '오늘' : 'Today';
    if (diff.inDays == 1) return ko ? '어제' : 'Yesterday';
    if (diff.inDays < 7) return ko ? '${diff.inDays}일 전' : '${diff.inDays}d ago';
    return '${profile.createdAt.year}.${profile.createdAt.month.toString().padLeft(2,'0')}.${profile.createdAt.day.toString().padLeft(2,'0')}';
  }

  @override
  Widget build(BuildContext context) {
    final applied = profile.isApplied;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: applied ? Colors.white.withValues(alpha: 0.04) : const Color(0xFF111111),
          border: Border.all(color: applied ? Colors.white24 : Colors.white.withValues(alpha: 0.09)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 이름 + status pill
            Row(children: [
              Expanded(
                child: Text(
                  profile.name,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w300),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF69F0AE).withValues(alpha: applied ? 0.15 : 0.07),
                  border: Border.all(color: const Color(0xFF69F0AE).withValues(alpha: applied ? 0.4 : 0.2)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  applied
                      ? (ko ? '적용됨 · 안전 확인' : 'Active · Safe')
                      : (ko ? '안전 확인' : 'Safe'),
                  style: TextStyle(
                    color: const Color(0xFF69F0AE).withValues(alpha: applied ? 1.0 : 0.6),
                    fontSize: 9,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.more_horiz, color: Colors.white.withValues(alpha: 0.25), size: 18),
            ]),
            const SizedBox(height: 10),
            // 메타 정보
            Row(children: [
              _MetaChip(text: ko ? profile.roomTypeLabel : profile.roomTypeLabelEn),
              if (profile.soundScore != null) ...[
                const SizedBox(width: 8),
                _MetaChip(text: 'Score ${profile.soundScore}'),
              ],
              const SizedBox(width: 8),
              _MetaChip(text: _createdLabel(ko)),
            ]),
            if (!applied) ...[
              const SizedBox(height: 12),
              // Safety verification note
              Container(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF69F0AE).withValues(alpha: 0.04),
                  border: Border.all(color: const Color(0xFF69F0AE).withValues(alpha: 0.18)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.verified_outlined, color: Color(0xFF69F0AE), size: 13),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      ko
                          ? '이 프로파일은 TUNAI 스피커에서 안전하게 재생될 수 있도록 확인되었습니다.'
                          : 'This profile has been checked for safe playback on your TUNAI speaker.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 10, height: 1.4),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: onApply,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white24),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    ko ? '적용' : 'Apply',
                    style: const TextStyle(color: Colors.white60, fontSize: 12, letterSpacing: 1.2),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String text;
  const _MetaChip({required this.text});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white12),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(text, style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 10, letterSpacing: 0.5)),
      );
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  const _ActionTile({required this.icon, required this.label, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.white70;
    return ListTile(
      leading: Icon(icon, color: c, size: 20),
      title: Text(label, style: TextStyle(color: c, fontSize: 14)),
      onTap: onTap,
    );
  }
}

// ── Empty State ──────────────────────────────────────────────────────────────

class _EmptyLibraryState extends StatelessWidget {
  final bool ko;
  final VoidCallback? onGoToRoomScan;
  const _EmptyLibraryState({required this.ko, this.onGoToRoomScan});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            Icon(Icons.library_music_outlined, color: Colors.white.withValues(alpha: 0.15), size: 40),
            const SizedBox(height: 20),
            Text(
              ko ? '아직 저장된 사운드 프로파일이 없습니다.' : 'No Sound Profiles yet.',
              style: const TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w300),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              ko
                  ? '공간 스캔으로 첫 어쿠스틱 튠을 만들어보세요.'
                  : 'Create your first Acoustic Tune with a Room Scan.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13, height: 1.5),
              textAlign: TextAlign.center,
            ),
            if (onGoToRoomScan != null) ...[
              const SizedBox(height: 28),
              GestureDetector(
                onTap: () { Navigator.of(context).pop(); onGoToRoomScan!(); },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    ko ? '공간 스캔 시작' : 'Start Room Scan',
                    style: const TextStyle(color: Colors.black, fontSize: 13, fontWeight: FontWeight.w500, letterSpacing: 1.3),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
