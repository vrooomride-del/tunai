import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/dsp/transport/dsp_transport_provider.dart';
import '../../core/profiles/system_profile.dart';
import '../../shared/widgets.dart';
import 'dsp_unlock_flags.dart';

// ── ADAU1466 주소 상수 (v0.8B Export18) ────────────────────────────────────
const _kDriverGainAddrs = [0x3B8, 0x3BB, 0x3C4, 0x3CA, 0x3C7, 0x3CD];
const _kDriverMuteAddrs = [0x60E, 0x60F, 0x613, 0x612, 0x610, 0x611];
// 아래 상수는 Step 3 SafeLoad 구현 시 사용
const kDriverDelayAddrs1466 = [0x3C1, 0x3C2, 0x408, 0x406, 0x405, 0x407];
const kGlobalPeqLAddr1466 = 0x69;
const kGlobalPeqRAddr1466 = 0x9B;
const _kPerDriverPeqAddrs = [0x21A, 0x27E, 0x326, 0x2F4, 0x24C, 0x2B0];
const _kDspMapVersion = 'ADAU1466 v0.8B Export18';

const _kChannelNames = [
  'WOO L', 'WOO R', 'MID L', 'MID R', 'TWE L', 'TWE R',
];

final _gainProvider =
    StateProvider<List<double>>((ref) => List.filled(6, 0.0));
final _muteProvider =
    StateProvider<List<bool>>((ref) => List.filled(6, false));
final _delayProvider =
    StateProvider<List<double>>((ref) => List.filled(6, 0.0));
final _globalPeqProvider =
    StateProvider<List<double>>((ref) => List.filled(20, 0.0));

// ── ADAU1701 주소 상수 (v0.8 Export14) ────────────────────────────────────
const _kDspMapVersion1701 = 'ADAU1701 v0.8 Export14';
const _kGain1701Addrs = [0x0084, 0x0085, 0x0088, 0x0089];
const _kMute1701Addrs = [0x0086, 0x0087, 0x008A, 0x008B];
// delay addrs: 0x008C~0x008F (채널 미확정, 잠금)
const _kPeq1701Addrs = [0x0030, 0x0045, 0x0064, 0x0074];
const _kChannelNames1701 = ['WOO L', 'WOO R', 'TWE L', 'TWE R'];

final _gain1701Provider =
    StateProvider<List<double>>((ref) => List.filled(4, 0.0));
final _mute1701Provider =
    StateProvider<List<bool>>((ref) => List.filled(4, false));
final _delay1701Provider =
    StateProvider<List<double>>((ref) => List.filled(4, 0.0));

class FactoryScreen extends ConsumerWidget {
  const FactoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(systemProfileProvider);
    final isAdau1466 = profile.isAdau1466;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            const TunaiTopBar(subtitle: 'FACTORY'),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              color: const Color(0xFF3A1A00),
              child: const Text(
                'Changing factory settings may affect speaker safety and sound output.\n팩토리 설정 변경은 스피커 안전성과 출력에 영향을 줄 수 있습니다.',
                style: TextStyle(color: Color(0xFFFFB366), fontSize: 11, height: 1.5),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isAdau1466) ...[
                      _Adau1701FactoryContent(),
                      const SizedBox(height: 24),
                      const _SecLabel('DSP MAP'),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.memory_outlined,
                                color: Colors.white38, size: 14),
                            SizedBox(width: 10),
                            Text(_kDspMapVersion1701,
                                style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                    fontFamily: 'monospace',
                                    letterSpacing: 1)),
                          ],
                        ),
                      ),
                    ] else ...[
                      _FactoryContent(),
                      const SizedBox(height: 24),
                      // ── DSP 맵 버전 ─────────────────────────────────────
                      const Text('DSP MAP',
                          style: TextStyle(
                              color: Colors.white60,
                              fontSize: 13,
                              letterSpacing: 3)),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.memory_outlined,
                                color: Colors.white38, size: 14),
                            SizedBox(width: 10),
                            Text(_kDspMapVersion,
                                style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                    fontFamily: 'monospace',
                                    letterSpacing: 1)),
                          ],
                        ),
                      ),
                    ],
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

