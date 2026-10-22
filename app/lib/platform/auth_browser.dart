/// OAuth 2 authorization in the system's authentication browser (RFC 8252):
/// for a sign-in that needs one. No feature uses it since ADR-048 removed the
/// cloud drives (NET-007) and Trakt progress sync (LIB-010), which each needed
/// a client ID the publisher would hold. The app never
/// shows sign-in pages in its own web view and never sees the password.
///
/// Lane C4 implements it in Phase C:
/// - Android: Custom Tabs, completing on an app link or the app's custom
///   scheme redirect.
/// - iOS / macOS: `ASWebAuthenticationSession` with the redirect's scheme as
///   `callbackURLScheme` (ephemeral session off, so existing sign-ins help).
/// - Windows: the default browser; the redirect is the loopback listener
///   B2 already runs (`LoopbackRedirect`, RFC 8252 §7.3), so the facade only
///   launches the URL and waits for that listener.
abstract interface class AuthBrowserFacade {
  /// Opens [authorizationUrl] and completes with the full redirect URI,
  /// query included (`code`, `state`, or `error`), once the provider
  /// redirects to [redirectUri]. B2 validates `state` and exchanges the code
  /// (PKCE S256). Throws [AuthCancelled] when the user closes the browser.
  Future<Uri> authorize(Uri authorizationUrl, Uri redirectUri);
}

/// The user closed the authentication browser before finishing sign-in.
final class AuthCancelled implements Exception {
  const AuthCancelled();

  @override
  String toString() => 'AuthCancelled';
}
