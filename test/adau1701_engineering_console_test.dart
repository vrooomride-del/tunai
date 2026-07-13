// ── TUNAI Consumer — ADAU1701 Engineering Console Tests ──────────────────────
// 49 tests covering: loader, executor guards, write path, persistence,
// model round-trip, value formats, safety constraints, and policy.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai/core/adau1701_engineering_candidate.dart';
import 'package:tunai/core/adau1701_engineering_loader.dart';
import 'package:tunai/core/adau1701_engineering_executor.dart';
import 'package:tunai/core/adau1701_engineering_persistence.dart';
import 'package:tunai/core/dsp/transport/dsp_transport.dart';

// ── Mock Transport ────────────────────────────────────────────────────────────

class _MockTransport implements DspTransport {
  final bool shouldThrow;
  final List<({int address, List<int> bytes})> calls = [];
  bool throwOnRestore = false;
  int _callCount = 0;

  _MockTransport({this.shouldThrow = false});

  @override
  Future<void> writeParameter(int address, List<int> bytes4) async {
    _callCount++;
    if (shouldThrow) throw Exception('BLE error');
    if (throwOnRestore && _callCount > 1) throw Exception('restore error');
    calls.add((address: address, bytes: bytes4));
  }

  @override
  Future<List<int>?> readParameter(int address) async => null;

  @override
  Future<bool> detectDevice() async => true;

  @override
  void dispose() {}
}

// ── Helper ────────────────────────────────────────────────────────────────────

Adau1701EngWriteRequest _req({
  String id = 'gain_0x0084',
  int address = 0x0084,
  int testVal = 0x00400000,
  int restoreVal = 0x00800000,
  bool userConfirmed = true,
  bool restoreConfirmed = true,
  bool isBlocked = false,
}) =>
    Adau1701EngWriteRequest(
      id: id,
      addressInt: address,
      label: 'Test',
      testValue32: testVal,
      restoreValue32: restoreVal,
      userConfirmed: userConfirmed,
      restoreValueConfirmed: restoreConfirmed,
      isBlocked: isBlocked,
    );

