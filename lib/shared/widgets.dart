import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/ble/ble_controller.dart';
import '../features/auth/auth_controller.dart';
import '../features/auth/auth_screen.dart';

/// 화면 전반에서 재사용하는 아웃라인 버튼 (기존 home_screen.dart의 _OutlineButton 추출)
class OutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  final bool enabled;
  const OutlineButton({super.key, required this.label, this.onTap, this.loading = false, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    final active = onTap != null && enabled && !loading;
    return GestureDetector(
      onTap: active ? onTap : null,
      child: Container(
        height: 40, padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(border: Border.all(color: active ? Colors.white : Colors.white24), borderRadius: BorderRadius.circular(6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (loading) ...[const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1, color: Colors.white38)), const SizedBox(width: 8)],
          Text(label, style: TextStyle(color: active ? Colors.white : Colors.white54, fontSize: 12, letterSpacing: 2, fontWeight: FontWeight.w400)),
        ]),
      ),
    );
  }
}

/// 모든 탭 상단에서 재사용하는 로고+연결상태+로그인 바 (기존 _TopBar 추출, 자체적으로 provider watch)
class TunaiTopBar extends ConsumerWidget {
  final String? subtitle;
  const TunaiTopBar({super.key, this.subtitle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bState = ref.watch(bleProvider);
    final auth = ref.watch(authProvider);
    final isConnected = bState.connection == BleConnectionState.connected;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('TUNAI', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w200, letterSpacing: 8)),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(subtitle!, style: const TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 2)),
                ),
            ],
          ),
          const Spacer(),
          Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: isConnected ? Colors.white : Colors.white24)),
          const SizedBox(width: 8),
          Text(isConnected ? (bState.deviceName ?? 'CONNECTED') : 'NO DEVICE',
              style: TextStyle(color: isConnected ? Colors.white54 : Colors.white24, fontSize: 10, letterSpacing: 2)),
          const SizedBox(width: 16),
          GestureDetector(
            onTap: () {
              if (auth.isLoggedIn) {
                ref.read(authProvider.notifier).logout();
              } else {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AuthScreen()));
              }
            },
            child: Text(
              auth.isLoggedIn ? (auth.nickname ?? 'MY') : 'LOGIN',
              style: const TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 2),
            ),
          ),
        ],
      ),
    );
  }
}

/// 카드형 섹션 공통 스타일 (기존 화면들의 반복되는 테두리/배경 패턴 추출)
class SectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const SectionCard({super.key, required this.child, this.padding = const EdgeInsets.all(14)});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(8),
        color: Colors.white.withValues(alpha: 0.03),
      ),
      child: child,
    );
  }
}
