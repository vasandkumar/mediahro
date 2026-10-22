import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/platform/android/android_security.dart';
import 'package:mediahro/platform/android/android_storage.dart';
import 'package:mediahro/platform/android/bindings.dart' as android;
import 'package:mediahro/platform/platform_facades.dart';

/// The container the device integration tests build for facade-backed cells
/// (`b2_library_sources_test.dart`): with the Android bindings the storage
/// and secure-storage facades exist, so those cells run on the phone instead
/// of skipping with `pending: C4`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('LIB-002 the Android bindings provide the storage facade', () {
    final c = ProviderContainer(overrides: android.overrides());
    addTearDown(c.dispose);
    expect(c.read(storageProvider), isA<AndroidStorage>());
  });

  test('LIB-013 the Android bindings provide secure storage', () {
    final c = ProviderContainer(overrides: android.overrides());
    addTearDown(c.dispose);
    expect(c.read(secureStorageProvider), isA<AndroidSecureStorage>());
  });

  test('a container without bindings has neither (the old skip)', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(() => c.read(storageProvider), throwsA(anything));
    expect(() => c.read(secureStorageProvider), throwsA(anything));
  });
}