void main() {
  // ── GROUP 1: Loader ────────────────────────────────────────────────────────
  group('Adau1701EngineeringLoader', () {
    late Adau1701LoadResult result;

    setUpAll(() => result = Adau1701EngineeringLoader.load());

    // T01
    test('T01 total candidate count is 18', () {
      // 2 MV + 4 gain + 4 mute + 4 delay + 4 peq = 18
      expect(result.candidates.length, 18);
    });

    // T02
    test('T02 gain candidates count = 4', () {
      expect(result.byKind(Adau1701CandidateKind.gain).length, 4);
    });

    // T03
    test('T03 mute candidates count = 4', () {
      expect(result.byKind(Adau1701CandidateKind.mute).length, 4);
    });

    // T04
    test('T04 peq candidates count = 4', () {
      expect(result.byKind(Adau1701CandidateKind.peq).length, 4);
    });

    // T05
    test('T05 delay candidates count = 4', () {
      expect(result.byKind(Adau1701CandidateKind.delay).length, 4);
    });

    // T06
    test('T06 masterVolume candidates count = 2', () {
      expect(result.byKind(Adau1701CandidateKind.masterVolume).length, 2);
    });

    // T07
    test('T07 gain candidates are unblocked', () {
      final gains = result.byKind(Adau1701CandidateKind.gain);
      expect(gains.every((c) => !c.isBlocked), isTrue);
    });

    // T08
    test('T08 masterVolume candidates are unblocked', () {
      final mv = result.byKind(Adau1701CandidateKind.masterVolume);
      expect(mv.every((c) => !c.isBlocked), isTrue);
    });

    // T09
    test('T09 mute candidates are blocked with CAPTURE_WINDOW_REQUIRED', () {
      final mutes = result.byKind(Adau1701CandidateKind.mute);
      expect(mutes.every((c) => c.isBlocked), isTrue);
      expect(
          mutes.every(
              (c) => c.blockReason!.contains('CAPTURE_WINDOW_REQUIRED')),
          isTrue);
    });

    // T10
    test('T10 peq candidates blocked with COEFFICIENT_ORDER_UNKNOWN', () {
      final peqs = result.byKind(Adau1701CandidateKind.peq);
      expect(peqs.every((c) => c.isBlocked), isTrue);
      expect(
          peqs.every(
              (c) => c.blockReason!.contains('COEFFICIENT_ORDER_UNKNOWN')),
          isTrue);
    });

    // T11
    test('T11 delay candidates blocked with CHANNEL_UNCONFIRMED', () {
      final delays = result.byKind(Adau1701CandidateKind.delay);
      expect(delays.every((c) => c.isBlocked), isTrue);
      expect(
          delays.every(
              (c) => c.blockReason!.contains('CHANNEL_UNCONFIRMED')),
          isTrue);
    });

    // T12
    test('T12 version label matches DSP map', () {
      expect(result.version, 'ADAU1701 v0.8 Export14');
    });

    // T13
    test('T13 gain address 0x0084 present', () {
      final c = result.candidates
          .firstWhere((c) => c.addressInt == 0x0084);
      expect(c.kind, Adau1701CandidateKind.gain);
    });

    // T14
    test('T14 gain default value format is 5.23', () {
      final gains = result.byKind(Adau1701CandidateKind.gain);
      expect(
          gains.every((c) => c.valueFormat == Adau1701ValueFormat.fixed523),
          isTrue);
    });

    // T15
    test('T15 gain exportDefaultHex is unity 5.23 (00800000)', () {
      final gains = result.byKind(Adau1701CandidateKind.gain);
      expect(gains.every((c) => c.exportDefaultHex == '00800000'), isTrue);
    });

    // T16
    test('T16 unblocked returns only gain + MV (6 total)', () {
      expect(result.unblocked.length, 6);
    });

    // T17
    test('T17 EEPROM address 0xA0 is not in candidate list', () {
      final eepromInList =
          result.candidates.any((c) => c.addressInt == 0xA0);
      expect(eepromInList, isFalse);
    });
  });

  // ── GROUP 2: Executor Guards ───────────────────────────────────────────────
  group('Adau1701EngineeringExecutor guards', () {
    // T18
    test('T18 G1: null transport → blocked, no write', () async {
      final exec = Adau1701EngineeringExecutor(transport: null);
      final r = await exec.writeWithRestore(_req());
      expect(r.resultStatus, Adau1701CandidateStatus.blocked);
      expect(r.testWasActualWrite, isFalse);
      expect(r.error, contains('G1'));
    });

    // T19
    test('T19 G2: userConfirmed=false → blocked', () async {
      final t = _MockTransport();
      final exec = Adau1701EngineeringExecutor(transport: t);
      final r = await exec.writeWithRestore(_req(userConfirmed: false));
      expect(r.resultStatus, Adau1701CandidateStatus.blocked);
      expect(r.testWasActualWrite, isFalse);
      expect(t.calls, isEmpty);
      expect(r.error, contains('G2'));
    });

    // T20
    test('T20 G3: restoreConfirmed=false → blocked', () async {
      final t = _MockTransport();
      final exec = Adau1701EngineeringExecutor(transport: t);
      final r = await exec.writeWithRestore(_req(restoreConfirmed: false));
      expect(r.resultStatus, Adau1701CandidateStatus.blocked);
      expect(r.testWasActualWrite, isFalse);
      expect(t.calls, isEmpty);
      expect(r.error, contains('G3'));
    });

    // T21
    test('T21 G4: EEPROM address 0xA0 → permanently blocked', () async {
      final t = _MockTransport();
      final exec = Adau1701EngineeringExecutor(transport: t);
      final r = await exec.writeWithRestore(_req(address: 0xA0));
      expect(r.resultStatus, Adau1701CandidateStatus.blocked);
      expect(r.testWasActualWrite, isFalse);
      expect(t.calls, isEmpty);
      expect(r.error, contains('G4'));
      expect(r.error, contains('EEPROM'));
    });

    // T22
    test('T22 G5: isBlocked=true → blocked', () async {
      final t = _MockTransport();
      final exec = Adau1701EngineeringExecutor(transport: t);
      final r = await exec.writeWithRestore(_req(isBlocked: true));
      expect(r.resultStatus, Adau1701CandidateStatus.blocked);
      expect(r.testWasActualWrite, isFalse);
      expect(t.calls, isEmpty);
      expect(r.error, contains('G5'));
    });
  });

  // ── GROUP 3: Executor Write Path ───────────────────────────────────────────
  group('Adau1701EngineeringExecutor write path', () {
    // T23
    test('T23 successful write → passAck', () async {
      final t = _MockTransport();
      final exec = Adau1701EngineeringExecutor(transport: t);
      final r = await exec.writeWithRestore(_req());
      expect(r.resultStatus, Adau1701CandidateStatus.passAck);
      expect(r.testWriteOk, isTrue);
    });

    // T24
    test('T24 testWasActualWrite=true on success', () async {
      final t = _MockTransport();
      final r = await Adau1701EngineeringExecutor(transport: t)
          .writeWithRestore(_req());
      expect(r.testWasActualWrite, isTrue);
    });

    // T25
    test('T25 restoreWasActualWrite=true on success', () async {
      final t = _MockTransport();
      final r = await Adau1701EngineeringExecutor(transport: t)
          .writeWithRestore(_req());
      expect(r.restoreWasActualWrite, isTrue);
    });

    // T26
    test('T26 transport called twice (test + restore)', () async {
      final t = _MockTransport();
      await Adau1701EngineeringExecutor(transport: t).writeWithRestore(_req());
      expect(t.calls.length, 2);
    });

    // T27
    test('T27 test write uses correct address', () async {
      final t = _MockTransport();
      await Adau1701EngineeringExecutor(transport: t)
          .writeWithRestore(_req(address: 0x0085));
      expect(t.calls[0].address, 0x0085);
    });

    // T28
    test('T28 test write encodes 5.23 value correctly (0x00400000)', () async {
      final t = _MockTransport();
      await Adau1701EngineeringExecutor(transport: t)
          .writeWithRestore(_req(testVal: 0x00400000));
      expect(t.calls[0].bytes, [0x00, 0x40, 0x00, 0x00]);
    });

    // T29
    test('T29 restore write uses restore value (0x00800000)', () async {
      final t = _MockTransport();
      await Adau1701EngineeringExecutor(transport: t)
          .writeWithRestore(_req(restoreVal: 0x00800000));
      expect(t.calls[1].bytes, [0x00, 0x80, 0x00, 0x00]);
    });

    // T30
    test('T30 write exception → fail + error message', () async {
      final t = _MockTransport(shouldThrow: true);
      final r = await Adau1701EngineeringExecutor(transport: t)
          .writeWithRestore(_req());
      expect(r.resultStatus, Adau1701CandidateStatus.fail);
      expect(r.error, isNotNull);
      expect(r.testWasActualWrite, isFalse);
    });

    // T31
    test('T31 testWasActualWrite=false on exception', () async {
      final t = _MockTransport(shouldThrow: true);
      final r = await Adau1701EngineeringExecutor(transport: t)
          .writeWithRestore(_req());
      expect(r.testWasActualWrite, isFalse);
    });

    // T32
    test('T32 5.23 unity value 0x00800000 encodes as [0x00,0x80,0x00,0x00]',
        () async {
      final t = _MockTransport();
      await Adau1701EngineeringExecutor(transport: t)
          .writeWithRestore(_req(testVal: 0x00800000));
      expect(t.calls[0].bytes, [0x00, 0x80, 0x00, 0x00]);
    });

    // T33
    test('T33 8.24 unity 0x01000000 is NOT equal to 5.23 unity 0x00800000',
        () {
      const adau1466Unity = 0x01000000;
      const adau1701Unity = 0x00800000;
      expect(adau1466Unity, isNot(equals(adau1701Unity)));
    });

    // T34
    test('T34 raw32 value passes through unmodified', () async {
      final t = _MockTransport();
      await Adau1701EngineeringExecutor(transport: t)
          .writeWithRestore(_req(testVal: 0xDEADBEEF));
      expect(t.calls[0].bytes, [0xDE, 0xAD, 0xBE, 0xEF]);
    });

    // T35
    test('T35 transportDesc is set', () async {
      final t = _MockTransport();
      final r = await Adau1701EngineeringExecutor(transport: t)
          .writeWithRestore(_req());
      expect(r.transportDesc, isNotEmpty);
    });

    // T36
    test('T36 executedAt is set and recent', () async {
      final before = DateTime.now();
      final t = _MockTransport();
      final r = await Adau1701EngineeringExecutor(transport: t)
          .writeWithRestore(_req());
      expect(r.executedAt.isAfter(before.subtract(const Duration(seconds: 1))),
          isTrue);
    });
  });

  // ── GROUP 4: Persistence ───────────────────────────────────────────────────
  group('Adau1701EngineeringPersistence', () {
    setUp(() =>
        SharedPreferences.setMockInitialValues({}));

    // T37
    test('T37 loadCandidates returns null when nothing saved', () async {
      final result = await Adau1701EngineeringPersistence.loadCandidates();
      expect(result, isNull);
    });

    // T38
    test('T38 loadLog returns empty when nothing saved', () async {
      final log = await Adau1701EngineeringPersistence.loadLog();
      expect(log, isEmpty);
    });

    // T39
    test('T39 save and load candidates round-trip preserves count', () async {
      final candidates = Adau1701EngineeringLoader.load().candidates;
      await Adau1701EngineeringPersistence.saveCandidates(candidates);
      final loaded = await Adau1701EngineeringPersistence.loadCandidates();
      expect(loaded, isNotNull);
      expect(loaded!.length, candidates.length);
    });

    // T40
    test('T40 candidate status preserved after round-trip', () async {
      final candidates = Adau1701EngineeringLoader.load().candidates;
      candidates.first.status = Adau1701CandidateStatus.passAck;
      await Adau1701EngineeringPersistence.saveCandidates(candidates);
      final loaded = await Adau1701EngineeringPersistence.loadCandidates();
      expect(loaded!.first.status, Adau1701CandidateStatus.passAck);
    });

    // T41
    test('T41 wasActualWrite=true preserved after round-trip', () async {
      final candidates = Adau1701EngineeringLoader.load().candidates;
      candidates.first.wasActualWrite = true;
      await Adau1701EngineeringPersistence.saveCandidates(candidates);
      final loaded = await Adau1701EngineeringPersistence.loadCandidates();
      expect(loaded!.first.wasActualWrite, isTrue);
    });

    // T42
    test('T42 save and load log round-trip', () async {
      final entry = Adau1701EngLogEntry(
        timestamp: DateTime(2026, 7, 13, 12, 0, 0),
        addressInt: 0x0084,
        addressHex: '0x0084',
        label: 'Driver Gain WOO L',
        channelName: 'WOO L',
        kind: 'gain',
        testValueHex: '00400000',
        restoreValueHex: '00800000',
        valueFormat: 'fixed523',
        testWasActualWrite: true,
        restoreWasActualWrite: true,
        resultStatus: 'passAck',
        version: 'ADAU1701 v0.8 Export14',
      );
      await Adau1701EngineeringPersistence.saveLog([entry]);
      final loaded = await Adau1701EngineeringPersistence.loadLog();
      expect(loaded.length, 1);
      expect(loaded.first.addressInt, 0x0084);
      expect(loaded.first.resultStatus, 'passAck');
    });

    // T43
    test('T43 log timestamp preserved after round-trip', () async {
      final ts = DateTime(2026, 7, 13, 9, 30, 0);
      final entry = Adau1701EngLogEntry(
        timestamp: ts,
        addressInt: 0x0085,
        addressHex: '0x0085',
        label: 'test',
        channelName: '',
        kind: 'gain',
        testValueHex: '00400000',
        restoreValueHex: '00800000',
        valueFormat: 'fixed523',
        testWasActualWrite: true,
        restoreWasActualWrite: true,
        resultStatus: 'passAck',
        version: 'ADAU1701 v0.8 Export14',
      );
      await Adau1701EngineeringPersistence.saveLog([entry]);
      final loaded = await Adau1701EngineeringPersistence.loadLog();
      expect(loaded.first.timestamp, ts);
    });

    // T44
    test('T44 clearAll removes candidates and log', () async {
      final candidates = Adau1701EngineeringLoader.load().candidates;
      await Adau1701EngineeringPersistence.saveCandidates(candidates);
      await Adau1701EngineeringPersistence.saveLog([
        Adau1701EngLogEntry(
          timestamp: DateTime.now(),
          addressInt: 0x84,
          addressHex: '0x0084',
          label: 'x',
          channelName: '',
          kind: 'gain',
          testValueHex: '00400000',
          restoreValueHex: '00800000',
          valueFormat: 'fixed523',
          testWasActualWrite: true,
          restoreWasActualWrite: true,
          resultStatus: 'passAck',
          version: 'ADAU1701 v0.8 Export14',
        ),
      ]);
      await Adau1701EngineeringPersistence.clearAll();
      expect(await Adau1701EngineeringPersistence.loadCandidates(), isNull);
      expect(await Adau1701EngineeringPersistence.loadLog(), isEmpty);
    });

    // T45
    test('T45 corrupt candidates data returns null gracefully', () async {
      SharedPreferences.setMockInitialValues(
          {'tunai_adau1701_eng_candidates_v1': 'not json {'});
      final result = await Adau1701EngineeringPersistence.loadCandidates();
      expect(result, isNull);
    });
  });

  // ── GROUP 5: Model ────────────────────────────────────────────────────────
  group('Adau1701AddressCandidate model', () {
    // T46
    test('T46 toJson/fromJson round-trip preserves all fields', () {
      final c = Adau1701AddressCandidate(
        id: 'gain_0x0084',
        addressInt: 0x0084,
        addressHex: '0x0084',
        label: 'Driver Gain WOO L',
        channelName: 'WOO L',
        kind: Adau1701CandidateKind.gain,
        isBlocked: false,
        exportDefaultHex: '00800000',
        status: Adau1701CandidateStatus.passAck,
        testValueHex: '00400000',
        restoreValueHex: '00800000',
        valueFormat: Adau1701ValueFormat.fixed523,
        wasActualWrite: true,
        measurementNote: 'sounds good',
        operatorNote: 'confirmed',
      );
      final j = c.toJson();
      final c2 = Adau1701AddressCandidate.fromJson(j);
      expect(c2.id, c.id);
      expect(c2.addressInt, c.addressInt);
      expect(c2.status, c.status);
      expect(c2.wasActualWrite, c.wasActualWrite);
      expect(c2.measurementNote, c.measurementNote);
      expect(c2.valueFormat, c.valueFormat);
    });

    // T47
    test('T47 status transitions: candidate → passAck → verified', () {
      final c = Adau1701AddressCandidate(
        id: 'test',
        addressInt: 0x84,
        addressHex: '0x0084',
        label: 'test',
        channelName: '',
        kind: Adau1701CandidateKind.gain,
        isBlocked: false,
        exportDefaultHex: '00800000',
        status: Adau1701CandidateStatus.candidate,
        testValueHex: '00400000',
        restoreValueHex: '00800000',
        valueFormat: Adau1701ValueFormat.fixed523,
      );
      expect(c.status, Adau1701CandidateStatus.candidate);
      c.status = Adau1701CandidateStatus.passAck;
      expect(c.status, Adau1701CandidateStatus.passAck);
      c.wasActualWrite = true;
      c.status = Adau1701CandidateStatus.verified;
      expect(c.status, Adau1701CandidateStatus.verified);
    });

    // T48
    test('T48 blocked candidate has isBlocked=true and blockReason set', () {
      final result = Adau1701EngineeringLoader.load();
      final mutes = result.byKind(Adau1701CandidateKind.mute);
      expect(mutes.first.isBlocked, isTrue);
      expect(mutes.first.blockReason, isNotNull);
      expect(mutes.first.blockReason, isNotEmpty);
    });
  });

  // ── GROUP 6: Safety & Policy ───────────────────────────────────────────────
  group('Safety and policy', () {
    // T49
    test(
        'T49 VERIFIED requires wasActualWrite=true — executor never sets VERIFIED automatically',
        () async {
      final t = _MockTransport();
      final r = await Adau1701EngineeringExecutor(transport: t)
          .writeWithRestore(_req());
      // passAck is the maximum the executor produces; VERIFIED is never automatic
      expect(r.resultStatus, isNot(Adau1701CandidateStatus.verified));
      expect(r.resultStatus, Adau1701CandidateStatus.passAck);
    });
  });
}
