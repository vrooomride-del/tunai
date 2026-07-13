// ── TUNAI Consumer — ADAU1701 Engineering Verification Console ───────────────
// Hidden engineering tool. NOT part of normal consumer UX.
// Accessed only from the PIN-protected Factory screen.
//
// ABSOLUTE RESTRICTIONS:
//   - No EEPROM. No Selfboot. No WriteAll. No full profile deployment.
//   - Every actual write requires user confirmation checkbox.
//   - Every actual write requires a stored restore value.
//   - ACK success alone = PASS_ACK, not VERIFIED.
//   - VERIFIED = operator manual mark only.
//   - 5.23 fixed-point by default (1.0 = 0x00800000, NOT 0x01000000).

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
    if (_kindFilter == null) return _candidates;
    return _candidates.where((c) => c.kind == _kindFilter).toList();
  }

  Adau1701AddressCandidate? get _selected =>
      _selectedIndex != null ? _candidates[_selectedIndex!] : null;

  void _select(int globalIdx) {
    final c = _candidates[globalIdx];
    setState(() {
      _selectedIndex = globalIdx;
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
    return _userConfirmed && _restoreConfirmed;
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
      testValueHex: c.testValueHex,
      restoreValueHex: c.restoreValueHex,
      valueFormat: c.valueFormat.name,
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
    if (c == null || !c.wasActualWrite) return;
    setState(() {
      c.status = Adau1701CandidateStatus.verified;
      if (_opNoteCtrl.text.trim().isNotEmpty) {
        c.operatorNote = _opNoteCtrl.text.trim();
      }
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SafetyBanner(),
        const SizedBox(height: 12),
        _versionRow(),
        const SizedBox(height: 12),
        _kindFilterRow(),
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

  Widget _versionRow() => Row(children: [
        const Icon(Icons.memory_outlined, color: Colors.white24, size: 11),
        const SizedBox(width: 6),
        Text(_loadResult.version,
            style: const TextStyle(
                color: Colors.white38,
                fontSize: 9,
                fontFamily: 'monospace',
                letterSpacing: 0.5)),
        const Spacer(),
        Text('${_candidates.length} addrs',
            style: const TextStyle(color: Colors.white24, fontSize: 9)),
      ]);

  Widget _kindFilterRow() {
    final kinds = [null, ...Adau1701CandidateKind.values];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: kinds.map((k) {
          final sel = _kindFilter == k;
          return GestureDetector(
            onTap: () => setState(() => _kindFilter = k),
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: sel ? Colors.white12 : Colors.transparent,
                border: Border.all(
                    color: sel ? Colors.white38 : Colors.white12),
                borderRadius: BorderRadius.circular(4),
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
    );
  }

  Widget _candidateList() => Column(
        children: _filtered.map((c) {
          final gi = _candidates.indexOf(c);
          final sel = _selectedIndex == gi;
          return GestureDetector(
            onTap: () => _select(gi),
            child: Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: sel
                    ? Colors.white.withOpacity(0.05)
                    : Colors.transparent,
                border: Border.all(
                    color: sel ? Colors.white24 : Colors.white12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _statusColor(c.status),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.label,
                          style: TextStyle(
                              color: c.isBlocked
                                  ? Colors.white24
                                  : Colors.white70,
                              fontSize: 11,
                              letterSpacing: 0.5)),
                      Text(
                          '${c.addressHex}  ${c.kind.label}  ${c.valueFormat.label}',
                          style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 9,
                              fontFamily: 'monospace')),
                    ],
                  ),
                ),
                if (c.isBlocked)
                  const Icon(Icons.lock_outline,
                      color: Colors.white24, size: 12)
                else
                  Text(c.status.label,
                      style: TextStyle(
                          color: _statusColor(c.status),
                          fontSize: 9,
                          letterSpacing: 1)),
              ]),
            ),
          );
        }).toList(),
      );

  Widget _detailPanel() {
    final c = _selected!;
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
                        fontSize: 13,
                        letterSpacing: 1,
                        fontWeight: FontWeight.bold))),
            _StatusChip(c.status, _statusColor(c.status)),
          ]),
          const SizedBox(height: 8),
          _meta('Address', c.addressHex),
          _meta('Kind', c.kind.label),
          _meta('Format', c.valueFormat.label),
          if (c.executedAt != null)
            _meta('Last run',
                '${c.executedAt!.hour.toString().padLeft(2, '0')}:${c.executedAt!.minute.toString().padLeft(2, '0')}'),

          if (c.isBlocked && c.blockReason != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF5C3317).withOpacity(0.3),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(children: [
                const Icon(Icons.block, color: Color(0xFFFF6B00), size: 11),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(c.blockReason!,
                        style: const TextStyle(
                            color: Color(0xFFFF6B00),
                            fontSize: 9,
                            height: 1.4))),
              ]),
            ),
          ],

          if (!c.isBlocked) ...[
            const SizedBox(height: 12),
            const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: 12),

            // Format selector
            _formatSelector(c),
            const SizedBox(height: 10),

            // Hex fields
            _hexField('TEST VALUE (hex)', _testCtrl),
            const SizedBox(height: 8),
            _hexField('RESTORE VALUE (hex)', _restoreCtrl),
            const SizedBox(height: 10),

            // Confirmation checkboxes
            _checkbox(
                'I understand this will write to DSP hardware via BLE',
                _userConfirmed,
                (v) => setState(() => _userConfirmed = v ?? false)),
            _checkbox(
                'I have confirmed the restore value is correct and safe',
                _restoreConfirmed,
                (v) => setState(() => _restoreConfirmed = v ?? false)),
            const SizedBox(height: 10),

            // Execute button
            _executeButton(),

            // Result panel
            if (_lastResult != null && _lastResult!.id == c.id) ...[
              const SizedBox(height: 8),
              _resultPanel(_lastResult!),
            ],

            const SizedBox(height: 10),
            _noteField('MEASUREMENT NOTE', _measCtrl),
            const SizedBox(height: 6),
            _noteField('OPERATOR NOTE', _opNoteCtrl),

            if (c.wasActualWrite) ...[
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: _actionBtn(
                        'VERIFIED', const Color(0xFF4CAF50), _markVerified)),
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
      ),
    );
  }

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

  Widget _formatSelector(Adau1701AddressCandidate c) => Row(children: [
        const Text('FORMAT',
            style: TextStyle(
                color: Colors.white38, fontSize: 9, letterSpacing: 1.5)),
        const SizedBox(width: 10),
        ...Adau1701ValueFormat.values.map((f) => GestureDetector(
              onTap: () => setState(() => c.valueFormat = f),
              child: Container(
                margin: const EdgeInsets.only(right: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: c.valueFormat == f
                      ? Colors.white12
                      : Colors.transparent,
                  border: Border.all(
                      color: c.valueFormat == f
                          ? Colors.white38
                          : Colors.white12),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(f.label,
                    style: TextStyle(
                        color: c.valueFormat == f
                            ? Colors.white
                            : Colors.white38,
                        fontSize: 9)),
              ),
            )),
      ]);

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
              borderRadius: BorderRadius.circular(4),
            ),
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
                hintStyle:
                    TextStyle(color: Colors.white24, fontSize: 12),
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                    RegExp(r'[0-9a-fA-FxX]')),
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
              borderRadius: BorderRadius.circular(4),
            ),
            child: TextField(
              controller: ctrl,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
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

  Widget _checkbox(
          String label, bool value, ValueChanged<bool?> onChanged) =>
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
                  color: Colors.white38, fontSize: 10, height: 1.4)),
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
                    ? const Color(0xFF4CAF50).withOpacity(0.5)
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
                        color: _canExecute
                            ? Colors.white70
                            : Colors.white24,
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
            ? const Color(0xFF1A3A00).withOpacity(0.5)
            : const Color(0xFF3A0000).withOpacity(0.5),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
            color: ok
                ? const Color(0xFF4CAF50).withOpacity(0.3)
                : const Color(0xFFF44336).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(r.resultStatus.label,
              style: TextStyle(
                  color: ok
                      ? const Color(0xFF4CAF50)
                      : const Color(0xFFF44336),
                  fontSize: 11,
                  letterSpacing: 2,
                  fontWeight: FontWeight.bold)),
          if (r.error != null) ...[
            const SizedBox(height: 4),
            Text(r.error!,
                style: const TextStyle(color: Colors.white38, fontSize: 9)),
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
            border: Border.all(color: color.withOpacity(0.4)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
              child: Text(label,
                  style: TextStyle(
                      color: color, fontSize: 9, letterSpacing: 1))),
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
                style:
                    const TextStyle(color: Colors.white24, fontSize: 9)),
          ]),
          const SizedBox(height: 6),
          ..._log.take(10).map((e) => Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(
                      color: Colors.white.withOpacity(0.06)),
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
                            '${e.testValueHex}→${e.restoreValueHex}',
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

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _SafetyBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF3A1A00),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: const Color(0xFFFF6B00).withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
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
            const SizedBox(height: 6),
            const Text(
              '• No EEPROM / Selfboot / WriteAll\n'
              '• Gain & MV only — Mute / Delay / PEQ blocked\n'
              '• Write completes without exception = PASS-ACK\n'
              '• PASS-ACK ≠ VERIFIED — mark manually\n'
              '• 5.23 fixed-point default (1.0 = 0x00800000)',
              style: TextStyle(
                  color: Color(0xFFFF9800), fontSize: 9, height: 1.6),
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
          color: color.withOpacity(0.12),
          border: Border.all(color: color.withOpacity(0.4)),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(status.label,
            style: TextStyle(
                color: color, fontSize: 9, letterSpacing: 1)),
      );
}
