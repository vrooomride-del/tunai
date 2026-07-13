// ── TUNAI Consumer — ADAU1701 Engineering Verification Console ───────────────
// Hidden engineering tool inside the PIN-protected Factory screen.
// NOT part of normal consumer UX (CONNECT/ROOM/TUNE/LISTEN/MORE tabs).
//
// ABSOLUTE RESTRICTIONS:
//   - No EEPROM. No Selfboot. No WriteAll. No full profile deployment.
//   - Every write requires: user confirm + restore confirm + firmware confirm + format confirm.
//   - ACK alone = PASS-ACK, not VERIFIED.
//   - VERIFIED = operator manual mark only, requires wasActualWrite AND formatConfirmed.
//   - 5-word coefficient-block candidates (Adapter-2026) are display-only.
//   - detectDevice() returns true unconditionally — does NOT prove firmware identity.
//     Operator must independently verify firmware before confirming.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/dsp/transport/dsp_transport_provider.dart';
import '../../core/adau1701_engineering_candidate.dart';
import '../../core/adau1701_engineering_loader.dart';
import '../../core/adau1701_engineering_executor.dart';
import '../../core/adau1701_engineering_persistence.dart';

class Adau1701EngineeringConsole extends ConsumerStatefulWidget {
  const Adau1701EngineeringConsole({super.key});

  @override
  ConsumerState<Adau1701EngineeringConsole> createState() =>
      _ConsoleState();
}

class _ConsoleState extends ConsumerState<Adau1701EngineeringConsole> {
  late Adau1701LoadResult _loadResult;
  late List<Adau1701AddressCandidate> _candidates;
  List<Adau1701EngLogEntry> _log = [];

  int? _selectedIndex;
  bool _userConfirmed = false;
  bool _restoreConfirmed = false;
  bool _executing = false;
  Adau1701EngWriteResult? _lastResult;

  final _testCtrl = TextEditingController();
  final _restoreCtrl = TextEditingController();
  final _measCtrl = TextEditingController();
  final _opNoteCtrl = TextEditingController();

  Adau1701CandidateKind? _kindFilter;
  Adau1701FirmwareSource? _sourceFilter;

  @override
  void initState() {
    super.initState();
    _loadResult = Adau1701EngineeringLoader.load();
    _candidates = List.from(_loadResult.candidates);
    _loadPersisted();
  }

