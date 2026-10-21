import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/vault/vault_manager.dart';
import 'package:mediahro/features/photos/vault/vault_mover.dart';
import 'package:mediahro/images/pipeline/image_io.dart';
import 'package:mediahro/platform/platform_facades.dart';

// A platform without OS crypto or a no-backup folder stays that way for the
// process: Riverpod's automatic retry must not keep the screens waiting.
Duration? _noRetry(int retryCount, Object error) => null;

/// Where the vault lives: a folder the OS never backs up (ADR-008). There is
/// no fallback: where the platform has no such folder the vault is not
/// offered, rather than put in one that a backup would copy.
final FutureProvider<Directory> vaultRootProvider = FutureProvider<Directory>((
  ref,
) async {
  final uri = await ref.watch(imagingProvider).noBackupDirectory('vault');
  return Directory(uri.toFilePath());
}, retry: _noRetry);

/// The vault as a whole. Fails with [PlatformCapabilityUnavailable] where the
/// platform has no OS crypto yet (ADR-039) or no folder that stays out of
/// backups, so the vault can never run on pure-Dart crypto.
final FutureProvider<VaultManager> vaultManagerProvider =
    FutureProvider<VaultManager>((ref) async {
      final manager = VaultManager(
        root: await ref.watch(vaultRootProvider.future),
        crypto: ref.watch(vaultCryptoProvider),
        secure: ref.watch(secureStorageProvider),
      );
      // A stopped reset or set-up is finished before any screen asks.
      await manager.recoverPending();
      return manager;
    }, retry: _noRetry);

/// What the vault screens show now.
class VaultState {
  const VaultState({this.vault});

  /// Null while locked.
  final OpenVault? vault;

  bool get isOpen => vault != null && !vault!.isClosed;
}

/// Who has the vault open (IMG-011). The PIN token and the keystore handle
/// live in memory only while it is open; locking drops them.
class VaultSession extends Notifier<VaultState> {
  // Kept beside the state: a dispose callback may not read the state.
  OpenVault? _vault;

  @override
  VaultState build() {
    ref.onDispose(() {
      final v = _vault;
      _vault = null;
      if (v != null) unawaited(v.close());
    });
    return const VaultState();
  }

  Future<VaultManager> _manager() => ref.read(vaultManagerProvider.future);

  void _adopt(VaultOpenResult r) {
    final old = state.vault;
    if (old != null && !identical(old, r.vault)) unawaited(old.close());
    if (r.isOpen) {
      _vault = r.vault;
      state = VaultState(vault: r.vault);
    }
  }

  /// Opens with the PIN.
  Future<VaultOpenResult> unlockWithPin(String pin) async {
    final r = await (await _manager()).openWithPin(pin);
    _adopt(r);
    return r;
  }

  /// Opens with the fingerprint or screen lock.
  Future<VaultOpenResult> unlockWithFingerprint() async {
    final r = await (await _manager()).openWithFingerprint();
    _adopt(r);
    return r;
  }

  /// Makes the vaults the first time and opens the one [pin] belongs to.
  Future<VaultOpenResult> setUp({
    required String pin,
    String? secondPin,
    bool fingerprint = false,
  }) async {
    final r = await (await _manager()).setUp(
      pin: pin,
      decoyPin: secondPin,
      fingerprint: fingerprint,
    );
    _adopt(r);
    return r;
  }

  /// [lock] for a place a provider may not be changed (a widget's dispose):
  /// the vault closes at once and the state follows a moment later.
  void lockSoon() {
    final v = _vault;
    if (v == null) return;
    _vault = null;
    unawaited(v.close());
    scheduleMicrotask(() {
      if (ref.mounted) state = const VaultState();
    });
  }

  /// Closes the vault: the PIN token is zeroed and the keystore handle
  /// released.
  void lock() {
    final v = _vault;
    if (v == null) return;
    _vault = null;
    state = const VaultState();
    unawaited(v.close());
  }
}

final vaultSessionProvider = NotifierProvider<VaultSession, VaultState>(
  VaultSession.new,
);

/// Whether fingerprint unlock is turned on (it is a switch inside the vault;
/// on the lock screen it only decides whether the button shows).
final FutureProvider<bool> vaultFingerprintOnProvider =
    FutureProvider.autoDispose<bool>((ref) async {
      ref.watch(vaultSessionProvider);
      final m = await ref.watch(vaultManagerProvider.future);
      return await m.fingerprintOn;
    });

/// Whether a vault has been set up.
final FutureProvider<bool> vaultExistsProvider =
    FutureProvider.autoDispose<bool>((ref) async {
      ref.watch(vaultSessionProvider);
      final m = await ref.watch(vaultManagerProvider.future);
      return m.exists;
    });

/// Moves photos into the vault.
final vaultMoverProvider = Provider<VaultMover>(
  (ref) => VaultMover(
    files: ref.watch(photoFilesProvider),
    io: MountedImageIo(ref.watch(mountsProvider)),
    db: ref.watch(libraryDatabaseProvider),
    pipeline: ref.watch(imagePipelineProvider),
    listFolder: (file) async {
      final mounts = ref.read(mountsProvider);
      final dir = file.replace(
        pathSegments: file.pathSegments.sublist(
          0,
          file.pathSegments.length - 1,
        ),
      );
      return [
        await for (final e in mounts.forUri(file).list(dir))
          if (!e.isDirectory) e.uri,
      ];
    },
  ),
);

/// Keeps the window out of screenshots, screen recordings and the app
/// switcher while any vault screen is up (ADR-039). Counted, so a screen
/// opening over another one does not switch it off early.
class SecureWindowScope {
  SecureWindowScope(this._ref);

  final Ref _ref;
  int _depth = 0;

  void enter() {
    if (_depth++ == 0) {
      unawaited(_set(secure: true));
    }
  }

  void leave() {
    if (_depth == 0) return;
    if (--_depth == 0) {
      unawaited(_set(secure: false));
    }
  }

  Future<void> _set({required bool secure}) async {
    try {
      await _ref.read(secureWindowProvider).setSecure(secure: secure);
    } on Object {
      // A platform without it, or a window that is gone.
    }
  }
}

final secureWindowScopeProvider = Provider<SecureWindowScope>(
  SecureWindowScope.new,
);
