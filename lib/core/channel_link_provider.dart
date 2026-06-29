import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'profiles/system_profile.dart';

/// 대역(ChannelType)별 L/R 링크 상태 — 기본값 모두 ON
final channelLinkProvider =
    StateProvider<Map<ChannelType, bool>>((ref) => {
      ChannelType.woofer: true,
      ChannelType.mid: true,
      ChannelType.tweeter: true,
      ChannelType.subwoofer: true,
      ChannelType.fullRange: true,
    });

/// 채널 인덱스별 게인 오프셋 (dB), 기본값 0.0
final channelGainProvider =
    StateProvider<Map<int, double>>((ref) => {});

/// 채널 인덱스별 크로스오버 주파수 (Hz)
/// 초기값은 _CrossoverCard에서 SpeakerProfile.recommendedCrossoverFreq로 설정
final channelXoFreqProvider =
    StateProvider<Map<int, double>>((ref) => {});

// ── 헬퍼 ─────────────────────────────────────────────────────

extension ChannelLinkRef on WidgetRef {
  bool isLinked(ChannelType type) =>
      watch(channelLinkProvider)[type] ?? true;

  void toggleLink(ChannelType type) {
    final map = Map<ChannelType, bool>.from(read(channelLinkProvider));
    map[type] = !(map[type] ?? true);
    read(channelLinkProvider.notifier).state = map;
  }

  double channelGain(int idx) =>
      watch(channelGainProvider)[idx] ?? 0.0;

  void setChannelGain(int idx, double gain,
      {required SystemProfile sys, bool propagateLink = true}) {
    final map = Map<int, double>.from(read(channelGainProvider));
    map[idx] = gain;

    if (propagateLink) {
      final ch = sys.channels[idx];
      final linked = read(channelLinkProvider)[ch.type] ?? true;
      if (linked) {
        // 같은 대역 반대쪽 채널 찾아서 동기화
        for (int i = 0; i < sys.channels.length; i++) {
          if (i != idx && sys.channels[i].type == ch.type) {
            map[i] = gain;
          }
        }
      }
    }
    read(channelGainProvider.notifier).state = map;
  }

  double channelXoFreq(int idx, {double fallback = 2000.0}) =>
      watch(channelXoFreqProvider)[idx] ?? fallback;

  void setChannelXoFreq(int idx, double freq,
      {required SystemProfile sys, bool propagateLink = true}) {
    final map = Map<int, double>.from(read(channelXoFreqProvider));
    map[idx] = freq;

    if (propagateLink) {
      final ch = sys.channels[idx];
      final linked = read(channelLinkProvider)[ch.type] ?? true;
      if (linked) {
        for (int i = 0; i < sys.channels.length; i++) {
          if (i != idx && sys.channels[i].type == ch.type) {
            map[i] = freq;
          }
        }
      }
    }
    read(channelXoFreqProvider.notifier).state = map;
  }
}
