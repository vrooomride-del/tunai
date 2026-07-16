import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/consumer_sound_profile.dart';
import '../../core/sound_profile_store.dart';
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

  void _showProRedirect(bool ko) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(
          ko ? 'TUNAI PRO에서 관리' : 'Manage in TUNAI PRO',
          style: const TextStyle(color: Colors.white, fontSize: 15),
        ),
        content: Text(
          ko
              ? '고급 프로파일은 TUNAI PRO에서 검토 후 적용할 수 있습니다.'
              : 'Advanced profiles can be reviewed and applied in TUNAI PRO.',
          style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ko ? '확인' : 'OK',
                style: const TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
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
            icon: Icons.open_in_new,
            label: ko ? 'TUNAI PRO에서 관리' : 'Manage in TUNAI PRO',
            onTap: () { Navigator.pop(ctx); _showProRedirect(ko); },
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

    // Group consumer profiles by taxonomy type
    final tunaiTunes = consumerProfiles
        .where((p) => p.profileType == ConsumerProfileType.tunaiTune)
        .toList();
    final myTunes = consumerProfiles
        .where((p) => p.profileType == ConsumerProfileType.myTune)
        .toList();
    final roomProfiles = consumerProfiles
        .where((p) => p.profileType == ConsumerProfileType.roomProfile)
        .toList();
    final references = consumerProfiles
        .where((p) => p.profileType == ConsumerProfileType.reference)
        .toList();
    final hasUserProfiles = consumerProfiles.isNotEmpty || profiles.isNotEmpty;

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
                  // Empty state — shown when no user profiles saved yet
                  if (!hasUserProfiles) ...[
                    const SizedBox(height: 60),
                    _EmptyLibraryState(ko: ko, onGoToRoomScan: widget.onGoToRoomScan),
                    const SizedBox(height: 40),
                  ],

                  // ── TUNAI Tune ─────────────────────────────────────────
                  if (tunaiTunes.isNotEmpty) ...[
                    _SectionHeader(ko ? 'TUNAI Tune' : 'TUNAI Tune'),
                    ...tunaiTunes.map((p) => _ConsumerProfileCard(profile: p, ko: ko)),
                    const SizedBox(height: 20),
                  ],

                  // ── My Tune ────────────────────────────────────────────
                  if (myTunes.isNotEmpty) ...[
                    _SectionHeader(ko ? 'My Tune' : 'My Tune'),
                    ...myTunes.map((p) => _ConsumerProfileCard(profile: p, ko: ko)),
                    const SizedBox(height: 20),
                  ],

                  // ── Room Profile ───────────────────────────────────────
                  if (roomProfiles.isNotEmpty) ...[
                    _SectionHeader(ko ? '공간 프로파일' : 'Room Profile'),
                    ...roomProfiles.map((p) => _ConsumerProfileCard(profile: p, ko: ko)),
                    const SizedBox(height: 20),
                  ],

                  // ── Reference ──────────────────────────────────────────
                  if (references.isNotEmpty) ...[
                    _SectionHeader(ko ? '레퍼런스' : 'Reference'),
                    ...references.map((p) => _ConsumerProfileCard(profile: p, ko: ko)),
                    const SizedBox(height: 20),
                  ],

                  // ── PRO Sound Profiles (from advanced tuning) ──────────
                  if (profiles.isNotEmpty) ...[
                    _SectionHeader(ko ? '고급 사운드 프로파일' : 'Advanced Sound Profiles'),
                    ...profiles.reversed.map((p) => _ProfileCard(
                          profile: p,
                          ko: ko,
                          onTap: () => _showActions(p),
                          onManageInPro: () => _showProRedirect(ko),
                        )),
                    const SizedBox(height: 20),
                  ],

                  // ── Factory Sound — always shown as baseline reference ──
                  _SectionHeader(ko ? 'Factory Sound' : 'Factory Sound'),
                  _FactoryPlaceholderCard(ko: ko),

                  // ── PRO Bridge info card ────────────────────────────────
                  const SizedBox(height: 28),
                  _ProBridgeCard(ko: ko),
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
            _MetaChip(text: ko ? profile.roomTypeLabel : profile.roomTypeLabelEn),
            const SizedBox(width: 8),
            _MetaChip(text: profile.confidence),
            const SizedBox(width: 8),
            _MetaChip(text: profile.profileType.label(ko)),
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
  final VoidCallback onManageInPro;
  const _ProfileCard({required this.profile, required this.ko, required this.onTap, required this.onManageInPro});

  String _createdLabel(bool ko) {
    final diff = DateTime.now().difference(profile.createdAt);
    if (diff.inDays == 0) return ko ? '오늘' : 'Today';
    if (diff.inDays == 1) return ko ? '어제' : 'Yesterday';
    if (diff.inDays < 7) {
      return ko ? '${diff.inDays}일 전' : '${diff.inDays}d ago';
    }
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
            const SizedBox(height: 12),
            GestureDetector(
              onTap: onManageInPro,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white24),
                  borderRadius: BorderRadius.circular(4),
                ),
                alignment: Alignment.center,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.open_in_new, color: Colors.white38, size: 12),
                  const SizedBox(width: 6),
                  Text(
                    ko ? 'TUNAI PRO에서 관리' : 'Manage in TUNAI PRO',
                    style: const TextStyle(color: Colors.white60, fontSize: 12, letterSpacing: 1.0),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Section Header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          title,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: 11,
            letterSpacing: 1.5,
          ),
        ),
      );
}

