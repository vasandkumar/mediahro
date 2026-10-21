import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:mediahro/features/video/text/open_text_services.dart';
import 'package:mediahro/platform/android/android_background_work.dart';
import 'package:mediahro/platform/android/android_caption_style.dart';
import 'package:mediahro/platform/android/android_car.dart';
import 'package:mediahro/platform/android/android_display.dart';
import 'package:mediahro/platform/android/android_enterprise.dart';
import 'package:mediahro/platform/android/android_home_widgets.dart';
import 'package:mediahro/platform/android/android_imaging.dart';
import 'package:mediahro/platform/android/android_input.dart';
import 'package:mediahro/platform/android/android_media.dart';
import 'package:mediahro/platform/android/android_motion.dart';
import 'package:mediahro/platform/android/android_network.dart';
import 'package:mediahro/platform/android/android_power_status.dart';
import 'package:mediahro/platform/android/android_purchases.dart';
import 'package:mediahro/platform/android/android_security.dart';
import 'package:mediahro/platform/android/android_sftp.dart';
import 'package:mediahro/platform/android/android_storage.dart';
import 'package:mediahro/platform/android/android_system.dart';
import 'package:mediahro/platform/android/android_text.dart';
import 'package:mediahro/platform/android/android_tls.dart';
import 'package:mediahro/platform/android/android_vault.dart';
import 'package:mediahro/platform/android/presentation_main.dart'
    show presentationMain;
import 'package:mediahro/platform/platform_facades.dart';

/// Dart entry points that native code starts engines at (the external-display
/// page); referenced here so they stay in the compiled program.
const List<Function> nativeEntryPoints = [presentationMain];

/// Facade implementations for Android (Kotlin, Media3) through Pigeon files in app/pigeons/android/
/// (lane C4a, ADR-025). Each entry overrides one provider from
/// `platform_facades.dart`; a facade not yet implemented stays unavailable
/// and its callers show "Not available on this device".
List<Override> overrides() => [
  storageProvider.overrideWithValue(AndroidStorage()),
  photoLibraryProvider.overrideWithValue(AndroidPhotoLibrary()),
  mediaSessionProvider.overrideWithValue(AndroidMediaSession()),
  audioOutputProvider.overrideWithValue(AndroidAudioOutput()),
  displayProvider.overrideWithValue(AndroidDisplay()),
  pipProvider.overrideWithValue(AndroidPip()),
  powerStatusProvider.overrideWithValue(AndroidPowerStatus()),
  captionStyleProvider.overrideWithValue(AndroidCaptionStyle()),
  speechSynthesisProvider.overrideWithValue(AndroidSpeechSynthesis()),
  // OCR, language ID and translation: the open services (ADR-034).
  ...openTextServiceOverrides(),
  mediaBrowseProvider.overrideWithValue(AndroidMediaBrowse()),
  alarmProvider.overrideWithValue(AndroidAlarms()),
  homeWidgetsProvider.overrideWithValue(AndroidHomeWidgets()),
  systemIntegrationProvider.overrideWithValue(AndroidSystemIntegration()),
  intentsProvider.overrideWithValue(AndroidIntents()),
  secureStorageProvider.overrideWithValue(AndroidSecureStorage()),
  biometricsProvider.overrideWithValue(AndroidBiometrics()),
  networkStatusProvider.overrideWithValue(AndroidNetworkStatus()),
  multicastProvider.overrideWithValue(AndroidMulticast()),
  authBrowserProvider.overrideWithValue(AndroidAuthBrowser()),
  tlsSocketProvider.overrideWithValue(AndroidTlsSocketFacade()),
  tlsServerProvider.overrideWithValue(AndroidTlsServerFacade()),
  sftpProvider.overrideWithValue(AndroidSftp()),
  accessibilityPrefsProvider.overrideWithValue(AndroidAccessibilityPrefs()),
  gamepadProvider.overrideWithValue(AndroidGamepad()),
  vaultCryptoProvider.overrideWithValue(AndroidVaultCrypto()),
  motionProvider.overrideWithValue(AndroidMotion()),
  secureWindowProvider.overrideWithValue(AndroidSecureWindow()),
  imagingProvider.overrideWithValue(AndroidImaging()),
  managedConfigProvider.overrideWithValue(AndroidManagedConfig()),
  kioskProvider.overrideWithValue(AndroidKiosk()),
  purchasesProvider.overrideWithValue(AndroidPurchases()),
  backgroundWorkProvider.overrideWithValue(AndroidBackgroundWork()),
];
