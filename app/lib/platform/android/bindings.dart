import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:mediahro/platform/android/android_storage.dart';
import 'package:mediahro/platform/platform_facades.dart';

/// Facade implementations for Android (Kotlin, Media3) through Pigeon files in app/pigeons/android/
/// (lane C4a, ADR-025). Each entry overrides one provider from
/// `platform_facades.dart`; a facade not yet implemented stays unavailable
/// and its callers show "Not available on this device".
List<Override> overrides() => [
  storageProvider.overrideWithValue(AndroidStorage()),
  photoLibraryProvider.overrideWithValue(AndroidPhotoLibrary()),
];