class _FactoryContent extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transport = ref.watch(dspTransportProvider);
    final connected = transport != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Driver Gain ──────────────────────────────────────────────────
        const _SecLabel('DRIVER GAIN'),
        const SizedBox(height: 2),
        const Text('즉시 write 가능 (Capture Window 불필요)',
            style: TextStyle(
                color: Colors.white38, fontSize: 10, letterSpacing: 0.5)),
        const SizedBox(height: 10),
        _GainSliders(connected: connected),
        const SizedBox(height: 20),

        // ── Driver Mute ──────────────────────────────────────────────────
        const _SecLabel('DRIVER MUTE'),
        const _LockedNote('Capture Window 확인 필요'),
        const SizedBox(height: 10),
        _MuteToggles(),
        const SizedBox(height: 20),

        // ── Driver Delay ─────────────────────────────────────────────────
        const _SecLabel('DRIVER DELAY (samples)'),
        const _LockedNote('Capture Window 확인 필요'),
        const SizedBox(height: 10),
        _DelaySliders(),
        const SizedBox(height: 20),

        // ── Global PEQ ───────────────────────────────────────────────────
        const _SecLabel('GLOBAL PEQ L / R (20-band)'),
        const _LockedNote('SafeLoad 구현 완료 후 unlock'),
        const SizedBox(height: 10),
        _GlobalPeqSliders(),
        const SizedBox(height: 20),

        // ── Per-driver PEQ ───────────────────────────────────────────────
        const _SecLabel('PER-DRIVER PEQ (6ch × 20-band)'),
        const _LockedNote('SafeLoad 구현 완료 후 unlock'),
        const SizedBox(height: 10),
        _PerDriverPeqInfo(),
      ],
    );
  }
}

class _GainSliders extends ConsumerWidget {
  final bool connected;

  const _GainSliders({required this.connected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gains = ref.watch(_gainProvider);
    final transport = ref.watch(dspTransportProvider);

    return Column(
      children: List.generate(6, (i) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              SizedBox(
                width: 52,
                child: Text(_kChannelNames[i],
                    style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        letterSpacing: 1)),
              ),
              Expanded(
                child: Slider(
                  value: gains[i],
                  min: -40,
                  max: 12,
                  divisions: 104,
                  activeColor: Colors.white,
                  inactiveColor: Colors.white12,
                  onChanged: (connected && DspUnlockFlags.gainWriteUnlocked)
                      ? (v) {
                          final next = List<double>.from(gains);
                          next[i] = v;
                          ref.read(_gainProvider.notifier).state = next;
                        }
                      : null,
                  onChangeEnd:
                      (connected && DspUnlockFlags.gainWriteUnlocked)
                          ? (v) async {
                              if (transport == null) return;
                              final linear = pow(10.0, v / 20.0).toDouble();
                              final fixed =
                                  (linear * (1 << 27)).round();
                              await transport.writeParameter(
                                  _kDriverGainAddrs[i], [
                                (fixed >> 24) & 0xFF,
                                (fixed >> 16) & 0xFF,
                                (fixed >> 8) & 0xFF,
                                fixed & 0xFF,
                              ]);
                            }
                          : null,
                ),
              ),
              SizedBox(
                width: 44,
                child: Text('${gains[i].toStringAsFixed(1)}dB',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        fontFamily: 'monospace')),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _MuteToggles extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mutes = ref.watch(_muteProvider);

    return Column(
      children: List.generate(6, (i) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              SizedBox(
                width: 52,
                child: Text(_kChannelNames[i],
                    style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        letterSpacing: 1)),
              ),
              const SizedBox(width: 8),
              Container(
                width: 48,
                height: 26,
                decoration: BoxDecoration(
                  color: mutes[i] ? Colors.white24 : Colors.transparent,
                  border: Border.all(color: Colors.white12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Center(
                  child: Text(mutes[i] ? 'MUTE' : 'ON',
                      style: const TextStyle(
                          color: Colors.white24,
                          fontSize: 9,
                          letterSpacing: 1)),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                  '0x${_kDriverMuteAddrs[i].toRadixString(16).toUpperCase()}',
                  style: const TextStyle(
                      color: Colors.white24,
                      fontSize: 10,
                      fontFamily: 'monospace')),
            ],
          ),
        );
      }),
    );
  }
}

