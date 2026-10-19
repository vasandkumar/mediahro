import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/platform/audio_output.dart';
import 'package:mediahro/platform/cast.dart';
import 'package:mediahro/platform/display.dart';
import 'package:mediahro/platform/enterprise.dart';
import 'package:mediahro/platform/media_session.dart';
import 'package:mediahro/platform/secure_transport.dart';
import 'package:mediahro/platform/security.dart';
import 'package:mediahro/platform/storage.dart';
import 'package:mediahro/platform/system_integration.dart';

export 'audio_output.dart';
export 'cast.dart';
export 'display.dart';
export 'enterprise.dart';
export 'media_session.dart';
export 'secure_transport.dart';
export 'security.dart';
export 'storage.dart';
export 'system_integration.dart';

/// Thrown when a facade has no implementation on this platform/flavour yet
/// or by design; callers map it to "Not available on this device".
final class PlatformCapabilityUnavailable implements Exception {
  const PlatformCapabilityUnavailable(this.capability);

  final String capability;

  @override
  String toString() => 'PlatformCapabilityUnavailable($capability)';
}

Never _unavailable(String name) => throw PlatformCapabilityUnavailable(name);

// One provider per facade (docs/05 §8). Lane C4 overrides each with its
// Pigeon-backed implementation per platform in `platform_bindings.dart`;
// tests override them with fakes. Feature code depends only on these.
final mediaSessionProvider = Provider<MediaSessionFacade>(
  (ref) => _unavailable('mediaSession'),
);
final storageProvider = Provider<StorageFacade>(
  (ref) => _unavailable('storage'),
);
final photoLibraryProvider = Provider<PhotoLibraryFacade>(
  (ref) => _unavailable('photoLibrary'),
);
final audioOutputProvider = Provider<AudioOutputFacade>(
  (ref) => _unavailable('audioOutput'),
);
final castProvider = Provider<CastFacade>((ref) => _unavailable('cast'));
final displayProvider = Provider<DisplayFacade>(
  (ref) => _unavailable('display'),
);
final pipProvider = Provider<PipFacade>((ref) => _unavailable('pip'));
final secureStorageProvider = Provider<SecureStorageFacade>(
  (ref) => _unavailable('secureStorage'),
);
final biometricsProvider = Provider<BiometricsFacade>(
  (ref) => _unavailable('biometrics'),
);
final managedConfigProvider = Provider<ManagedConfigFacade>(
  (ref) => _unavailable('managedConfig'),
);
final kioskProvider = Provider<KioskFacade>((ref) => _unavailable('kiosk'));
final systemIntegrationProvider = Provider<SystemIntegrationFacade>(
  (ref) => _unavailable('systemIntegration'),
);
final intentsProvider = Provider<IntentsFacade>(
  (ref) => _unavailable('intents'),
);
final homeWidgetsProvider = Provider<HomeWidgetsFacade>(
  (ref) => _unavailable('homeWidgets'),
);
final tlsSocketProvider = Provider<TlsSocketFacade>(
  (ref) => _unavailable('tlsSocket'),
);
final sftpProvider = Provider<SftpFacade>((ref) => _unavailable('sftp'));