  @override
  void dispose() {
    _testCtrl.dispose();
    _restoreCtrl.dispose();
    _measCtrl.dispose();
    _opNoteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPersisted() async {
    final saved = await Adau1701EngineeringPersistence.loadCandidates();
    final savedLog = await Adau1701EngineeringPersistence.loadLog();
    if (!mounted) return;
    setState(() {
      if (saved != null && saved.length == _candidates.length) {
        for (var i = 0; i < _candidates.length; i++) {
          final s = saved[i];
          if (s.id == _candidates[i].id) {
            _candidates[i].status = s.status;
            _candidates[i].wasActualWrite = s.wasActualWrite;
            _candidates[i].testValueHex = s.testValueHex;
            _candidates[i].restoreValueHex = s.restoreValueHex;
            _candidates[i].valueFormat = s.valueFormat;
            _candidates[i].firmwareConfirmed = s.firmwareConfirmed;
            _candidates[i].formatConfirmed = s.formatConfirmed;
            _candidates[i].lastError = s.lastError;
            _candidates[i].measurementNote = s.measurementNote;
            _candidates[i].operatorNote = s.operatorNote;
            _candidates[i].executedAt = s.executedAt;
          }
        }
      }
      _log = savedLog;
    });
  }

  Future<void> _persist() async {
    await Adau1701EngineeringPersistence.saveCandidates(_candidates);
    await Adau1701EngineeringPersistence.saveLog(_log);
  }

  List<Adau1701AddressCandidate> get _filtered {
    return _candidates.where((c) {
      if (_kindFilter != null && c.kind != _kindFilter) return false;
      if (_sourceFilter != null && c.firmwareSource != _sourceFilter) return false;
      return true;
    }).toList();
  }

  Adau1701AddressCandidate? get _selected =>
      _selectedIndex != null ? _candidates[_selectedIndex!] : null;

  void _select(int gi) {
    final c = _candidates[gi];
    setState(() {
      _selectedIndex = gi;
      _userConfirmed = false;
      _restoreConfirmed = false;
      _lastResult = null;
      _testCtrl.text = c.testValueHex;
      _restoreCtrl.text = c.restoreValueHex;
      _measCtrl.text = c.measurementNote ?? '';
      _opNoteCtrl.text = c.operatorNote ?? '';
    });
  }

  bool get _canExecute {
    final c = _selected;
    if (c == null || c.isBlocked || _executing) return false;
    if (!_userConfirmed || !_restoreConfirmed) return false;
    if (c.writeShape != Adau1701WriteShape.singleWordParameter) return false;
    if (!c.firmwareConfirmed) return false;
    if (c.valueFormat == Adau1701ValueFormat.unknown || !c.formatConfirmed) return false;
    return true;
  }

  bool get _canMarkVerified {
    final c = _selected;
    if (c == null) return false;
    return c.wasActualWrite && c.formatConfirmed;
  }

  int _parseHex(String hex) {
    final clean = hex.trim().replaceAll('0x', '').replaceAll(' ', '');
    if (clean.isEmpty) return 0;
    final s = clean.length > 8 ? clean.substring(clean.length - 8) : clean.padLeft(8, '0');
    return int.tryParse(s, radix: 16) ?? 0;
  }

  Future<void> _execute() async {
    final c = _selected;
    if (c == null || !_canExecute) return;

    final transport = ref.read(dspTransportProvider);
    c.testValueHex = _testCtrl.text.trim();
    c.restoreValueHex = _restoreCtrl.text.trim();

    final req = Adau1701EngWriteRequest(
      id: c.id,
      addressInt: c.addressInt,
      label: c.label,
      testValue32: _parseHex(c.testValueHex),
      restoreValue32: _parseHex(c.restoreValueHex),
      userConfirmed: _userConfirmed,
      restoreValueConfirmed: _restoreConfirmed,
      isBlocked: c.isBlocked,
      writeShape: c.writeShape,
      firmwareConfirmed: c.firmwareConfirmed,
      formatConfirmed: c.formatConfirmed,
      valueFormat: c.valueFormat,
    );

    setState(() => _executing = true);
    final result =
        await Adau1701EngineeringExecutor(transport: transport).writeWithRestore(req);

    final entry = Adau1701EngLogEntry(
      timestamp: result.executedAt,
      addressInt: c.addressInt,
      addressHex: c.addressHex,
      label: c.label,
      channelName: c.channelName,
      kind: c.kind.name,
      firmwareSource: c.firmwareSource.name,
      writeShape: c.writeShape.name,
      testValueHex: c.testValueHex,
      restoreValueHex: c.restoreValueHex,
      valueFormat: c.valueFormat.name,
      formatConfirmed: c.formatConfirmed,
      testWasActualWrite: result.testWasActualWrite,
      restoreWasActualWrite: result.restoreWasActualWrite,
      resultStatus: result.resultStatus.name,
      error: result.error,
      measurementNote:
          _measCtrl.text.trim().isEmpty ? null : _measCtrl.text.trim(),
      operatorNote:
          _opNoteCtrl.text.trim().isEmpty ? null : _opNoteCtrl.text.trim(),
      version: _loadResult.version,
    );

    setState(() {
      c.status = result.resultStatus;
      c.wasActualWrite = result.testWasActualWrite;
      c.lastError = result.error;
      c.executedAt = result.executedAt;
      _executing = false;
      _lastResult = result;
      _log = [entry, ..._log.take(49)];
      _userConfirmed = false;
      _restoreConfirmed = false;
    });
    await _persist();
  }

  void _markVerified() {
    final c = _selected;
    if (c == null || !_canMarkVerified) return;
    setState(() {
      c.status = Adau1701CandidateStatus.verified;
      if (_opNoteCtrl.text.trim().isNotEmpty) c.operatorNote = _opNoteCtrl.text.trim();
    });
    _persist();
  }

  void _markNeedsMeasurement() {
    final c = _selected;
    if (c == null) return;
    setState(() => c.status = Adau1701CandidateStatus.needsMeasurement);
    _persist();
  }

  void _markRejected() {
    final c = _selected;
    if (c == null) return;
    setState(() => c.status = Adau1701CandidateStatus.rejected);
    _persist();
  }

  Color _statusColor(Adau1701CandidateStatus s) => switch (s) {
        Adau1701CandidateStatus.verified => const Color(0xFF4CAF50),
        Adau1701CandidateStatus.passAck => const Color(0xFF8BC34A),
        Adau1701CandidateStatus.needsMeasurement => const Color(0xFFFF9800),
        Adau1701CandidateStatus.fail => const Color(0xFFF44336),
        Adau1701CandidateStatus.rejected => const Color(0xFF9E9E9E),
        Adau1701CandidateStatus.blocked => const Color(0xFF5C3317),
        _ => const Color(0xFF444444),
      };

  Color _srcColor(Adau1701FirmwareSource s) => switch (s) {
        Adau1701FirmwareSource.export14SingleWord => const Color(0xFF4A9EFF),
        Adau1701FirmwareSource.recompiled20260704Adapter => const Color(0xFFFF9800),
        Adau1701FirmwareSource.unknown => const Color(0xFF9E9E9E),
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SafetyBanner(),
        const SizedBox(height: 8),
        _transportWarning(),
        const SizedBox(height: 12),
        _versionRow(),
        const SizedBox(height: 10),
        _filterRow(),
        const SizedBox(height: 8),
        _candidateList(),
        if (_selected != null) ...[
          const SizedBox(height: 12),
          _detailPanel(),
        ],
        if (_log.isNotEmpty) ...[
          const SizedBox(height: 12),
          _logPanel(),
        ],
      ],
    );
  }

  Widget _transportWarning() => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A00),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.yellow.withValues(alpha: 0.2)),
        ),
        child: const Row(children: [
          Icon(Icons.info_outline, color: Colors.yellow, size: 11),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              'detectDevice() returns true unconditionally — '
              'does NOT prove firmware identity. '
              'Confirm firmware manually before enabling writes.',
              style: TextStyle(color: Colors.yellow, fontSize: 8, height: 1.4),
            ),
          ),
        ]),
      );

  Widget _versionRow() => Row(children: [
        const Icon(Icons.memory_outlined, color: Colors.white24, size: 11),
        const SizedBox(width: 6),
        Flexible(
          child: Text(_loadResult.version,
              style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 8,
                  fontFamily: 'monospace',
                  letterSpacing: 0.3)),
        ),
        const SizedBox(width: 8),
        Text('${_candidates.length} addr',
            style: const TextStyle(color: Colors.white24, fontSize: 9)),
      ]);

  Widget _filterRow() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Kind filter
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [null, ...Adau1701CandidateKind.values].map((k) {
                final sel = _kindFilter == k;
                return GestureDetector(
                  onTap: () => setState(() => _kindFilter = k),
                  child: Container(
                    margin: const EdgeInsets.only(right: 5),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: sel ? Colors.white12 : Colors.transparent,
                      border: Border.all(
                          color: sel ? Colors.white38 : Colors.white12),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(k?.label ?? 'ALL',
                        style: TextStyle(
                            color: sel ? Colors.white : Colors.white38,
                            fontSize: 9,
                            letterSpacing: 1)),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 6),
          // Source filter
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [null, ...Adau1701FirmwareSource.values].map((s) {
                final sel = _sourceFilter == s;
                final color = s != null ? _srcColor(s) : Colors.white38;
                return GestureDetector(
                  onTap: () => setState(() => _sourceFilter = s),
                  child: Container(
                    margin: const EdgeInsets.only(right: 5),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: sel ? color.withValues(alpha: 0.12) : Colors.transparent,
                      border: Border.all(
                          color: sel ? color.withValues(alpha: 0.5) : Colors.white12),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(s?.label ?? 'ALL-SRC',
                        style: TextStyle(
                            color: sel ? color : Colors.white24,
                            fontSize: 8,
                            letterSpacing: 0.5)),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      );

  Widget _candidateList() => Column(
        children: _filtered.map((c) {
          final gi = _candidates.indexOf(c);
          final sel = _selectedIndex == gi;
          final srcColor = _srcColor(c.firmwareSource);
          return GestureDetector(
            onTap: () => _select(gi),
            child: Container(
              margin: const EdgeInsets.only(bottom: 3),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: sel ? Colors.white.withValues(alpha: 0.04) : Colors.transparent,
                border: Border.all(
                    color: sel ? Colors.white24 : Colors.white.withValues(alpha: 0.07)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: _statusColor(c.status),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.label,
                          style: TextStyle(
                              color: c.isBlocked ? Colors.white24 : Colors.white60,
                              fontSize: 10,
                              letterSpacing: 0.3)),
                      Row(children: [
                        Text(c.addressHex,
                            style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 8,
                                fontFamily: 'monospace')),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: srcColor.withValues(alpha: 0.4)),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Text(c.firmwareSource.label,
                              style: TextStyle(
                                  color: srcColor,
                                  fontSize: 7,
                                  letterSpacing: 0.3)),
                        ),
                        const SizedBox(width: 4),
                        Text(c.writeShape.label,
                            style: const TextStyle(
                                color: Colors.white24, fontSize: 7)),
                      ]),
                    ],
                  ),
                ),
                if (c.isBlocked)
                  const Icon(Icons.lock_outline, color: Colors.white24, size: 11)
                else if (!c.firmwareConfirmed)
                  const Icon(Icons.device_unknown_outlined,
                      color: Color(0xFF4A9EFF), size: 11)
                else
                  Text(c.status.label,
                      style: TextStyle(
                          color: _statusColor(c.status),
                          fontSize: 8,
                          letterSpacing: 0.5)),
              ]),
            ),
          );
        }).toList(),
      );

  Widget _detailPanel() {
    final c = _selected!;
    final srcColor = _srcColor(c.firmwareSource);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(children: [
            Expanded(
                child: Text(c.label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.bold))),
            _StatusChip(c.status, _statusColor(c.status)),
          ]),
          const SizedBox(height: 8),

          // Meta grid
          _meta('Address', c.addressHex),
          _meta('Kind', c.kind.label),
          _meta('Write', c.writeShape.label),
          Row(children: [
            const SizedBox(
              width: 64,
              child: Text('Source',
                  style: TextStyle(
                      color: Colors.white38, fontSize: 9, letterSpacing: 1)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                border: Border.all(color: srcColor.withValues(alpha: 0.5)),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(c.firmwareSource.label,
                  style: TextStyle(color: srcColor, fontSize: 8)),
            ),
          ]),
          if (c.executedAt != null) ...[
            const SizedBox(height: 2),
            _meta('Last run',
                '${c.executedAt!.hour.toString().padLeft(2, '0')}:${c.executedAt!.minute.toString().padLeft(2, '0')}'),
          ],

          // Block reason
          if (c.isBlocked && c.blockReason != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF5C3317).withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(children: [
                const Icon(Icons.block, color: Color(0xFFFF6B00), size: 11),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(c.blockReason!,
                        style: const TextStyle(
                            color: Color(0xFFFF6B00),
                            fontSize: 8,
                            height: 1.4))),
              ]),
            ),
          ],

          // Write controls (only for unblocked, single-word candidates)
          if (!c.isBlocked &&
              c.writeShape == Adau1701WriteShape.singleWordParameter) ...[
            const SizedBox(height: 12),
            const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: 12),

            // Firmware confirmation gate
            if (!c.firmwareConfirmed) ...[
              _firmwareConfirmBox(c),
              const SizedBox(height: 10),
            ],

            if (c.firmwareConfirmed) ...[
              // Format selector + confirmation
              _formatSection(c),
              const SizedBox(height: 10),

              // Hex value fields
              _hexField('TEST VALUE (hex)', _testCtrl),
              const SizedBox(height: 8),
              _hexField('RESTORE VALUE (hex)', _restoreCtrl),
              const SizedBox(height: 10),

              // Write confirmation checkboxes
              _checkbox(
                  'I understand this will write to DSP hardware via BLE',
                  _userConfirmed,
                  (v) => setState(() => _userConfirmed = v ?? false)),
              _checkbox(
                  'I have confirmed the restore value is correct and safe',
                  _restoreConfirmed,
                  (v) => setState(() => _restoreConfirmed = v ?? false)),
              const SizedBox(height: 10),

              // Execute
              _executeButton(),

              // Result
              if (_lastResult != null && _lastResult!.id == c.id) ...[
                const SizedBox(height: 8),
                _resultPanel(_lastResult!),
              ],

              const SizedBox(height: 10),
              _noteField('MEASUREMENT NOTE', _measCtrl),
              const SizedBox(height: 6),
              _noteField('OPERATOR NOTE', _opNoteCtrl),

              // Operator actions — VERIFIED requires wasActualWrite AND formatConfirmed
              if (c.wasActualWrite) ...[
                const SizedBox(height: 10),
                if (!c.formatConfirmed) ...[
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A00),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                          color: Colors.yellow.withValues(alpha: 0.3)),
                    ),
                    child: const Text(
                      'VERIFIED blocked: format not confirmed. '
                      'Confirm the value format above before marking VERIFIED.',
                      style: TextStyle(
                          color: Colors.yellow, fontSize: 8, height: 1.4),
                    ),
                  ),
                ] else ...[
                  Row(children: [
                    Expanded(
                        child: _actionBtn('VERIFIED', const Color(0xFF4CAF50),
                            _markVerified)),
                    const SizedBox(width: 6),
                    Expanded(
                        child: _actionBtn('NEEDS MEAS', const Color(0xFFFF9800),
                            _markNeedsMeasurement)),
                    const SizedBox(width: 6),
                    Expanded(
                        child: _actionBtn(
                            'REJECTED', const Color(0xFF9E9E9E), _markRejected)),
                  ]),
                ],
              ],
            ],
          ],
        ],
      ),
    );
  }

  Widget _firmwareConfirmBox(Adau1701AddressCandidate c) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF001A3A),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFF4A9EFF).withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.device_unknown_outlined,
                  color: Color(0xFF4A9EFF), size: 11),
              SizedBox(width: 6),
              Text('FIRMWARE CONFIRMATION REQUIRED',
                  style: TextStyle(
                      color: Color(0xFF4A9EFF),
                      fontSize: 9,
                      letterSpacing: 1)),
            ]),
            const SizedBox(height: 6),
            Text(
              'Source: ${c.firmwareSource.label}\n'
              'This address is valid for Export14 firmware only.\n'
              'detectDevice() does NOT verify firmware version.\n'
              'Confirm manually (SigmaStudio / firmware version label) before enabling writes.',
              style: const TextStyle(
                  color: Color(0xFF4A9EFF), fontSize: 8, height: 1.5),
            ),
            const SizedBox(height: 8),
            _checkbox(
              'I confirm this device is running ADAU1701 Export14 firmware',
              c.firmwareConfirmed,
              (v) {
                setState(() => c.firmwareConfirmed = v ?? false);
                _persist();
              },
            ),
          ],
        ),
      );

  Widget _formatSection(Adau1701AddressCandidate c) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('VALUE FORMAT',
              style: TextStyle(
                  color: Colors.white38, fontSize: 9, letterSpacing: 1.5)),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children:
                  Adau1701ValueFormat.values.map((f) {
                final sel = c.valueFormat == f;
                final isUnknown = f == Adau1701ValueFormat.unknown;
                return GestureDetector(
                  onTap: () {
                    if (c.valueFormat != f) {
                      setState(() {
                        c.valueFormat = f;
                        c.formatConfirmed = false; // must re-confirm on change
                      });
                    }
                  },
                  child: Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: sel
                          ? (isUnknown
                              ? Colors.red.withValues(alpha: 0.15)
                              : Colors.white12)
                          : Colors.transparent,
                      border: Border.all(
                          color: sel
                              ? (isUnknown
                                  ? Colors.red.withValues(alpha: 0.5)
                                  : Colors.white38)
                              : Colors.white12),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(f.label,
                        style: TextStyle(
                            color: sel
                                ? (isUnknown ? Colors.red : Colors.white)
                                : Colors.white38,
                            fontSize: 9)),
                  ),
                );
              }).toList(),
            ),
          ),
          if (c.valueFormat != Adau1701ValueFormat.unknown) ...[
            const SizedBox(height: 8),
            _checkbox(
              'I confirm the value format is ${c.valueFormat.label} '
              '(changing format resets this confirmation)',
              c.formatConfirmed,
              (v) {
                setState(() => c.formatConfirmed = v ?? false);
                _persist();
              },
            ),
          ] else ...[
            const SizedBox(height: 6),
            const Text(
              'Select a format above. Unknown format blocks execution and VERIFIED.',
              style: TextStyle(
                  color: Colors.red, fontSize: 8, height: 1.4),
            ),
          ],
        ],
      );

  // ── Reusable sub-widgets ──────────────────────────────────────────────────

  Widget _meta(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(children: [
          SizedBox(
            width: 64,
            child: Text(k,
                style: const TextStyle(
                    color: Colors.white38, fontSize: 9, letterSpacing: 1)),
          ),
          Text(v,
              style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 10,
                  fontFamily: 'monospace')),
        ]),
      );

  Widget _hexField(String label, TextEditingController ctrl) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.white38, fontSize: 9, letterSpacing: 1)),
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(
                border: Border.all(color: Colors.white12),
                borderRadius: BorderRadius.circular(4)),
            child: TextField(
              controller: ctrl,
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontFamily: 'monospace'),
              decoration: const InputDecoration(
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: InputBorder.none,
                hintText: '00800000',
                hintStyle: TextStyle(color: Colors.white24, fontSize: 12),
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-FxX]')),
                LengthLimitingTextInputFormatter(10),
              ],
            ),
          ),
        ],
      );

  Widget _noteField(String label, TextEditingController ctrl) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.white38, fontSize: 9, letterSpacing: 1)),
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(
                border: Border.all(color: Colors.white12),
                borderRadius: BorderRadius.circular(4)),
            child: TextField(
              controller: ctrl,
              style:
                  const TextStyle(color: Colors.white54, fontSize: 11),
              maxLines: 2,
              decoration: const InputDecoration(
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: InputBorder.none,
              ),
            ),
          ),
        ],
      );

  Widget _checkbox(String label, bool value, ValueChanged<bool?> onChanged) =>
      Row(children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: value,
            onChanged: onChanged,
            side: const BorderSide(color: Colors.white24),
            checkColor: Colors.white,
            fillColor: WidgetStateProperty.all(Colors.transparent),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label,
              style: const TextStyle(
                  color: Colors.white38, fontSize: 9, height: 1.4)),
        ),
      ]);

  Widget _executeButton() => GestureDetector(
        onTap: _canExecute && !_executing ? _execute : null,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: _canExecute && !_executing
                ? const Color(0xFF1A3A00)
                : Colors.transparent,
            border: Border.all(
                color: _canExecute && !_executing
                    ? const Color(0xFF4CAF50).withValues(alpha: 0.5)
                    : Colors.white12),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: _executing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.5, color: Colors.white38))
                : Text('WRITE TEST → RESTORE',
                    style: TextStyle(
                        color: _canExecute ? Colors.white70 : Colors.white24,
                        fontSize: 11,
                        letterSpacing: 2)),
          ),
        ),
      );

  Widget _resultPanel(Adau1701EngWriteResult r) {
    final ok = r.resultStatus == Adau1701CandidateStatus.passAck;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: ok
            ? const Color(0xFF1A3A00).withValues(alpha: 0.5)
            : const Color(0xFF3A0000).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
            color: ok
                ? const Color(0xFF4CAF50).withValues(alpha: 0.3)
                : const Color(0xFFF44336).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(r.resultStatus.label,
              style: TextStyle(
                  color:
                      ok ? const Color(0xFF4CAF50) : const Color(0xFFF44336),
                  fontSize: 11,
                  letterSpacing: 2,
                  fontWeight: FontWeight.bold)),
          if (r.error != null) ...[
            const SizedBox(height: 4),
            Text(r.error!,
                style:
                    const TextStyle(color: Colors.white38, fontSize: 9)),
          ],
          const SizedBox(height: 4),
          Text(
              'test write: ${r.testWasActualWrite ? "YES" : "NO"}  '
              'restore: ${r.restoreWasActualWrite ? "YES" : "NO"}',
              style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 9,
                  fontFamily: 'monospace')),
          if (r.testWasActualWrite) ...[
            const SizedBox(height: 4),
            const Text(
                'PASS-ACK ≠ VERIFIED. Mark manually after confirming expected behavior.',
                style: TextStyle(
                    color: Color(0xFFFF9800), fontSize: 8, height: 1.4)),
          ],
        ],
      ),
    );
  }

  Widget _actionBtn(String label, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: color.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: Text(label,
                style:
                    TextStyle(color: color, fontSize: 9, letterSpacing: 1)),
          ),
        ),
      );

  Widget _logPanel() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('LOG',
                style: TextStyle(
                    color: Colors.white38, fontSize: 9, letterSpacing: 2)),
            const SizedBox(width: 6),
            Text('(${_log.length})',
                style: const TextStyle(color: Colors.white24, fontSize: 9)),
          ]),
          const SizedBox(height: 6),
          ..._log.take(10).map((e) => Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.06)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${e.addressHex}  ${e.label}',
                            style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 9,
                                fontFamily: 'monospace')),
                        Text(
                            '${e.resultStatus}  '
                            '${e.firmwareSource}  '
                            '${e.valueFormat}',
                            style: const TextStyle(
                                color: Colors.white24,
                                fontSize: 8,
                                fontFamily: 'monospace')),
                      ],
                    ),
                  ),
                  Text(
                    '${e.timestamp.hour.toString().padLeft(2, '0')}:'
                    '${e.timestamp.minute.toString().padLeft(2, '0')}:'
                    '${e.timestamp.second.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                        color: Colors.white24,
                        fontSize: 8,
                        fontFamily: 'monospace'),
                  ),
                ]),
              )),
        ],
      );
}

