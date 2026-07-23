import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/acoustic_intent.dart';
import '../../core/acoustic_intent_service.dart';
import '../../core/acoustic_profile.dart';
import '../../core/listening_taste.dart';

/// "나의 사운드 취향" — the user chooses the LISTENING EXPERIENCE they want,
/// never an EQ preset. No Hz/dB/Q/filter/PEQ/DSP anywhere: the options are
/// perceptual ("따뜻하고 편안한 소리"). Selection is saved immediately to the
/// local [AcousticProfileStore]; it never re-tunes anything on its own — a
/// notice tells the user it applies from the next Space Analysis / Tune.
///
/// An OPTIONAL natural-language box lets the user describe what they want; the
/// text goes to the `aiIntent` Cloud Function, which returns a PERCEPTUAL
/// [AcousticIntent] only (the client hard-rejects any DSP field). The result is
/// shown for the user to CONFIRM before it is saved — never saved silently.
class SoundTasteScreen extends ConsumerStatefulWidget {
  const SoundTasteScreen({super.key});

  @override
  ConsumerState<SoundTasteScreen> createState() => _SoundTasteScreenState();
}

class _SoundTasteScreenState extends ConsumerState<SoundTasteScreen> {
  AcousticProfile? _profile;
  bool _loading = true;
  final _requestController = TextEditingController();
  bool _interpreting = false;
  AcousticIntent? _pendingIntent; // awaiting user confirmation
  String? _intentError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _requestController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final stored = await AcousticProfileStore.load();
    if (!mounted) return;
    setState(() {
      _profile = stored ?? const AcousticProfile(roomType: '');
      _loading = false;
    });
  }

  Future<void> _selectTaste(ListeningTaste taste) async {
    final updated = (_profile ?? const AcousticProfile(roomType: ''))
        .copyWith(listeningTaste: taste);
    setState(() => _profile = updated);
    // Immediate save — but never auto-applies a tune.
    await AcousticProfileStore.save(updated);
  }

  Future<void> _selectGoal(ListeningGoal goal) async {
    final updated = (_profile ?? const AcousticProfile(roomType: ''))
        .copyWith(listeningGoal: goal);
    setState(() => _profile = updated);
    await AcousticProfileStore.save(updated);
  }

  Future<void> _interpret(bool ko) async {
    final text = _requestController.text.trim();
    if (text.isEmpty || _interpreting) return;
    setState(() {
      _interpreting = true;
      _intentError = null;
      _pendingIntent = null;
    });
    final intent = await AcousticIntentService.extract(text, ko: ko);
    if (!mounted) return;
    setState(() {
      _interpreting = false;
      if (intent == null || !intent.hasAnySignal) {
        _intentError = ko
            ? '이해하지 못했어요. 조금 더 구체적으로 표현해 주세요.'
            : "Couldn't understand that. Try describing it a little more.";
      } else {
        _pendingIntent = intent; // wait for confirmation
      }
    });
  }

  Future<void> _confirmIntent() async {
    final intent = _pendingIntent;
    if (intent == null) return;
    final updated = (_profile ?? const AcousticProfile(roomType: ''))
        .copyWith(intent: intent);
    await AcousticProfileStore.save(updated);
    if (!mounted) return;
    setState(() {
      _profile = updated;
      _pendingIntent = null;
      _requestController.clear();
    });
  }

  void _cancelIntent() => setState(() => _pendingIntent = null);

  @override
  Widget build(BuildContext context) {
    final ko = Localizations.localeOf(context).languageCode == 'ko';
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white70),
        title: Text(
          ko ? '나의 사운드 취향' : 'My sound taste',
          style: const TextStyle(
              color: Colors.white, fontSize: 17, fontWeight: FontWeight.w400),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white24))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ko
                        ? '어떤 소리로 듣고 싶으세요?'
                        : 'How would you like it to sound?',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w300),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    ko
                        ? '고른 방향은 다음 공간 분석부터 반영됩니다. 지금 재생 중인 소리는 바뀌지 않아요.'
                        : 'Your choice applies from the next Space Analysis. It won’t change what’s playing now.',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 13,
                        height: 1.5),
                  ),
                  const SizedBox(height: 26),
                  _SectionLabel(ko ? '전체적인 느낌' : 'Overall feel'),
                  const SizedBox(height: 12),
                  for (final taste in ListeningTaste.values)
                    _ChoiceTile(
                      selected: _profile?.listeningTaste == taste,
                      title: taste.label(ko: ko),
                      subtitle: taste.description(ko: ko),
                      onTap: () => _selectTaste(taste),
                    ),
                  const SizedBox(height: 26),
                  _SectionLabel(ko ? '청취 목표' : 'Listening goal'),
                  const SizedBox(height: 12),
                  for (final goal in ListeningGoal.values)
                    _ChoiceTile(
                      selected: _profile?.listeningGoal == goal,
                      title: _goalLabel(goal, ko: ko),
                      subtitle: _goalDesc(goal, ko: ko),
                      onTap: () => _selectGoal(goal),
                    ),
                  const SizedBox(height: 30),
                  _SectionLabel(ko ? '직접 표현하기 (선택)' : 'Describe it (optional)'),
                  const SizedBox(height: 12),
                  _NaturalLanguageBox(
                    controller: _requestController,
                    interpreting: _interpreting,
                    ko: ko,
                    onInterpret: () => _interpret(ko),
                  ),
                  if (_intentError != null) ...[
                    const SizedBox(height: 10),
                    Text(_intentError!,
                        style: const TextStyle(
                            color: Color(0xFFFF8A80), fontSize: 12)),
                  ],
                  if (_pendingIntent != null) ...[
                    const SizedBox(height: 16),
                    _IntentConfirmCard(
                      intent: _pendingIntent!,
                      ko: ko,
                      onConfirm: _confirmIntent,
                      onCancel: _cancelIntent,
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  static String _goalLabel(ListeningGoal g, {required bool ko}) => switch (g) {
        ListeningGoal.music => ko ? '음악을 자연스럽게' : 'Music, naturally',
        ListeningGoal.movie => ko ? '영화·영상' : 'Movies & video',
        ListeningGoal.desktop => ko ? '가까이서 듣기' : 'Close-up listening',
        ListeningGoal.longListening =>
          ko ? '오래 들어도 편안하게' : 'Comfortable for hours',
      };

  static String _goalDesc(ListeningGoal g, {required bool ko}) => switch (g) {
        ListeningGoal.music =>
          ko ? '음악 감상에 어울리는 균형' : 'Balanced for listening to music',
        ListeningGoal.movie =>
          ko ? '대사와 효과가 또렷하게' : 'Clear dialogue and effects',
        ListeningGoal.desktop =>
          ko ? '책상처럼 가까운 환경' : 'For near-field, desk setups',
        ListeningGoal.longListening =>
          ko ? '피로감 없이 오래' : 'Easy on the ears over time',
      };
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(
            color: Colors.white.withValues(alpha: 0.38),
            fontSize: 10,
            letterSpacing: 2.0),
      );
}

