import 'package:flutter/material.dart';

import 'brand_identity.dart';
import 'splash_animation.dart';
import 'splash_controller.dart';

/// TUNAI brand intro splash.
///
/// Black → symbol wipe-in → settle(scale/fade) → logo-sound-synced exit.
/// Cold start only — mounted once as the app's initial screen; it is never
/// re-shown on background resume because it isn't re-mounted.
///
/// Safety principles (see [SplashController] / [AudioIdentityService]):
/// - [onFinished] fires exactly once, when the motion completes.
/// - A missing/failing logo sound never blocks the motion or the transition.
/// - A fail-safe timer guarantees [onFinished] fires even if the animation
///   itself never reaches `completed`.
/// - dispose() tears down the timer, controller, and audio player so nothing
///   fires after this widget leaves the tree.
class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    required this.onFinished,
    this.minDuration = const Duration(milliseconds: 1400),
    this.playLogoSound = true,
    this.brand = BrandIdentity.tunai,
  });

  /// Called once when the splash should hand off to the next screen.
  final VoidCallback onFinished;

  /// Minimum motion length (brand guideline: 1.0–1.5s, default 1.4s — chosen
  /// to comfortably cover the ~1s logo sound with margin). The actual
  /// handoff may take slightly longer than this if the logo sound is still
  /// playing when the motion finishes — see [SplashController].
  final Duration minDuration;

  /// Disable in tests or if audio playback should be skipped entirely.
  final bool playLogoSound;

  /// Which brand's mark/wordmark/logo sound to render — defaults to TUNAI.
  /// Swapping brands (e.g. a future OHNM rebrand) means passing a different
  /// [BrandIdentity] here; no other Splash code changes.
  final BrandIdentity brand;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final SplashController _controller;

  @override
  void initState() {
    super.initState();
    debugPrint(
        '[ SPLASH ] SplashScreen init (minDuration=${widget.minDuration})');
    _controller = SplashController(
      vsync: this,
      brand: widget.brand,
      minDuration: widget.minDuration,
      playLogoSound: widget.playLogoSound,
    )..start(widget.onFinished);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      body: Center(
        child: AnimatedBuilder(
          animation: _controller.animation,
          builder: (context, _) {
            final t = _controller.animation.value;
            return reduceMotion
                ? ReducedMotionSplashView(t: t, brand: widget.brand)
                : SplashMotionView(t: t, brand: widget.brand);
          },
        ),
      ),
    );
  }
}
