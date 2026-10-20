import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/vault/vault_keys.dart';
import 'package:mediahro/features/photos/vault/vault_mover.dart';
import 'package:mediahro/features/photos/vault/vault_store.dart';
import 'package:mediahro/images/pipeline/image_io.dart';
import 'package:mediahro/platform/platform_facades.dart';

/// Where the vault lives: a folder the OS never backs up (ADR-008), or a
/// private folder of the app where the platform has no such thing.
final FutureProvider<Directory> vaultRootProvider = FutureProvider<Directory>((
  ref,
) async {
  try {
    final uri = await ref.watch(imagingProvider).noBackupDirectory('vault');
    return Directory(uri.toFilePath());
  } on Object {
    return Directory(
      '${ref.watch(appDataDirectoryProvider).path}${Platform.pathSeparator}vault-private',
    );
  }
});

/// The vault's keys; fails with [PlatformCapabilityUnavailable] where the
/// platform has no secure storage or biometrics facade.
final FutureProvider<VaultKeys> vaultKeysProvider = FutureProvider<VaultKeys>(
  (ref) async => VaultKeys(
    root: await ref.watch(vaultRootProvider.future),
    secure: ref.watch(secureStorageProvider),
    biometrics: ref.watch(biometricsProvider),
  ),
);

/// What the vault screen is showing now.
class VaultState {
  const VaultState({this.store, this.decoy = false});

  /// Null while locked.
  final VaultStore? store;

  /// The decoy vault is open (it looks the same).
  final bool decoy;

  bool get isOpen => store != null;
}

/// Who has the vault open (IMG-011). The master key lives in memory only
/// while it is open; locking drops it.
class VaultSession extends Notifier<VaultState> {
  @override
  VaultState build() => const VaultState();

  /// Opens the vault with the device's biometric / screen-lock prompt.
  Future<VaultUnlock> unlock(String reason) async {
    final keys = await ref.read(vaultKeysProvider.future);
    final r = await keys.unlock(reason: reason);
    if (r.result == VaultUnlock.opened) {
      state = VaultState(store: r.store);
    }
    return r.result;
  }

  /// Makes the vault the first time.
  Future<VaultUnlock> setUp() async {
    final keys = await ref.read(vaultKeysProvider.future);
    if (!await keys.available()) return VaultUnlock.unavailable;
    state = VaultState(store: await keys.create());
    return VaultUnlock.opened;
  }

  /// Opens the decoy vault with its PIN.
  Future<VaultUnlock> unlockWithPin(String pin) async {
    final keys = await ref.read(vaultKeysProvider.future);
    final r = await keys.unlockDecoy(pin);
    if (r.result == VaultUnlock.opened) {
      state = VaultState(store: r.store, decoy: true);
    }
    return r.result;
  }

  void lock() => state = const VaultState();
}

final vaultSessionProvider = NotifierProvider<VaultSession, VaultState>(
  VaultSession.new,
);

/// Moves photos into the vault.
final vaultMoverProvider = Provider<VaultMover>(
  (ref) => VaultMover(
    files: ref.watch(photoFilesProvider),
    io: MountedImageIo(ref.watch(mountsProvider)),
    db: ref.watch(libraryDatabaseProvider),
    pipeline: ref.watch(imagePipelineProvider),
  ),
);