class _ChoiceTile extends StatelessWidget {
  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ChoiceTile({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF69F0AE).withValues(alpha: 0.06)
              : Colors.white.withValues(alpha: 0.03),
          border: Border.all(
            color: selected
                ? const Color(0xFF69F0AE).withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.1),
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w400)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 12)),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle,
                  color: Color(0xFF69F0AE), size: 20),
          ],
        ),
      ),
    );
  }
}

class _NaturalLanguageBox extends StatelessWidget {
  final TextEditingController controller;
  final bool interpreting;
  final bool ko;
  final VoidCallback onInterpret;
  const _NaturalLanguageBox({
    required this.controller,
    required this.interpreting,
    required this.ko,
    required this.onInterpret,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          maxLines: 3,
          minLines: 2,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: ko
                ? '예) 밤에 오래 들어도 피곤하지 않게'
                : 'e.g. easy to listen to for hours at night',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.03),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: Colors.white.withValues(alpha: 0.3)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: interpreting ? null : onInterpret,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 13),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white24),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              interpreting
                  ? (ko ? '이해하는 중...' : 'Understanding...')
                  : (ko ? 'TUNAI에게 전달하기' : 'Send to TUNAI'),
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }
}

/// "TUNAI가 이렇게 이해했습니다" — the confirmation gate. The AI result is
/// shown in plain language and saved ONLY when the user taps confirm.
class _IntentConfirmCard extends StatelessWidget {
  final AcousticIntent intent;
  final bool ko;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  const _IntentConfirmCard({
    required this.intent,
    required this.ko,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final lines = _describe(intent, ko: ko);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF7C4DFF).withValues(alpha: 0.06),
        border:
            Border.all(color: const Color(0xFF7C4DFF).withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ko ? 'TUNAI가 이렇게 이해했습니다' : 'Here’s what TUNAI understood',
            style: const TextStyle(color: Color(0xFFB39DFF), fontSize: 13),
          ),
          const SizedBox(height: 12),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('· $line',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontSize: 13.5,
                      height: 1.4)),
            ),
          if (lines.isEmpty)
            Text(
              ko ? '뚜렷한 방향을 찾지 못했어요.' : 'No clear direction found.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: onCancel,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white24),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(ko ? '취소' : 'Cancel',
                        style:
                            const TextStyle(color: Colors.white60, fontSize: 14)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: onConfirm,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C4DFF).withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(ko ? '이대로 저장' : 'Save this',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 14)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static List<String> _describe(AcousticIntent i, {required bool ko}) {
    final out = <String>[];
    switch (i.soundCharacter) {
      case SoundCharacter.warm:
        out.add(ko ? '따뜻한 음색' : 'A warm character');
      case SoundCharacter.detailed:
        out.add(ko ? '또렷하고 섬세한 표현' : 'Crisp, detailed sound');
      case SoundCharacter.relaxed:
        out.add(ko ? '편안한 느낌' : 'A relaxed feel');
      case SoundCharacter.energetic:
        out.add(ko ? '생동감 있는 느낌' : 'An energetic feel');
      case SoundCharacter.natural:
        out.add(ko ? '자연스러운 밸런스' : 'A natural balance');
      case null:
        break;
    }
    switch (i.bassPreference) {
      case BassPreference.powerful:
        out.add(ko ? '풍부한 저음' : 'Fuller bass');
      case BassPreference.controlled:
        out.add(ko ? '단정한 저음' : 'Controlled bass');
      case BassPreference.natural:
        out.add(ko ? '자연스러운 저음' : 'Natural bass');
      case null:
        break;
    }
    if (i.vocalPreference == VocalPreference.forward) {
      out.add(ko ? '또렷한 보컬' : 'Forward vocals');
    }
    if (i.listeningFatigue == 'low' ||
        i.listeningGoal == ListeningGoal.longListening) {
      out.add(ko ? '오래 들어도 편안한 방향' : 'Comfortable for long listening');
    }
    return out;
  }
}
