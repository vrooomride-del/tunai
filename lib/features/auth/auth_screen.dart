import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_controller.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  bool _isLogin = true;
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nicknameCtrl = TextEditingController();

  bool _isKo(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'ko';

  @override
  Widget build(BuildContext context) {
    final ko = _isKo(context);
    final auth = ref.watch(authProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 60),
              const Text('TUNAI',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 28,
                      fontWeight: FontWeight.w200, letterSpacing: 10)),
              const SizedBox(height: 8),
              Text(
                  _isLogin
                      ? (ko ? '로그인' : 'SIGN IN')
                      : (ko ? '계정 만들기' : 'CREATE ACCOUNT'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 4)),
              const SizedBox(height: 16),
              Text(
                ko
                    ? '나만의 사운드를 저장하고,\n커뮤니티와 함께 공유하세요.'
                    : 'Save Your Sound and\nshare it with the community.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white24, fontSize: 12, height: 1.6),
              ),
              const SizedBox(height: 44),
              _Field(label: 'EMAIL', controller: _emailCtrl, keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 16),
              if (!_isLogin) ...[
                _Field(label: 'NICKNAME', controller: _nicknameCtrl),
                const SizedBox(height: 16),
              ],
              _Field(label: 'PASSWORD', controller: _passwordCtrl, obscure: true),
              const SizedBox(height: 8),
              if (auth.error != null)
                Text(auth.error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                    textAlign: TextAlign.center),
              const SizedBox(height: 32),
              GestureDetector(
                onTap: auth.isLoading ? null : () async {
                  bool ok;
                  if (_isLogin) {
                    ok = await ref.read(authProvider.notifier)
                        .login(_emailCtrl.text.trim(), _passwordCtrl.text);
                  } else {
                    ok = await ref.read(authProvider.notifier)
                        .register(_emailCtrl.text.trim(), _passwordCtrl.text, _nicknameCtrl.text.trim());
                  }
                  if (!mounted) return;
                  // ignore: use_build_context_synchronously
                  if (ok) Navigator.of(context).pop();
                },
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    border: Border.all(color: auth.isLoading ? Colors.white24 : Colors.white),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: auth.isLoading
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 1, color: Colors.white38))
                        : Text(
                            _isLogin
                                ? (ko ? '로그인' : 'Sign In')
                                : (ko ? '계정 만들기' : 'Create Account'),
                            style: const TextStyle(color: Colors.white, fontSize: 12, letterSpacing: 3)),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  const Expanded(child: Divider(color: Colors.white12)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(ko ? '또는' : 'or',
                        style: const TextStyle(color: Colors.white24, fontSize: 11)),
                  ),
                  const Expanded(child: Divider(color: Colors.white12)),
                ],
              ),


              const SizedBox(height: 12),
              // Google login
              GestureDetector(
                onTap: () async {
                  final ok = await ref.read(authProvider.notifier).loginWithGoogle();
                  if (!mounted) return;
                  // ignore: use_build_context_synchronously
                  if (ok) Navigator.of(context).pop();
                },
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white24),
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.white,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.g_mobiledata, color: Colors.red, size: 28),
                      const SizedBox(width: 8),
                      Text(ko ? 'Google로 로그인' : 'Continue with Google',
                          style: const TextStyle(
                              color: Colors.black87,
                              fontSize: 14,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Kakao login
              GestureDetector(
                onTap: () async {
                  final ok = await ref.read(authProvider.notifier).loginWithKakao();
                  if (!mounted) return;
                  // ignore: use_build_context_synchronously
                  if (ok) Navigator.of(context).pop();
                },
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE500),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.chat_bubble, color: Color(0xFF3A1D1D), size: 18),
                      const SizedBox(width: 8),
                      Text(ko ? '카카오 로그인' : 'Continue with Kakao',
                          style: const TextStyle(color: Color(0xFF3A1D1D),
                              fontSize: 14, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () => setState(() => _isLogin = !_isLogin),
                child: Text(
                  _isLogin
                      ? (ko ? '계정이 없으신가요?  계정 만들기' : "Don't have an account?  Create one")
                      : (ko ? '이미 계정이 있으신가요?  로그인' : 'Already have an account?  Sign in'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Center(
                  child: Text(
                    ko ? '로그인 없이 계속' : 'Continue without signing in',
                    style: const TextStyle(color: Colors.white24, fontSize: 12, decoration: TextDecoration.underline),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool obscure;
  final TextInputType? keyboardType;
  const _Field({required this.label, required this.controller, this.obscure = false, this.keyboardType});

  String _displayLabel(BuildContext context) {
    final ko = Localizations.localeOf(context).languageCode == 'ko';
    if (!ko) return label;
    return switch (label) {
      'EMAIL' => '이메일',
      'PASSWORD' => '비밀번호',
      'NICKNAME' => '닉네임',
      _ => label,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_displayLabel(context), style: const TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 2)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: const InputDecoration(
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
            contentPadding: EdgeInsets.symmetric(vertical: 8),
          ),
        ),
      ],
    );
  }
}
