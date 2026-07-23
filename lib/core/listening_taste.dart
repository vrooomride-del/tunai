import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A user's high-level listening taste, as a stated preference.
///
/// STRUCTURE ONLY — intentionally NOT connected to any EQ / TunePlan / DSP
/// behaviour in this batch. It exists so a future feature ("shape my sound
/// toward Warm / Deep Bass") has a stable data model and a stored value to
/// build on, without a later breaking migration. Nothing reads this to alter
/// a correction today; [TunePlanner] still takes its direction solely from
/// the existing [SoundPreference] used at Tune creation.
///
/// Kept deliberately separate from [SoundPreference] (which is already wired
/// into TunePlanner's per-band weighting): conflating a not-yet-connected
/// taste selector with the live EQ weighting is exactly how a "structure
/// only" field turns into an accidental behaviour change.
enum ListeningTaste {
  natural,
  warm,
  detailed,
  deepBass;

  String toJson() => name;

  static ListeningTaste fromJson(String? value) => switch (value) {
        'warm' => ListeningTaste.warm,
        'detailed' => ListeningTaste.detailed,
        'deepBass' => ListeningTaste.deepBass,
        _ => ListeningTaste.natural,
      };

  String label({required bool ko}) => switch (this) {
        ListeningTaste.natural => ko ? '자연스럽게' : 'Natural',
        ListeningTaste.warm => ko ? '따뜻하게' : 'Warm',
        ListeningTaste.detailed => ko ? '섬세하게' : 'Detailed',
        ListeningTaste.deepBass => ko ? '깊은 저음' : 'Deep Bass',
      };

  String description({required bool ko}) => switch (this) {
        ListeningTaste.natural =>
          ko ? '있는 그대로의 균형 잡힌 소리' : 'True to the source, evenly balanced',
        ListeningTaste.warm =>
          ko ? '부드럽고 포근한 음색' : 'Soft and full-bodied',
        ListeningTaste.detailed =>
          ko ? '작은 소리까지 또렷하게' : 'Crisp, with fine detail',
        ListeningTaste.deepBass =>
          ko ? '묵직하고 깊은 저음' : 'Weighty, extended low end',
      };
}

/// Session-scoped selection. Persistence and any effect on sound are
/// deliberately left for the future feature that consumes this — see the
/// enum doc. Defaults to [ListeningTaste.natural].
final listeningTasteProvider =
    StateProvider<ListeningTaste>((ref) => ListeningTaste.natural);