// ── Factory Placeholder Card ──────────────────────────────────────────────────

class _FactoryPlaceholderCard extends StatelessWidget {
  final bool ko;
  const _FactoryPlaceholderCard({required this.ko});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                ko ? '기본 소리' : 'Default Sound',
                style: const TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.w300),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Factory',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 9, letterSpacing: 1),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            ko
                ? 'TUNAI 기기의 기본 사운드 설정입니다.\nAcoustic Tune 이전의 기준이 됩니다.'
                : 'The original sound of your TUNAI device.\nThis is the baseline before any Acoustic Tune.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.28), fontSize: 11, height: 1.5),
          ),
        ],
      ),
    );
  }
}

// ── PRO Bridge Info Card ──────────────────────────────────────────────────────

class _ProBridgeCard extends StatelessWidget {
  final bool ko;
  const _ProBridgeCard({required this.ko});

  void _showDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'TUNAI PRO Bridge',
          style: TextStyle(color: Colors.white, fontSize: 15, letterSpacing: 1),
        ),
        content: Text(
          ko
              ? '이 기능은 준비 중입니다.\n현재 Mobile에서는 Sound Profile을 저장하고 비교할 수 있으며, 고급 검토와 배포는 향후 TUNAI PRO 연동으로 제공됩니다.'
              : 'This feature is coming soon.\nFor now, Mobile can save and compare Sound Profiles. Advanced review and deployment will be available later through TUNAI PRO.',
          style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              ko ? '확인' : 'OK',
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showDialog(context),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.swap_horiz_rounded, color: Colors.white24, size: 16),
              const SizedBox(width: 8),
              Text(
                ko ? 'TUNAI PRO와 함께 사용하기' : 'Use with TUNAI PRO',
                style: const TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w300),
              ),
            ]),
            const SizedBox(height: 10),
            Text(
              ko
                  ? 'Mobile에서 만든 Sound Profile은 나중에 TUNAI PRO에서 전문가 검토를 받을 수 있습니다.\n전문가가 다듬은 Reference Profile은 다시 Mobile에서 사용할 수 있습니다.'
                  : 'Sound Profiles created on Mobile can later be reviewed in TUNAI PRO.\nExpert-refined Reference Profiles can be used again on Mobile.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11, height: 1.55),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                ko ? 'PRO 연동 준비 중' : 'PRO Bridge Coming Soon',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11, letterSpacing: 0.5),
              ),
            ),
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
              ko ? '아직 저장된 Sound Profile이 없습니다.' : 'No Sound Profiles saved yet.',
              style: const TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w300),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              ko
                  ? 'Room Scan과 Acoustic Tune을 완료하면\n이곳에 저장됩니다.'
                  : 'Complete Room Scan and Acoustic Tune\nto save your first profile.',
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