// ── Static sub-widgets ────────────────────────────────────────────────────────

class _SafetyBanner extends StatelessWidget {
  const _SafetyBanner();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF3A1A00),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: const Color(0xFFFF6B00).withValues(alpha: 0.3)),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.warning_amber_rounded,
                  color: Color(0xFFFF9800), size: 13),
              SizedBox(width: 6),
              Text('ADAU1701 ENGINEERING VERIFICATION',
                  style: TextStyle(
                      color: Color(0xFFFF9800),
                      fontSize: 10,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.bold)),
            ]),
            SizedBox(height: 6),
            Text(
              '• No EEPROM / Selfboot / WriteAll\n'
              '• Export14: MV always ready. Gain needs firmware confirm.\n'
              '• Adapter-2026: all blocked (5-word write shape, not supported)\n'
              '• Unknown format blocks execution AND VERIFIED\n'
              '• PASS-ACK ≠ VERIFIED — mark manually after behavior confirmed\n'
              '• VERIFIED requires wasActualWrite AND formatConfirmed\n'
              '• 5.23 fixed-point (1.0 = 0x00800000). Confirm before writing.',
              style: TextStyle(
                  color: Color(0xFFFF9800), fontSize: 8, height: 1.6),
            ),
          ],
        ),
      );
}

class _StatusChip extends StatelessWidget {
  final Adau1701CandidateStatus status;
  final Color color;
  const _StatusChip(this.status, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(status.label,
            style: TextStyle(
                color: color, fontSize: 9, letterSpacing: 1)),
      );
}
