import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/platform/audio_output.dart';
import 'package:mediahro/platform/auth_browser.dart';
import 'package:mediahro/platform/caption_style.dart';
import 'package:mediahro/platform/car_and_alarms.dart';
import 'package:mediahro/platform/cast.dart';
import 'package:mediahro/platform/display.dart';
import 'package:mediahro/platform/enterprise.dart';
import 'package:mediahro/platform/media_session.dart';
import 'package:mediahro/platform/network_status.dart';
import 'package:mediahro/platform/purchases.dart';
import 'package:mediahro/platform/secure_transport.dart';
import 'package:mediahro/platform/security.dart';
import 'package:mediahro/platform/storage.dart';
import 'package:mediahro/platform/system_integration.dart';
import 'package:mediahro/platform/text_services.dart';

export 'audio_output.dart';
export 'auth_browser.dart';
export 'caption_style.dart';
export 'car_and_alarms.dart';
export 'cast.dart';
export 'display.dart';
export 'enterprise.dart';
export 'media_session.dart';
export 'network_status.dart';
export 'purchases.dart';
export 'secure_transport.dart';
export 'security.dart';
export 'storage.dart';
export 'system_integration.dart';
export 'text_services.dart';

/// Thrown when a facade has no implementation on this platform/flavour yet
/// or by design; callers map it to "Not available on this device".
final class PlatformCapabilityUnavailable implements Exception {
  const PlatformCapabilityUnavailable(this.capability);

  final String capability;

  @override
  String toString() => 'PlatformCapabilityUnavailable($capability)';
}

Never _unavailable(String name) => throw PlatformCapabilityUnavailable(name);

// A missing facade is permanent for the process, so Riverpod 3's automatic
// retry must not rebuild everything that depends on it with backoff.
Duration? _noRetry(int retryCount, Object error) => null;

// One provider per facade (docs/05 §8). Lane C4 overrides each with its
// Pigeon-backed implementation per platform in `<platform>/bindings.dart`;
// tests override them with fakes. Feature code depends only on these.
final mediaSessionProvider = Provider<MediaSessionFacade>(
  (ref) => _unavailable('mediaSession'),
  retry: _noRetry,
);
final storageProvider = Provider<StorageFacade>(
  (ref) => _unavailable('storage'),
  retry: _noRetry,
);
final photoLibraryProvider = Provider<PhotoLibraryFacade>(
  (ref) => _unavailable('photoLibrary'),
  retry: _noRetry,
);
final audioOutputProvider = Provider<AudioOutputFacade>(
  (ref) => _unavailable('audioOutput'),
  retry: _noRetry,
);
final castProvider = Provider<CastFacade>(
  (ref) => _unavailable('cast'),
  retry: _noRetry,
);
final displayProvider = Provider<DisplayFacade>(
  (ref) => _unavailable('display'),
  retry: _noRetry,
);
final pipProvider = Provider<PipFacade>(
  (ref) => _unavailable('pip'),
  retry: _noRetry,
);
final secureStorageProvider = Provider<SecureStorageFacade>(
  (ref) => _unavailable('secureStorage'),
  retry: _noRetry,
);
final biometricsProvider = Provider<BiometricsFacade>(
  (ref) => _unavailable('biometrics'),
  retry: _noRetry,
);
final managedConfigProvider = Provider<ManagedConfigFacade>(
  (ref) => _unavailable('managedConfig'),
  retry: _noRetry,
);
final kioskProvider = Provider<KioskFacade>(
  (ref) => _unavailable('kiosk'),
  retry: _noRetry,
);
final systemIntegrationProvider = Provider<SystemIntegrationFacade>(
  (ref) => _unavailable('systemIntegration'),
  retry: _noRetry,
);
final intentsProvider = Provider<IntentsFacade>(
  (ref) => _unavailable('intents'),
  retry: _noRetry,
);
final homeWidgetsProvider = Provider<HomeWidgetsFacade>(
  (ref) => _unavailable('homeWidgets'),
  retry: _noRetry,
);
final tlsSocketProvider = Provider<TlsSocketFacade>(
  (ref) => _unavailable('tlsSocket'),
  retry: _noRetry,
);
final sftpProvider = Provider<SftpFacade>(
  (ref) => _unavailable('sftp'),
  retry: _noRetry,
);
final authBrowserProvider = Provider<AuthBrowserFacade>(
  (ref) => _unavailable('authBrowser'),
  retry: _noRetry,
);
final networkStatusProvider = Provider<NetworkStatusFacade>(
  (ref) => _unavailable('networkStatus'),
  retry: _noRetry,
);
final multicastProvider = Provider<MulticastFacade>(
  (ref) => _unavailable('multicast'),
  retry: _noRetry,
);
final tlsServerProvider = Provider<TlsServerFacade>(
  (ref) => _unavailable('tlsServer'),
  retry: _noRetry,
);
final purchasesProvider = Provider<PurchasesFacade>(
  (ref) => _unavailable('purchases'),
  retry: _noRetry,
);
final speechSynthesisProvider = Provider<SpeechSynthesisFacade>(
  (ref) => _unavailable('speechSynthesis'),
  retry: _noRetry,
);
final textRecognitionProvider = Provider<TextRecognitionFacade>(
  (ref) => _unavailable('textRecognition'),
  retry: _noRetry,
);
final translationProvider = Provider<TranslationFacade>(
  (ref) => _unavailable('translation'),
  retry: _noRetry,
);
final mediaBrowseProvider = Provider<MediaBrowseFacade>(
  (ref) => _unavailable('mediaBrowse'),
  retry: _noRetry,
);
final alarmProvider = Provider<AlarmFacade>(
  (ref) => _unavailable('alarm'),
  retry: _noRetry,
);
final captionStyleProvider = Provider<CaptionStyleFacade>(
  (ref) => _unavailable('captionStyle'),
  retry: _noRetry,
);

/// Which player owns the OS media session right now (ADR-029). Only the owner
/// answers lock-screen, notification, headset and car commands. A player sets
/// itself as owner when it starts playing and clears ownership only if it is
/// still the owner; the other players watch this and let go.
final mediaSessionOwnerProvider =
    NotifierProvider<MediaSessionOwner, MediaSessionKind?>(
      MediaSessionOwner.new,
    );

final class MediaSessionOwner extends Notifier<MediaSessionKind?> {
  @override
  MediaSessionKind? build() => null;

  /// Makes [kind] the owner (the player that just started playing).
  // A verb reads better at call sites than `owner.state = kind`.
  // ignore: use_setters_to_change_properties
  void claim(MediaSessionKind kind) => state = kind;

  /// Gives up ownership if [kind] still holds it.
  void release(MediaSessionKind kind) {
    if (state == kind) state = null;
  }
}
