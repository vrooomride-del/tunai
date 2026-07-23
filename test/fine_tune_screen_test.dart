import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai/core/consumer_sound_profile.dart';
import 'package:tunai/core/room_scan_result.dart';
import 'package:tunai/core/sound_preference.dart';
import 'package:tunai/core/tune_plan.dart';
import 'package:tunai/features/fine_tune/fine_tune_screen.dart';

/// Note: FineTuneScreen's happy path depends on RoomMeasurementStore, which
/// reads real device state via path_provider — not exercised at the widget
/// level anywhere else in this suite either (see TunePlanner + Fine Tune
/// logic coverage in fine_tune_adjustments_test.dart, which is unaffected).
/// This test covers the safe fallback: no measurement on record for the
/// given profile short-circuits (RoomMeasurementStore.load() returns null
/// as soon as SharedPreferences has no stored id — before ever touching
/// path_provider) straight to the "unavailable" UI, with no technical terms
/// exposed.
ConsumerSoundProfile _profileWithoutMeasurement() {
  final now = DateTime.utc(2026, 7, 17);
  return ConsumerSoundProfile(
    id: 'profile-1',
    name: 'Living Room Your Sound',
    roomType: 'Living Room',
    createdAt: now,
    updatedAt: now,
    micProfileName: 'Generic Phone Mic',
    confidence: 'High',
    isActive: false,
    status: ConsumerProfileStatus.ready,
    resultCards: kDefaultResultCards,
    preference: SoundPreference.balanced,
    measurementId: 'measurement-not-actually-stored',
    tunePlanId: 'measurement-not-actually-stored:v1',
    isSelected: true,
    generationStatus: ConsumerProfileGenerationStatus.generated,
    deploymentStatus: TuneDeploymentStatus.notDeployed,
  );
}

final _scan = RoomScanResult(
  roomType: 'Living Room',
  micProfileName: 'Generic Phone Mic',
  completedAt: DateTime.fromMillisecondsSinceEpoch(1000),
  confidence: 'High',
  cards: kDefaultResultCards,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows the unavailable state when no measurement is on record',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: FineTuneScreen(
          baseProfile: _profileWithoutMeasurement(),
          scan: _scan,
        ),
      ),
    ));
    // Avoid pumpAndSettle: bleProvider (read by TunaiTopBar) schedules its
    // own recurring frames, as elsewhere in this test suite, so it never
    // converges.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Default test locale is English (no localizationsDelegates configured
    // here), so the English copy renders.
    expect(find.textContaining("isn't available right now"), findsOneWidget);
    expect(find.textContaining('PEQ'), findsNothing);
    expect(find.textContaining('DSP'), findsNothing);
    expect(find.textContaining('dB'), findsNothing);
    expect(find.textContaining('Hz'), findsNothing);
  });
}
