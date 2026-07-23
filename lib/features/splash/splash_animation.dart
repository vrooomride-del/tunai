import 'package:flutter/material.dart';

import 'brand_identity.dart';

/// Reduce Motion fallback — simple fade-in, no scale choreography.
class ReducedMotionSplashView extends StatelessWidget {
  const ReducedMotionSplashView(
      {super.key, required this.t, required this.brand});

  final double t;
  final BrandIdentity brand;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: t.clamp(0.0, 1.0),
      child: SplashSymbol(brand: brand),
    );
  }
}

/// Full brand motion — a quiet fade + gentle settle so the intro reads as a
/// held, considered reveal rather than a flash, comfortably covering the
/// logo sound with room to spare:
/// 1) 0.00–0.55: the brand image fades in.
/// 2) 0.15–0.70: it settles from a slight scale-down (0.94) to 1.0.
/// 3) 0.90–1.00: hold — logo sound tail finishes before the next screen.
class SplashMotionView extends StatelessWidget {
  const SplashMotionView({super.key, required this.t, required this.brand});

  final double t;
  final BrandIdentity brand;

  static double _progress(double t, double start, double end) {
    if (t <= start) return 0;
    if (t >= end) return 1;
    return (t - start) / (end - start);
  }

  @override
  Widget build(BuildContext context) {
    final opacity = Curves.easeIn.transform(_progress(t, 0.0, 0.55));
    final settle = Curves.easeOutBack.transform(_progress(t, 0.15, 0.70));
    final scale = (0.94 + (0.06 * settle)).clamp(0.0, 1.06);

    return Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: Transform.scale(
        scale: scale,
        child: SplashSymbol(brand: brand),
      ),
    );
  }
}

/// Renders the real brand image ([BrandIdentity.imageAssetPath]) — the
/// actual approved BI artwork, not a redrawn approximation. `BoxFit.contain`
/// inside a horizontally-padded, width-capped box guarantees the mark and
/// wordmark are never cropped, on any screen size or aspect ratio: the image
/// only ever shrinks to fit, never overflows or gets clipped.
class SplashSymbol extends StatelessWidget {
  const SplashSymbol({super.key, required this.brand});

  final BrandIdentity brand;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    // .clamp guards against a zero/near-zero test MediaQuerySize (or a real
    // device in an unusually tiny window) producing a negative maxWidth,
    // which BoxConstraints rejects outright.
    final maxWidth = (screenSize.width - 80).clamp(0.0, double.infinity);
    final maxHeight = (screenSize.height * 0.5).clamp(0.0, double.infinity);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: maxHeight,
        ),
        child: Image.asset(
          brand.imageAssetPath,
          fit: BoxFit.contain,
          semanticLabel: brand.name,
        ),
      ),
    );
  }
}
