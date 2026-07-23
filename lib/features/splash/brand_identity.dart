/// Brand-specific values the Splash feature renders — kept in one place so a
/// future rebrand only requires a new [BrandIdentity] value, not changes to
/// the splash widget/controller/animation code.
class BrandIdentity {
  /// Wordmark shown for accessibility/semantics and in places that still
  /// need plain text (e.g. window title) — the Splash screen itself renders
  /// [imageAssetPath], which already contains the wordmark as artwork.
  final String name;

  /// Logo sound asset path (brand audio identity, distinct from any speaker
  /// output confirmation tone — see [AudioIdentityService]).
  final String logoSoundAssetPath;

  /// The brand image (mark + wordmark, already composed by design) the
  /// Splash screen displays — rendered with `BoxFit.contain` so it is never
  /// cropped on any screen size/aspect ratio.
  final String imageAssetPath;

  const BrandIdentity({
    required this.name,
    required this.logoSoundAssetPath,
    required this.imageAssetPath,
  });

  static const tunai = BrandIdentity(
    name: 'OHNUM',
    logoSoundAssetPath: 'assets/audio/tunai_logo_sound.wav',
    imageAssetPath: 'assets/images/splash_bi.png',
  );
}
