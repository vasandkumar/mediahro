/// What the About screen says about this build (CORE-013).
abstract final class AboutInfo {
  /// The product name. Not translated.
  static const appName = 'Mediahro';

  /// `pubspec.yaml`'s version, passed to every build with
  /// `--dart-define=MEDIAHRO_VERSION=<name>` and `MEDIAHRO_BUILD=<number>`
  /// (the same values as `--build-name` and `--build-number`); the default is
  /// what `flutter run` shows. A test keeps the default equal to the pubspec.
  static const version = String.fromEnvironment(
    'MEDIAHRO_VERSION',
    defaultValue: '0.1.0',
  );
  static const build = String.fromEnvironment(
    'MEDIAHRO_BUILD',
    defaultValue: '1',
  );

  /// A fork or modified build must say so in About (docs/09 §5):
  /// `--dart-define=MEDIAHRO_UNOFFICIAL=true`.
  static const unofficial = bool.fromEnvironment('MEDIAHRO_UNOFFICIAL');
}

/// The project's published documents (docs/09 §5, §6). Shown to copy; the app
/// never opens them or contacts these hosts itself.
abstract final class AboutLinks {
  static const privacy = 'https://mediahro.com/privacy';
  static const terms = 'https://mediahro.com/terms';
  static const trademark = 'https://mediahro.com/trademark';
  static const source = 'https://github.com/vasandkumar/mediahro';
}
