import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/consumer_sound_profile.dart';
import '../../shared/widgets.dart';
import '../ble/ble_controller.dart';
import '../dsp/master_volume_controller.dart';

class ListenScreen extends ConsumerWidget {
  const ListenScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ko = Localizations.localeOf(context).languageCode == 'ko';
    final profile = ref.watch(activeConsumerProfileProvider);
    final connected =
        ref.watch(bleProvider).connection == BleConnectionState.connected;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const TunaiTopBar(subtitle: 'LISTEN'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ko ? '나의 사운드를\n들어보세요.' : 'Listen to\nYour Sound.',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        height: 1.18,
                        fontWeight: FontWeight.w300,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      profile == null
                          ? (ko
                              ? '공간에 맞춘 나만의 사운드가 여기에 표시됩니다.'
                              : 'Your sound, shaped for your space, will appear here.')
                          : (connected
                              ? (ko
                                  ? '지금 나만의 사운드로 재생하고 있습니다.'
                                  : 'Your speaker is playing with Your Sound.')
                              : (ko
                                  ? '스피커를 연결하면 나만의 사운드로 들을 수 있습니다.'
                                  : 'Connect your speaker to listen with Your Sound.')),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.42),
                        fontSize: 14,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 36),
                    _CurrentSoundCard(
                      profile: profile,
                      connected: connected,
                      ko: ko,
                    ),
                    const SizedBox(height: 36),
                    const _ListeningLevelSection(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrentSoundCard extends StatelessWidget {
  final ConsumerSoundProfile? profile;
  final bool connected;
  final bool ko;

  const _CurrentSoundCard({
    required this.profile,
    required this.connected,
    required this.ko,
  });

  @override
  Widget build(BuildContext context) {
    final active = profile != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                ko ? '현재 사운드' : 'CURRENT SOUND',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.38),
                  fontSize: 10,
                  letterSpacing: 2.2,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: active
                      ? const Color(0xFF69F0AE).withValues(alpha: 0.1)
                      : Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color:
                            active ? const Color(0xFF69F0AE) : Colors.white24,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      active
                          ? (ko ? '활성' : 'ACTIVE')
                          : (ko ? '준비 전' : 'NOT READY'),
                      style: TextStyle(
                        color:
                            active ? const Color(0xFF69F0AE) : Colors.white38,
                        fontSize: 9,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),
          Text(
            profile?.name ?? (ko ? '나만의 사운드가 없습니다' : 'No sound yet'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              height: 1.3,
              fontWeight: FontWeight.w300,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            profile == null
                ? (ko
                    ? '공간 분석을 완료하면 나만의 사운드를 만들 수 있습니다.'
                    : 'Complete Space Analysis to create Your Sound.')
                : (ko
                    ? '${profile!.roomTypeLabel}에 맞춘 나의 사운드'
                    : 'Your Sound for ${profile!.roomTypeLabelEn}'),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 13,
              height: 1.5,
            ),
          ),
          if (active && !connected) ...[
            const SizedBox(height: 22),
            Container(height: 0.5, color: Colors.white10),
            const SizedBox(height: 18),
            Row(
              children: [
                const Icon(Icons.speaker_outlined,
                    color: Colors.white38, size: 17),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    ko ? '스피커 연결 대기 중' : 'Waiting for your speaker',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

String _levelLabel(double value, {required bool ko}) {
  if (value <= -55) return ko ? '낮게' : 'Low';
  if (value <= -45) return ko ? '편안하게' : 'Comfortable';
  return ko ? '생생하게' : 'Lively';
}

class _ListeningLevelSection extends ConsumerWidget {
  const _ListeningLevelSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ko = Localizations.localeOf(context).languageCode == 'ko';
    final volume = ref.watch(masterVolumeProvider);
    final controller = ref.read(masterVolumeProvider.notifier);
    const presets = [
      (-60.0, '낮게', 'Low'),
      (-50.0, '편안하게', 'Comfortable'),
      (-40.0, '생생하게', 'Lively'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          ko ? '듣기 음량' : 'Listening Level',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.42),
            fontSize: 11,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          ko
              ? '현재 · ${_levelLabel(volume, ko: true)}'
              : 'Current · ${_levelLabel(volume, ko: false)}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w300,
          ),
        ),
        const SizedBox(height: 12),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            activeTrackColor: Colors.white70,
            inactiveTrackColor: Colors.white12,
            thumbColor: Colors.white,
            overlayColor: Colors.white10,
          ),
          child: Slider(
            value: volume,
            min: -70,
            max: 0,
            onChanged: controller.updateUiOnly,
            onChangeEnd: controller.setVolume,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final (value, labelKo, labelEn) in presets) ...[
              Expanded(
                child: _LevelPreset(
                  label: ko ? labelKo : labelEn,
                  selected: volume == value,
                  onTap: () => controller.setVolume(value),
                ),
              ),
              if (value != presets.last.$1) const SizedBox(width: 8),
            ],
          ],
        ),
      ],
    );
  }
}

class _LevelPreset extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _LevelPreset({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? Colors.white.withValues(alpha: 0.09)
                : Colors.transparent,
            border: Border.all(
              color: selected ? Colors.white38 : Colors.white12,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white38,
              fontSize: 11,
            ),
          ),
        ),
      );
}
