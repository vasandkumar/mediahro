import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:mediahro/platform/android/android_caption_style.dart';
import 'package:mediahro/platform/android/android_car.dart';
import 'package:mediahro/platform/android/android_display.dart';
import 'package:mediahro/platform/android/android_home_widgets.dart';
import 'package:mediahro/platform/android/android_media.dart';
import 'package:mediahro/platform/android/android_network.dart';
import 'package:mediahro/platform/android/android_power_status.dart';
import 'package:mediahro/platform/android/android_security.dart';
import 'package:mediahro/platform/android/android_sftp.dart';
import 'package:mediahro/platform/android/android_storage.dart';
import 'package:mediahro/platform/android/android_tls.dart';
import 'package:mediahro/platform/platform_facades.dart';

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
  mediaBrowseProvider.overrideWithValue(AndroidMediaBrowse()),
  alarmProvider.overrideWithValue(AndroidAlarms()),
  homeWidgetsProvider.overrideWithValue(AndroidHomeWidgets()),
  secureStorageProvider.overrideWithValue(AndroidSecureStorage()),
  biometricsProvider.overrideWithValue(AndroidBiometrics()),
  networkStatusProvider.overrideWithValue(AndroidNetworkStatus()),
  multicastProvider.overrideWithValue(AndroidMulticast()),
  authBrowserProvider.overrideWithValue(AndroidAuthBrowser()),
  tlsSocketProvider.overrideWithValue(AndroidTlsSocketFacade()),
  tlsServerProvider.overrideWithValue(AndroidTlsServerFacade()),
  sftpProvider.overrideWithValue(AndroidSftp()),
];
