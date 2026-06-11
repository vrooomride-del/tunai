import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_service.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_screen.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  List<dynamic> _measurements = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final auth = ref.read(authProvider);
    if (!auth.isLoggedIn) {
      setState(() => _loading = false);
      return;
    }
    final res = await ApiService.getMeasurements();
    if (res['status'] == 'ok') {
      setState(() {
        _measurements = res['data'] ?? [];
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Row(
                children: [
                  const Text('HISTORY',
                      style: TextStyle(color: Colors.white, fontSize: 18,
                          fontWeight: FontWeight.w200, letterSpacing: 6)),
                  const Spacer(),
                  GestureDetector(
                    onTap: _load,
                    child: const Icon(Icons.refresh, color: Colors.white38, size: 16),
                  ),
                ],
              ),
            ),
            Expanded(
              child: !auth.isLoggedIn
                  ? _buildLoginPrompt(context)
                  : _loading
                      ? const Center(child: CircularProgressIndicator(
                          color: Colors.white24, strokeWidth: 1))
                      : _measurements.isEmpty
                          ? const Center(
                              child: Text('측정 기록이 없습니다.',
                                  style: TextStyle(color: Colors.white38, fontSize: 13)))
                          : RefreshIndicator(
                              onRefresh: _load,
                              color: Colors.white,
                              backgroundColor: const Color(0xFF111111),
                              child: ListView.separated(
                                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                                itemCount: _measurements.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 12),
                                itemBuilder: (_, i) =>
                                    _MeasurementCard(data: _measurements[i]),
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoginPrompt(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('로그인 후 측정 기록을 확인할 수 있습니다.',
              style: TextStyle(color: Colors.white38, fontSize: 13)),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AuthScreen())),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white38),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('LOGIN',
                  style: TextStyle(color: Colors.white, fontSize: 11, letterSpacing: 2)),
            ),
          ),
        ],
      ),
    );
  }
}

class _MeasurementCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _MeasurementCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final peaks = data['peaks_json'] as List? ?? [];
    final createdAt = data['created_at'] ?? '';
    final dateStr = createdAt.length >= 10 ? createdAt.substring(0, 10) : createdAt;
    final timeStr = createdAt.length >= 16 ? createdAt.substring(11, 16) : '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.graphic_eq, color: Colors.white38, size: 14),
              const SizedBox(width: 8),
              Text('측정 #${data['id'] ?? ''}',
                  style: const TextStyle(color: Colors.white, fontSize: 14)),
              const Spacer(),
              Text('$dateStr  $timeStr',
                  style: const TextStyle(color: Colors.white24, fontSize: 10)),
            ],
          ),
          const SizedBox(height: 12),
          // 피크 목록
          if (peaks.isEmpty)
            const Text('공진 주파수 없음',
                style: TextStyle(color: Colors.white24, fontSize: 11))
          else
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: peaks.map<Widget>((p) {
                final freq = (p['frequency'] ?? p['f'] ?? 0).toDouble();
                final gain = (p['gain'] ?? p['g'] ?? 0).toDouble();
                final freqStr = freq >= 1000
                    ? '${(freq / 1000).toStringAsFixed(1)}kHz'
                    : '${freq.toStringAsFixed(0)}Hz';
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    border: Border.all(color: Colors.white12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '$freqStr  ${gain.toStringAsFixed(1)}dB',
                    style: const TextStyle(color: Colors.white54, fontSize: 10),
                  ),
                );
              }).toList(),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text('${peaks.length}개 공진 검출',
                  style: const TextStyle(color: Colors.white24, fontSize: 10)),
              const Spacer(),
              if (data['speaker_model'] != null)
                Text(data['speaker_model'],
                    style: const TextStyle(color: Colors.white24, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }
}