class _DelaySliders extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final delays = ref.watch(_delayProvider);

    return Column(
      children: List.generate(6, (i) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              SizedBox(
                width: 52,
                child: Text(_kChannelNames[i],
                    style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        letterSpacing: 1)),
              ),
              Expanded(
                child: Slider(
                  value: delays[i],
                  min: 0,
                  max: 100,
                  divisions: 100,
                  activeColor: Colors.white12,
                  inactiveColor: Colors.white12,
                  onChanged: null,
                ),
              ),
              SizedBox(
                width: 44,
                child: Text('${delays[i].toStringAsFixed(0)}smp',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        color: Colors.white24,
                        fontSize: 11,
                        fontFamily: 'monospace')),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _GlobalPeqSliders extends ConsumerWidget {
  static const _freqs = [
    '20', '32', '50', '80', '125', '200', '315', '500', '800', '1k',
    '1.6k', '2.5k', '4k', '6.3k', '10k', '12.5k', '14k', '16k', '18k', '20k',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bands = ref.watch(_globalPeqProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('L (0x69) / R (0x9B)',
            style: TextStyle(
                color: Colors.white24,
                fontSize: 10,
                fontFamily: 'monospace',
                letterSpacing: 0.5)),
        const SizedBox(height: 8),
        SizedBox(
          height: 120,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(20, (i) {
              return Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: Slider(
                          value: bands[i],
                          min: -12,
                          max: 12,
                          activeColor: Colors.white12,
                          inactiveColor: Colors.white12,
                          onChanged: null,
                        ),
                      ),
                    ),
                    Text(_freqs[i],
                        style: const TextStyle(
                            color: Colors.white24,
                            fontSize: 7)),
                  ],
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

class _PerDriverPeqInfo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(6, (i) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              SizedBox(
                width: 52,
                child: Text(_kChannelNames[i],
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 11)),
              ),
              Text(
                  '0x${_kPerDriverPeqAddrs[i].toRadixString(16).toUpperCase()}  · 20-band',
                  style: const TextStyle(
                      color: Colors.white24,
                      fontSize: 10,
                      fontFamily: 'monospace',
                      letterSpacing: 0.5)),
            ],
          ),
        );
      }),
    );
  }
}

// ── ADAU1701 Factory Content ─────────────────────────────────────────────────

