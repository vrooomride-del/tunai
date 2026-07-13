// ── TUNAI Consumer — ADAU1701 Engineering Console Tests ──────────────────────
// Covers: loader (both firmware maps), executor guards G1–G8,
// write path, persistence, model round-trip, value formats,
// firmware confirmation, write-shape gating, and policy.

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

  _MockTransport({this.shouldThrow = false});

  @override
  Future<void> writeParameter(int address, List<int> bytes4) async {
    if (shouldThrow) throw Exception('BLE error');
    calls.add((address: address, bytes: bytes4));
  }

  @override
  Future<List<int>?> readParameter(int address) async => null;

  @override
  Future<bool> detectDevice() async => true;

  @override
  void dispose() {}
}

// ── Helper — default passing request ─────────────────────────────────────────

Adau1701EngWriteRequest _req({
  String id = 'mv_0x0005',
  int address = 0x0005,
  int testVal = 0x00400000,
  int restoreVal = 0x00800000,
  bool userConfirmed = true,
  bool restoreConfirmed = true,
  bool isBlocked = false,
  Adau1701WriteShape writeShape = Adau1701WriteShape.singleWordParameter,
  bool firmwareConfirmed = true,
  bool formatConfirmed = true,
  Adau1701ValueFormat valueFormat = Adau1701ValueFormat.fixed523,
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
      writeShape: writeShape,
      firmwareConfirmed: firmwareConfirmed,
      formatConfirmed: formatConfirmed,
      valueFormat: valueFormat,
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── GROUP 1: Loader — Export14 ─────────────────────────────────────────────
  group('Adau1701EngineeringLoader — Export14', () {
    late Adau1701LoadResult result;
    setUpAll(() => result = Adau1701EngineeringLoader.load());

    // T01
    test('T01 total candidate count is 34 (18 Export14 + 16 Adapter)', () {
      // MV 2 + Gain 4 + Mute 4 + Delay 4 + PEQ 4 = 18 Export14
      // Adapter: gain 2 + ch-mute 2 + out-mute 4 + XO 8 = 16
      expect(result.candidates.length, 34);
    });

    // T02
    test('T02 Export14 gain count = 4', () {
      expect(
          result
              .bySource(Adau1701FirmwareSource.export14SingleWord)
              .where((c) => c.kind == Adau1701CandidateKind.gain)
              .length,
          4);
    });

    // T03
    test('T03 Export14 mute count = 4', () {
      expect(
          result
              .bySource(Adau1701FirmwareSource.export14SingleWord)
              .where((c) => c.kind == Adau1701CandidateKind.mute)
              .length,
          4);
    });

    // T04
    test('T04 Export14 PEQ count = 4', () {
      expect(
          result
              .bySource(Adau1701FirmwareSource.export14SingleWord)
              .where((c) => c.kind == Adau1701CandidateKind.peq)
              .length,
          4);
    });

    // T05
    test('T05 Export14 delay count = 4', () {
      expect(
          result
              .bySource(Adau1701FirmwareSource.export14SingleWord)
              .where((c) => c.kind == Adau1701CandidateKind.delay)
              .length,
          4);
    });

    // T06
    test('T06 masterVolume count = 2', () {
      expect(result.byKind(Adau1701CandidateKind.masterVolume).length, 2);
    });

    // T07
    test('T07 gain candidates (Export14) are not isBlocked', () {
      final gains = result
          .bySource(Adau1701FirmwareSource.export14SingleWord)
          .where((c) => c.kind == Adau1701CandidateKind.gain);
      expect(gains.every((c) => !c.isBlocked), isTrue);
    });

    // T08
    test('T08 MV candidates are unblocked and firmwareConfirmed=true', () {
      final mv = result.byKind(Adau1701CandidateKind.masterVolume);
      expect(mv.every((c) => !c.isBlocked), isTrue);
      expect(mv.every((c) => c.firmwareConfirmed), isTrue);
    });

    // T09
    test('T09 Export14 mute blocked with CAPTURE_WINDOW_REQUIRED', () {
      final mutes = result
          .bySource(Adau1701FirmwareSource.export14SingleWord)
          .where((c) => c.kind == Adau1701CandidateKind.mute);
      expect(mutes.every((c) => c.isBlocked), isTrue);
      expect(
          mutes.every(
              (c) => c.blockReason!.contains('CAPTURE_WINDOW_REQUIRED')),
          isTrue);
    });

    // T10
    test('T10 Export14 PEQ blocked with COEFFICIENT_ORDER_UNKNOWN', () {
      final peqs = result
          .bySource(Adau1701FirmwareSource.export14SingleWord)
          .where((c) => c.kind == Adau1701CandidateKind.peq);
      expect(peqs.every((c) => c.isBlocked), isTrue);
      expect(
          peqs.every(
              (c) => c.blockReason!.contains('COEFFICIENT_ORDER_UNKNOWN')),
          isTrue);
    });

    // T11
    test('T11 Export14 delay blocked with CHANNEL_UNCONFIRMED', () {
      final delays = result
          .bySource(Adau1701FirmwareSource.export14SingleWord)
          .where((c) => c.kind == Adau1701CandidateKind.delay);
      expect(delays.every((c) => c.isBlocked), isTrue);
      expect(
          delays.every(
              (c) => c.blockReason!.contains('CHANNEL_UNCONFIRMED')),
          isTrue);
    });

    // T12
    test('T12 version string contains Export14', () {
      expect(result.version, contains('Export14'));
    });

    // T13
    test('T13 gain address 0x0084 present with Export14 source', () {
      final c = result.candidates
          .firstWhere((c) => c.addressInt == 0x0084);
      expect(c.kind, Adau1701CandidateKind.gain);
      expect(c.firmwareSource, Adau1701FirmwareSource.export14SingleWord);
    });

    // T14
    test('T14 MV has formatConfirmed=true (production-verified)', () {
      final mv = result.byKind(Adau1701CandidateKind.masterVolume);
      expect(mv.every((c) => c.formatConfirmed), isTrue);
    });

    // T15
    test('T15 Export14 gain exportDefaultHex is 5.23 unity', () {
      final gains = result
          .bySource(Adau1701FirmwareSource.export14SingleWord)
          .where((c) => c.kind == Adau1701CandidateKind.gain);
      expect(gains.every((c) => c.exportDefaultHex == '00800000'), isTrue);
    });

    // T16
    test('T16 unblocked (by isBlocked flag) = 6 (MV + Export14 gain)', () {
      expect(result.unblocked.length, 6);
    });

    // T17
    test('T17 EEPROM address 0xA0 is not in candidate list', () {
      expect(result.candidates.any((c) => c.addressInt == 0xA0), isFalse);
    });
  });

  // ── GROUP 2: Loader — Adapter (2026-07-04) ─────────────────────────────────
  group('Adau1701EngineeringLoader — Adapter-2026', () {
    late Adau1701LoadResult result;
    setUpAll(() => result = Adau1701EngineeringLoader.load());

    // T18
    test('T18 adapter candidate count = 16', () {
      expect(
          result
              .bySource(Adau1701FirmwareSource.recompiled20260704Adapter)
              .length,
          16);
    });

    // T19
    test('T19 adapter gain addr 7 present with 5-word write shape', () {
      final c = result.candidates
          .firstWhere((c) => c.addressInt == 7 && c.firmwareSource == Adau1701FirmwareSource.recompiled20260704Adapter);
      expect(c.writeShape, Adau1701WriteShape.fiveWordCoefficientBlock);
      expect(c.isBlocked, isTrue);
    });

    // T20
    test('T20 adapter gain addr 6 present', () {
      final c = result.candidates
          .firstWhere((c) => c.addressInt == 6 && c.firmwareSource == Adau1701FirmwareSource.recompiled20260704Adapter);
      expect(c.kind, Adau1701CandidateKind.gain);
    });

    // T21
    test('T21 adapter candidates all blocked with WRITE_SHAPE_NOT_SUPPORTED', () {
      final adapter =
          result.bySource(Adau1701FirmwareSource.recompiled20260704Adapter);
      expect(adapter.every((c) => c.isBlocked), isTrue);
      expect(
          adapter.every(
              (c) => c.blockReason!.contains('WRITE_SHAPE_NOT_SUPPORTED')),
          isTrue);
    });

    // T22
    test('T22 adapter XO block count = 8', () {
      final xo = result
          .bySource(Adau1701FirmwareSource.recompiled20260704Adapter)
          .where((c) => c.kind == Adau1701CandidateKind.crossover);
      expect(xo.length, 8);
    });

    // T23
    test('T23 adapter all have fiveWordCoefficientBlock write shape', () {
      final adapter =
          result.bySource(Adau1701FirmwareSource.recompiled20260704Adapter);
      expect(
          adapter.every(
              (c) => c.writeShape == Adau1701WriteShape.fiveWordCoefficientBlock),
          isTrue);
    });

    // T24
    test('T24 XO block addrs include 16, 21, 26, 31, 36, 41, 46, 51', () {
      final xoAddrs = result
          .bySource(Adau1701FirmwareSource.recompiled20260704Adapter)
          .where((c) => c.kind == Adau1701CandidateKind.crossover)
          .map((c) => c.addressInt)
          .toSet();
      for (final a in [16, 21, 26, 31, 36, 41, 46, 51]) {
        expect(xoAddrs.contains(a), isTrue, reason: 'addr $a missing');
      }
    });

    // T25
    test('T25 Export14 gain firmwareConfirmed=false by default', () {
      final gains = result
          .bySource(Adau1701FirmwareSource.export14SingleWord)
          .where((c) => c.kind == Adau1701CandidateKind.gain);
      expect(gains.every((c) => !c.firmwareConfirmed), isTrue);
    });

    // T26
    test('T26 writeReady = 2 (MV only by default)', () {
      expect(result.writeReady.length, 2);
      expect(
          result.writeReady.every(
              (c) => c.kind == Adau1701CandidateKind.masterVolume),
          isTrue);
    });
  });

  // ── GROUP 3: Executor — Guards G1–G5 ──────────────────────────────────────
  group('Executor guards G1–G5', () {
    // T27
    test('T27 G1: null transport → blocked', () async {
      const exec = Adau1701EngineeringExecutor(transport: null);
      final r = await exec.writeWithRestore(_req());
      expect(r.resultStatus, Adau1701CandidateStatus.blocked);
      expect(r.testWasActualWrite, isFalse);
      expect(r.error, contains('G1'));
    });

    // T28
    test('T28 G2: userConfirmed=false → blocked, no write', () async {
      final t = _MockTransport();
      final r = await Adau1701EngineeringExecutor(transport: t)
          .writeWithRestore(_req(userConfirmed: false));
      expect(r.resultStatus, Adau1701CandidateStatus.blocked);
      expect(t.calls, isEmpty);
      expect(r.error, contains('G2'));
    });

    // T29
    test('T29 G3: restoreConfirmed=false → blocked', () async {
      final t = _MockTransport();
      final r = await Adau1701EngineeringExecutor(transport: t)
          .writeWithRestore(_req(restoreConfirmed: false));
      expect(r.resultStatus, Adau1701CandidateStatus.blocked);
      expect(t.calls, isEmpty);
      expect(r.error, contains('G3'));
    });

    // T30
    test('T30 G4: EEPROM address 0xA0 → blocked with EEPROM in message', () async {
      final t = _MockTransport();
      final r = await Adau1701EngineeringExecutor(transport: t)
          .writeWithRestore(_req(address: 0xA0));
      expect(r.resultStatus, Adau1701CandidateStatus.blocked);
      expect(t.calls, isEmpty);
      expect(r.error, contains('G4'));
      expect(r.error, contains('EEPROM'));
    });

    // T31
    test('T31 G5: isBlocked=true → blocked', () async {
      final t = _MockTransport();
      final r = await Adau1701EngineeringExecutor(transport: t)
          .writeWithRestore(_req(isBlocked: true));
      expect(r.resultStatus, Adau1701CandidateStatus.blocked);
      expect(t.calls, isEmpty);
      expect(r.error, contains('G5'));
    });
  });

  // ── GROUP 4: Executor — Guards G6–G8 (new) ────────────────────────────────
  group('Executor guards G6–G8', () {
    // T32
    test('T32 G6: fiveWordCoefficientBlock → WRITE_SHAPE_NOT_SUPPORTED', () async {
      final t = _MockTransport();
      final r = await Adau1701EngineeringExecutor(transport: t).writeWithRestore(
          _req(writeShape: Adau1701WriteShape.fiveWordCoefficientBlock));
      expect(r.resultStatus, Adau1701CandidateStatus.blocked);
      expect(t.calls, isEmpty);
      expect(r.error, contains('G6'));
      expect(r.error, contains('WRITE_SHAPE_NOT_SUPPORTED'));
    });

    // T33
    test('T33 G6: unsupported write shape → blocked', () async {
      final t = _MockTransport();
      final r = await Adau1701EngineeringExecutor(transport: t)
          .writeWithRestore(_req(writeShape: Adau1701WriteShape.unsupported));
      expect(r.resultStatus, Adau1701CandidateStatus.blocked);
      expect(r.error, contains('G6'));
    });

    // T34
    test('T34 G7: firmwareConfirmed=false → FIRMWARE_SOURCE_NOT_CONFIRMED', () async {
      final t = _MockTransport();
      final r = await Adau1701EngineeringExecutor(transport: t)
          .writeWithRestore(_req(firmwareConfirmed: false));
      expect(r.resultStatus, Adau1701CandidateStatus.blocked);
      expect(t.calls, isEmpty);
      expect(r.error, contains('G7'));
      expect(r.error, contains('FIRMWARE_SOURCE_NOT_CONFIRMED'));
    });

    // T35
    test('T35 G8: valueFormat=unknown → FORMAT_NOT_CONFIRMED', () async {
      final t = _MockTransport();
      final r = await Adau1701EngineeringExecutor(transport: t).writeWithRestore(
          _req(valueFormat: Adau1701ValueFormat.unknown, formatConfirmed: false));
      expect(r.resultStatus, Adau1701CandidateStatus.blocked);
      expect(t.calls, isEmpty);
      expect(r.error, contains('G8'));
      expect(r.error, contains('FORMAT_NOT_CONFIRMED'));
    });

    // T36
    test('T36 G8: formatConfirmed=false even with known format → blocked', () async {
      final t = _MockTransport();
      final r = await Adau1701EngineeringExecutor(transport: t).writeWithRestore(
          _req(valueFormat: Adau1701ValueFormat.fixed523, formatConfirmed: false));
      expect(r.resultStatus, Adau1701CandidateStatus.blocked);
      expect(r.error, contains('G8'));
    });

    // T37
    test('T37 MV passes all guards (firmwareConfirmed=true, formatConfirmed=true)', () async {
      final t = _MockTransport();
      final r = await Adau1701EngineeringExecutor(transport: t).writeWithRestore(_req());
      expect(r.resultStatus, Adau1701CandidateStatus.passAck);
      expect(r.testWasActualWrite, isTrue);
    });
  });

  // ── GROUP 5: Executor — Write Path ────────────────────────────────────────
  group('Executor write path', () {
    // T38
    test('T38 successful write → passAck', () async {
      final t = _MockTransport();
      final r = await Adau1701EngineeringExecutor(transport: t).writeWithRestore(_req());
      expect(r.resultStatus, Adau1701CandidateStatus.passAck);
    });

    // T39
    test('T39 testWasActualWrite=true on success', () async {
      final t = _MockTransport();
      final r = await Adau1701EngineeringExecutor(transport: t).writeWithRestore(_req());
      expect(r.testWasActualWrite, isTrue);
    });

    // T40
    test('T40 restoreWasActualWrite=true on success', () async {
      final t = _MockTransport();
      final r = await Adau1701EngineeringExecutor(transport: t).writeWithRestore(_req());
      expect(r.restoreWasActualWrite, isTrue);
    });

    // T41
    test('T41 transport called twice (test + restore)', () async {
      final t = _MockTransport();
      await Adau1701EngineeringExecutor(transport: t).writeWithRestore(_req());
      expect(t.calls.length, 2);
    });

    // T42
    test('T42 test write uses correct address', () async {
      final t = _MockTransport();
      await Adau1701EngineeringExecutor(transport: t)
          .writeWithRestore(_req(address: 0x0085));
      expect(t.calls[0].address, 0x0085);
    });

    // T43
    test('T43 5.23 value 0x00400000 encodes as [0x00, 0x40, 0x00, 0x00]', () async {
      final t = _MockTransport();
      await Adau1701EngineeringExecutor(transport: t)
          .writeWithRestore(_req(testVal: 0x00400000));
      expect(t.calls[0].bytes, [0x00, 0x40, 0x00, 0x00]);
    });

    // T44
    test('T44 5.23 unity 0x00800000 encodes as [0x00, 0x80, 0x00, 0x00]', () async {
      final t = _MockTransport();
      await Adau1701EngineeringExecutor(transport: t)
          .writeWithRestore(_req(testVal: 0x00800000));
      expect(t.calls[0].bytes, [0x00, 0x80, 0x00, 0x00]);
    });

    // T45
    test('T45 8.24 unity differs from 5.23 unity', () {
      const adau1466 = 0x01000000;
      const adau1701 = 0x00800000;
      expect(adau1466, isNot(equals(adau1701)));
    });

    // T46
    test('T46 restore uses restore value bytes', () async {
      final t = _MockTransport();
      await Adau1701EngineeringExecutor(transport: t)
          .writeWithRestore(_req(restoreVal: 0x00800000));
      expect(t.calls[1].bytes, [0x00, 0x80, 0x00, 0x00]);
    });

    // T47
    test('T47 raw32 0xDEADBEEF passes through unmodified', () async {
      final t = _MockTransport();
      await Adau1701EngineeringExecutor(transport: t)
          .writeWithRestore(_req(testVal: 0xDEADBEEF));
      expect(t.calls[0].bytes, [0xDE, 0xAD, 0xBE, 0xEF]);
    });

    // T48
    test('T48 exception → fail + error message', () async {
      final t = _MockTransport(shouldThrow: true);
      final r = await Adau1701EngineeringExecutor(transport: t).writeWithRestore(_req());
      expect(r.resultStatus, Adau1701CandidateStatus.fail);
      expect(r.error, isNotNull);
      expect(r.testWasActualWrite, isFalse);
    });

    // T49
    test('T49 executor NEVER sets VERIFIED — max is passAck', () async {
      final t = _MockTransport();
      final r = await Adau1701EngineeringExecutor(transport: t).writeWithRestore(_req());
      expect(r.resultStatus, isNot(Adau1701CandidateStatus.verified));
      expect(r.resultStatus, Adau1701CandidateStatus.passAck);
    });
  });

  // ── GROUP 6: Persistence ──────────────────────────────────────────────────
  group('Persistence', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    // T50
    test('T50 loadCandidates returns null when nothing saved', () async {
      expect(await Adau1701EngineeringPersistence.loadCandidates(), isNull);
    });

    // T51
    test('T51 loadLog returns empty when nothing saved', () async {
      expect(await Adau1701EngineeringPersistence.loadLog(), isEmpty);
    });

    // T52
    test('T52 save and load candidates round-trip preserves count', () async {
      final candidates = Adau1701EngineeringLoader.load().candidates;
      await Adau1701EngineeringPersistence.saveCandidates(candidates);
      final loaded = await Adau1701EngineeringPersistence.loadCandidates();
      expect(loaded!.length, candidates.length);
    });

    // T53
    test('T53 firmwareConfirmed=true persists through round-trip', () async {
      final candidates = Adau1701EngineeringLoader.load().candidates;
      candidates.first.firmwareConfirmed = true;
      await Adau1701EngineeringPersistence.saveCandidates(candidates);
      final loaded = await Adau1701EngineeringPersistence.loadCandidates();
      expect(loaded!.first.firmwareConfirmed, isTrue);
    });

    // T54
    test('T54 formatConfirmed=true persists through round-trip', () async {
      final candidates = Adau1701EngineeringLoader.load().candidates;
      candidates.first.formatConfirmed = true;
      await Adau1701EngineeringPersistence.saveCandidates(candidates);
      final loaded = await Adau1701EngineeringPersistence.loadCandidates();
      expect(loaded!.first.formatConfirmed, isTrue);
    });

    // T55
    test('T55 wasActualWrite=true persists', () async {
      final candidates = Adau1701EngineeringLoader.load().candidates;
      candidates.first.wasActualWrite = true;
      await Adau1701EngineeringPersistence.saveCandidates(candidates);
      final loaded = await Adau1701EngineeringPersistence.loadCandidates();
      expect(loaded!.first.wasActualWrite, isTrue);
    });

    // T56
    test('T56 log round-trip with firmware source and write shape', () async {
      final entry = Adau1701EngLogEntry(
        timestamp: DateTime(2026, 7, 13, 12, 0, 0),
        addressInt: 0x0005,
        addressHex: '0x0005',
        label: 'Master Volume MV L',
        channelName: 'MV L',
        kind: 'masterVolume',
        firmwareSource: 'export14SingleWord',
        writeShape: 'singleWordParameter',
        testValueHex: '00400000',
        restoreValueHex: '00800000',
        valueFormat: 'fixed523',
        formatConfirmed: true,
        testWasActualWrite: true,
        restoreWasActualWrite: true,
        resultStatus: 'passAck',
        version: 'ADAU1701 v0.8 Export14 | Adapter-2026-07-04',
      );
      await Adau1701EngineeringPersistence.saveLog([entry]);
      final loaded = await Adau1701EngineeringPersistence.loadLog();
      expect(loaded.first.firmwareSource, 'export14SingleWord');
      expect(loaded.first.writeShape, 'singleWordParameter');
      expect(loaded.first.formatConfirmed, isTrue);
    });

    // T57
    test('T57 clearAll removes candidates and log', () async {
      final candidates = Adau1701EngineeringLoader.load().candidates;
      await Adau1701EngineeringPersistence.saveCandidates(candidates);
      await Adau1701EngineeringPersistence.clearAll();
      expect(await Adau1701EngineeringPersistence.loadCandidates(), isNull);
      expect(await Adau1701EngineeringPersistence.loadLog(), isEmpty);
    });

    // T58
    test('T58 corrupt data returns null gracefully', () async {
      SharedPreferences.setMockInitialValues(
          {'tunai_adau1701_eng_candidates_v1': '{{invalid'});
      expect(await Adau1701EngineeringPersistence.loadCandidates(), isNull);
    });
  });

  // ── GROUP 7: Model ────────────────────────────────────────────────────────
  group('Model', () {
    // T59
    test('T59 toJson/fromJson round-trip preserves firmware source & write shape', () {
      final c = Adau1701AddressCandidate(
        id: 'mv_0x0005',
        addressInt: 0x0005,
        addressHex: '0x0005',
        label: 'Master Volume MV L',
        channelName: 'MV L',
        kind: Adau1701CandidateKind.masterVolume,
        firmwareSource: Adau1701FirmwareSource.export14SingleWord,
        writeShape: Adau1701WriteShape.singleWordParameter,
        isBlocked: false,
        exportDefaultHex: '00800000',
        status: Adau1701CandidateStatus.passAck,
        testValueHex: '00400000',
        restoreValueHex: '00800000',
        valueFormat: Adau1701ValueFormat.fixed523,
        firmwareConfirmed: true,
        formatConfirmed: true,
        wasActualWrite: true,
      );
      final c2 = Adau1701AddressCandidate.fromJson(c.toJson());
      expect(c2.firmwareSource, Adau1701FirmwareSource.export14SingleWord);
      expect(c2.writeShape, Adau1701WriteShape.singleWordParameter);
      expect(c2.firmwareConfirmed, isTrue);
      expect(c2.formatConfirmed, isTrue);
    });

    // T60
    test('T60 fromJson handles unknown firmwareSource gracefully', () {
      final j = {
        'id': 'x',
        'addressInt': 0,
        'addressHex': '0x0000',
        'label': 'x',
        'kind': 'unknown',
        'firmwareSource': 'nonexistent_source',
        'writeShape': 'singleWordParameter',
        'isBlocked': false,
        'exportDefaultHex': '00000000',
        'status': 'unknown',
        'testValueHex': '00000000',
        'restoreValueHex': '00000000',
        'valueFormat': 'unknown',
      };
      final c = Adau1701AddressCandidate.fromJson(j);
      expect(c.firmwareSource, Adau1701FirmwareSource.unknown);
    });

    // T61
    test('T61 unknown valueFormat default prevents execution', () async {
      final t = _MockTransport();
      final r = await Adau1701EngineeringExecutor(transport: t).writeWithRestore(
          _req(valueFormat: Adau1701ValueFormat.unknown, formatConfirmed: true));
      expect(r.resultStatus, Adau1701CandidateStatus.blocked);
      expect(r.error, contains('G8'));
    });

    // T62
    test('T62 adapter blocked candidate has 5-word write shape in model', () {
      final result = Adau1701EngineeringLoader.load();
      final adpGain = result.candidates
          .firstWhere((c) => c.addressInt == 7 && c.firmwareSource == Adau1701FirmwareSource.recompiled20260704Adapter);
      expect(adpGain.writeShape, Adau1701WriteShape.fiveWordCoefficientBlock);
      expect(adpGain.isBlocked, isTrue);
    });

    // T63
    test('T63 crossover kind present in loader output', () {
      final result = Adau1701EngineeringLoader.load();
      expect(result.byKind(Adau1701CandidateKind.crossover).isNotEmpty, isTrue);
    });
  });

  // ── GROUP 8: Policy ───────────────────────────────────────────────────────
  group('Policy', () {
    // T64
    test('T64 adapter gain requires manual 5-word path — single-word executor blocks it', () async {
      final t = _MockTransport();
      // Try to pass adapter gain addr 7 through single-word executor
      final r = await Adau1701EngineeringExecutor(transport: t).writeWithRestore(_req(
        address: 7,
        writeShape: Adau1701WriteShape.fiveWordCoefficientBlock,
        firmwareConfirmed: true,
        formatConfirmed: true,
      ));
      expect(r.resultStatus, Adau1701CandidateStatus.blocked);
      expect(r.error, contains('WRITE_SHAPE_NOT_SUPPORTED'));
      expect(t.calls, isEmpty);
    });

    // T65
    test('T65 export14 gain is writable when all conditions met', () async {
      final t = _MockTransport();
      final r = await Adau1701EngineeringExecutor(transport: t).writeWithRestore(_req(
        id: 'gain_0x0084',
        address: 0x0084,
        writeShape: Adau1701WriteShape.singleWordParameter,
        firmwareConfirmed: true,
        formatConfirmed: true,
        valueFormat: Adau1701ValueFormat.fixed523,
      ));
      expect(r.resultStatus, Adau1701CandidateStatus.passAck);
      expect(t.calls.length, 2);
    });

    // T66
    test('T66 export14 gain blocked if firmwareConfirmed=false', () async {
      final t = _MockTransport();
      final r = await Adau1701EngineeringExecutor(transport: t).writeWithRestore(_req(
        id: 'gain_0x0084',
        address: 0x0084,
        firmwareConfirmed: false,
      ));
      expect(r.resultStatus, Adau1701CandidateStatus.blocked);
      expect(t.calls, isEmpty);
    });
  });
}
