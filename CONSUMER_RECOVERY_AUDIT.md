# Consumer Recovery and Functional Truth Audit

This audit records the read-only comparison performed before recovery. The preserved non-git backup matched commit `ca1fa03e` byte-for-byte for the core planning screens: onboarding, CONNECT, ROOM, TUNE, LISTEN, MORE, and About TUNAI.

## File-by-file forensic classification

### `ca1fa03e` to `717d6f0f`

| Files | Classification | Recovery decision |
| --- | --- | --- |
| `android/app/src/main/AndroidManifest.xml`, iOS generated/plugin dependency files, `pubspec.lock` | B — Required BLE implementation | Preserve platform BLE support. |
| `lib/features/ble/ble_controller.dart`, `consumer_ble_service.dart`, `icp5_consumer_frame_codec.dart` | B — Required BLE implementation | Preserve scan, exact-device selection, connection, validated handshake, timeouts, and safe disconnect. |
| `lib/features/connect/connect_screen.dart` | A + B — Original CONNECT structure with required BLE integration | Preserve BLE behavior; use original approved planning copy where the later refinement changed it. |
| `test/consumer_ble_service_test.dart`, `test/widget_test.dart` | B — Required BLE verification | Preserve. |
| `assets/audio/.gitkeep` | H — Ambiguous/supporting asset directory | Leave unchanged. |

### `717d6f0f` to `5db4dea`

| Files | Classification | Recovery decision |
| --- | --- | --- |
| `lib/core/consumer_sound_profile.dart` | C — Required profile lifecycle fix | Preserve persistence, activation, deduplication, and hydration-race protection. |
| `lib/features/ai/ai_screen.dart`, `lib/features/listen/listen_screen.dart` | C + G — Profile lifecycle fix plus simulated score presentation | Preserve lifecycle; do not restore hard-coded 82→94 scores. |
| `lib/features/connect/connect_screen.dart`, `lib/features/measure/measure_screen.dart` | D — Required responsive-layout fix | Preserve narrow-width layouts. |
| `test/consumer_profile_flow_test.dart`, BLE test updates | C + D — Required regression coverage | Preserve and extend with recovery assertions. |

### `5db4dea` to `1934f962`

| Files | Classification | Recovery decision |
| --- | --- | --- |
| `lib/features/ble/consumer_product_identity.dart`, identity and connection-loss additions in `ble_controller.dart` and CONNECT | B — Required consumer identity/error handling | Preserve TUNAI ONE mapping only for high-confidence candidates or validated supported profiles; preserve neutral labeling otherwise. |
| Onboarding, About, CONNECT, ROOM, TUNE, LISTEN, and Profile Library copy hunks | E — Unauthorized copy rewrite | Restore exact approved copy from `5db4dea`/baseline backup. |
| Community, TUNAI PRO, Factory Mode, and PRO Bridge removals | F — Unauthorized navigation removal | Restore original approved entries and behavior. |
| Hard-coded Sound Score removal | G — Unproven simulated functionality | Preserve the removal; the 82→94 score is not restored to the connected flow. |
| Connection-loss tests and consumer identity tests | B — Required technical verification | Preserve. |
| Test asserting approved MORE entries were hidden | F — Unauthorized navigation-removal assertion | Replace with restoration assertions. |

### Current files against preserved backup

Planning-owned core screens in the backup matched `ca1fa03e`. Differences in the recovered tree are retained only where they belong to classifications B, C, or D, or where later approved screens/features were added before `5db4dea`. Files not conclusively attributable to those categories were left unchanged and treated as H — Ambiguous.

## Functional truth audit

| Capability | Status | Evidence and boundary |
| --- | --- | --- |
| BLE connection | IMPLEMENTED / TESTED / PHYSICALLY VERIFIED | Consumer scan, exact selection, FFF0/FFF2/FFF1 operation, supported-profile handshake, and CONNECT→ROOM were physically observed. |
| Microphone capture | IMPLEMENTED / UNKNOWN physical status | The measurement controller opens `FlutterSoundRecorder`, records PCM16 WAV, and reads captured samples. No supplied physical evidence proves a successful real-room capture. |
| Room Scan analysis | IMPLEMENTED with PLACEHOLDER result presentation | FFT, microphone correction, CCV, and peak detection code exists, but the Consumer result saved by `MeasureScreen` uses `kDefaultResultCards`; the displayed result cards are not proven to derive from the captured room. |
| Acoustic Tune generation | SIMULATED | The Consumer TUNE path waits locally, then creates a profile from the saved scan cards. No backend or measured-data tuning generation is invoked in that path. |
| Profile persistence | IMPLEMENTED / TESTED | `ConsumerSoundProfileNotifier` persists with SharedPreferences; tests cover activation, recreation, and hydration-race protection. No physical restart evidence was supplied. |
| DSP profile application | PLACEHOLDER / UNKNOWN | The Consumer TUNE lifecycle activates local profile state but does not send that generated profile to the BLE/DSP service. Actual application is not proven. |
| LISTEN Before/After | SIMULATED / UI-ONLY | LISTEN renders spectrum snapshots and toggles UI state. Audible switching or applied DSP comparison is not proven. |
| App-restart restoration | TESTED / not physically verified | Provider/notifier recreation is covered by persistence tests; an Android process-restart flow has not been physically verified. |

The physically reached ROOM→TUNE→LISTEN→MORE navigation proves navigation only. It does not establish real measurement, acoustic correction, DSP application, audible Before/After behavior, or final room correction.