class _Adau1701FactoryContent extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transport = ref.watch(dspTransportProvider);
    final connected = transport != null;
    final gains = ref.watch(_gain1701Provider);
    final mutes = ref.watch(_mute1701Provider);
    final delays = ref.watch(_delay1701Provider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Driver Gain ──────────────────────────────────────────────────
        const _SecLabel('DRIVER GAIN'),
        const SizedBox(height: 2),
        const Text('즉시 write 가능 (Capture Window 불필요)',
            style: TextStyle(
                color: Colors.white38, fontSize: 10, letterSpacing: 0.5)),
        const SizedBox(height: 10),
        Column(
          children: List.generate(4, (i) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 52,
                    child: Text(_kChannelNames1701[i],
                        style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                            letterSpacing: 1)),
                  ),
                  Expanded(
                    child: Slider(
                      value: gains[i],
                      min: -40,
                      max: 12,
                      divisions: 104,
                      activeColor: Colors.white,
                      inactiveColor: Colors.white12,
                      onChanged: (connected && DspUnlockFlags.gainWriteUnlocked)
                          ? (v) {
                              final next = List<double>.from(gains);
                              next[i] = v;
                              ref.read(_gain1701Provider.notifier).state = next;
                            }
                          : null,
                      onChangeEnd:
                          (connected && DspUnlockFlags.gainWriteUnlocked)
                              ? (v) async {
                                  final linear =
                                      pow(10.0, v / 20.0).toDouble();
                                  final fixed =
                                      (linear * (1 << 23)).round();
                                  await transport.writeParameter(
                                      _kGain1701Addrs[i], [
                                    (fixed >> 24) & 0xFF,
                                    (fixed >> 16) & 0xFF,
                                    (fixed >> 8) & 0xFF,
                                    fixed & 0xFF,
                                  ]);
                                }
                              : null,
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text('${gains[i].toStringAsFixed(1)}dB',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                            fontFamily: 'monospace')),
                  ),
                ],
              ),
            );
          }),
        ),
        const SizedBox(height: 20),

        // ── Driver Mute (잠금) ────────────────────────────────────────────
        const _SecLabel('DRIVER MUTE'),
        const _LockedNote('Capture Window 확인 필요'),
        const SizedBox(height: 10),
        Column(
          children: List.generate(4, (i) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 52,
                    child: Text(_kChannelNames1701[i],
                        style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                            letterSpacing: 1)),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 48,
                    height: 26,
                    decoration: BoxDecoration(
                      color: mutes[i] ? Colors.white24 : Colors.transparent,
                      border: Border.all(color: Colors.white12),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Center(
                      child: Text(mutes[i] ? 'MUTE' : 'ON',
                          style: const TextStyle(
                              color: Colors.white24,
                              fontSize: 9,
                              letterSpacing: 1)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                      '0x${_kMute1701Addrs[i].toRadixString(16).toUpperCase()}',
                      style: const TextStyle(
                          color: Colors.white24,
                          fontSize: 10,
                          fontFamily: 'monospace')),
                ],
              ),
            );
          }),
        ),
        const SizedBox(height: 20),

        // ── Driver Delay (잠금) ───────────────────────────────────────────
        const _SecLabel('DRIVER DELAY (samples)'),
        const _LockedNote('채널 미확정'),
        const SizedBox(height: 10),
        Column(
          children: List.generate(4, (i) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 52,
                    child: Text(_kChannelNames1701[i],
                        style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                            letterSpacing: 1)),
                  ),
                  Expanded(
                    child: Slider(
                      value: delays[i],
                      min: 0,
                      max: 100,
                      divisions: 100,
                      activeColor: Colors.white12,
                      inactiveColor: Colors.white12,
                      onChanged: null,
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text('${delays[i].toStringAsFixed(0)}smp',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            color: Colors.white24,
                            fontSize: 11,
                            fontFamily: 'monospace')),
                  ),
                ],
              ),
            );
          }),
        ),
        const SizedBox(height: 20),

        // ── Per-driver PEQ (잠금) ─────────────────────────────────────────
        const _SecLabel('PER-DRIVER PEQ (4ch × 20-band)'),
        const _LockedNote('SafeLoad 구현 완료 후 unlock'),
        const SizedBox(height: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(4, (i) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 52,
                    child: Text(_kChannelNames1701[i],
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11)),
                  ),
                  Text(
                      '0x${_kPeq1701Addrs[i].toRadixString(16).toUpperCase().padLeft(4, '0')}  · 20-band',
                      style: const TextStyle(
                          color: Colors.white24,
                          fontSize: 10,
                          fontFamily: 'monospace',
                          letterSpacing: 0.5)),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _SecLabel extends StatelessWidget {
  final String text;

  const _SecLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          color: Colors.white60, fontSize: 13, letterSpacing: 3));
}

class _LockedNote extends StatelessWidget {
  final String reason;

  const _LockedNote(this.reason);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: [
            const Icon(Icons.lock_outline, color: Colors.white24, size: 11),
            const SizedBox(width: 4),
            Text(reason,
                style: const TextStyle(
                    color: Colors.white24,
                    fontSize: 10,
                    letterSpacing: 0.5)),
          ],
        ),
      );
}
