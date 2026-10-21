import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:mediahro/features/photos/vault/vault_container.dart';
import 'package:mediahro/features/photos/vault/vault_framing.dart';
import 'package:mediahro/features/photos/vault/vault_kdf.dart';
import 'package:mediahro/platform/security.dart';
import 'package:mediahro/platform/vault_crypto.dart';
import 'package:meta/meta.dart';

/// What came of an attempt to open the vault.
enum VaultOutcome {
  opened,

  /// No vault yet.
  needsSetup,

  /// The PIN opens nothing. The same answer whatever the PIN is near to.
  wrongPin,

  /// Too many wrong PINs; try again after [VaultOpenResult.wait].
  waitToRetry,

  /// The user backed out of the fingerprint or screen-lock prompt.
  cancelled,

  /// The device has no fingerprint, face or screen lock to ask.
  notEnrolled,

  /// The OS invalidated the fingerprint key (a fingerprint was added or the
  /// screen lock removed): the fingerprint no longer opens the vault. The PIN
  /// still does.
  fingerprintInvalidated,

  /// The keystore key is gone (a restore on another device, a keystore
  /// reset): the vault cannot be opened any more.
  keyLost,

  /// The OS asked to wait before trying the fingerprint again.
  lockedOut,

  /// The fingerprint or screen lock was rejected.
  authFailed,

  /// No OS crypto here, or it failed for another reason.
  unavailable,

  /// The vault's files do not match any more.
  damaged,

  /// Fingerprint unlock is not turned on.
  noFingerprint,
}

/// A vault that is open: its container and the keystore handle behind it.
/// Closing it zeroes the PIN token and releases the handle.
final class OpenVault {
  OpenVault._(this.container, this._manager, this._master);

  final VaultContainer container;
  final VaultManager _manager;
  final VaultKeyHandle _master;
  bool _closed = false;

  bool get isClosed => _closed;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    container.close();
    try {
      await _manager.crypto.close(_master);
    } on Object {
      // Released with the process at the latest.
    }
  }
}

@immutable
final class VaultOpenResult {
  const VaultOpenResult(this.outcome, {this.vault, this.wait});

  final VaultOutcome outcome;
  final OpenVault? vault;
  final Duration? wait;

  bool get isOpen => outcome == VaultOutcome.opened;
}

/// The vault as a whole (IMG-011, PRIV-007; ADR-008, ADR-039, ADR-040): two
/// containers in a folder the OS never backs up, one opened by each PIN.
/// They are made together at set-up, are named at random and hold the same
/// files, so nothing on disk says which is which; the screen, the menus and
/// the flow are identical for both. Fingerprint unlock is optional and opens
/// the vault it was turned on in.
///
/// Each container's token comes from a PIN through PBKDF2 on an isolate, is
/// never stored, and binds the encrypted index; the keys of the files are
/// wrapped by a keystore key that does not leave the device. A wrong PIN is
/// answered after the same work as a right one and, from the fourth miss on,
/// with a wait that doubles each time and survives restarts.
final class VaultManager {
  VaultManager({
    required this.root,
    required this.crypto,
    required this.secure,
    this.iterations = vaultKdfIterations,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Directory root;
  final VaultCryptoFacade crypto;
  final SecureStorageFacade secure;
  final int iterations;
  final DateTime Function() _clock;

  static const String _bioKey = 'photos.vault.fingerprint';
  static const String _attemptsKey = 'photos.vault.attempts';
  static final List<int> _bioAad = utf8.encode('MVL2 fingerprint');

  /// Wrong PINs that cost nothing, then the wait starts at 30 s and doubles,
  /// to a day.
  static const int freeAttempts = 3;
  static const Duration firstWait = Duration(seconds: 30);
  static const Duration longestWait = Duration(days: 1);

  static final RegExp _dirName = RegExp(r'^[0-9a-f]{16}$');

  List<Directory> _dirs() {
    if (!root.existsSync()) return const [];
    return [
      for (final e in root.listSync(followLinks: false))
        if (e is Directory &&
            _dirName.hasMatch(e.path.split(Platform.pathSeparator).last))
          e,
    ]..sort((a, b) => a.path.compareTo(b.path));
  }

  /// Whether a vault has been set up.
  bool get exists => _dirs().isNotEmpty;

  File _saltFile(Directory d) => File('${d.path}${Platform.pathSeparator}salt');

  Future<({Uint8List salt, int rounds})> _salt(Directory d) async {
    final b = await _saltFile(d).readAsBytes();
    if (b.length != 20) throw const VaultCorrupt('salt');
    return (
      salt: Uint8List.sublistView(b, 0, 16),
      rounds: ByteData.sublistView(b).getUint32(16),
    );
  }

  Future<void> _writeSalt(Directory d, Uint8List salt, int rounds) async {
    final b = BytesBuilder()
      ..add(salt)
      ..add((ByteData(4)..setUint32(0, rounds)).buffer.asUint8List());
    final part = File('${_saltFile(d).path}.part');
    await part.writeAsBytes(b.takeBytes(), flush: true);
    await part.rename(_saltFile(d).path);
  }

  static String _randomName() =>
      randomBytes(8).map((x) => x.toRadixString(16).padLeft(2, '0')).join();

  /// A PIN nobody knows, for a vault the user did not ask for.
  static String randomPin() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(10)).join();
  }

  /// Maps the facade's failures to the answers the screen words.
  static VaultOutcome outcomeOf(VaultCryptoException e) => switch (e.error) {
    VaultCryptoError.cancelled => VaultOutcome.cancelled,
    VaultCryptoError.notEnrolled => VaultOutcome.notEnrolled,
    VaultCryptoError.keyInvalidated => VaultOutcome.fingerprintInvalidated,
    VaultCryptoError.keyLost => VaultOutcome.keyLost,
    VaultCryptoError.lockedOut => VaultOutcome.lockedOut,
    VaultCryptoError.authFailed => VaultOutcome.authFailed,
    VaultCryptoError.integrityFailure => VaultOutcome.damaged,
    VaultCryptoError.unavailable => VaultOutcome.unavailable,
  };

  // ---- set-up ----------------------------------------------------------

  /// Makes both vaults and returns the one [pin] opens. [decoyPin] is the
  /// other's PIN; none given, the other vault is made with a PIN nobody
  /// knows, so it is there all the same. With [fingerprint] the fingerprint
  /// (or screen lock) opens the new vault too.
  Future<VaultOpenResult> setUp({
    required String pin,
    String? decoyPin,
    bool fingerprint = false,
  }) async {
    if (exists) return const VaultOpenResult(VaultOutcome.damaged);
    final VaultKeyHandle master;
    try {
      master = await crypto.openMasterKey(requireBiometry: false);
    } on VaultCryptoException catch (e) {
      return VaultOpenResult(outcomeOf(e));
    }
    final made = <Directory>[];
    try {
      final pins = [pin, decoyPin ?? randomPin()];
      final order = [0, 1]..shuffle(Random.secure());
      final salts = [randomBytes(16), randomBytes(16)];
      final tokens = await Future.wait([
        for (var i = 0; i < 2; i++)
          derivePinToken(pins[i], salts[i], iterations),
      ]);
      VaultContainer? real;
      for (final i in order) {
        final dir = Directory(
          '${root.path}${Platform.pathSeparator}${_randomName()}',
        );
        made.add(dir);
        await dir.create(recursive: true);
        await _writeSalt(dir, salts[i], iterations);
        final c = await VaultContainer.create(
          directory: dir,
          crypto: crypto,
          master: master,
          token: tokens[i],
        );
        if (i == 0) {
          real = c;
        } else {
          c.close();
        }
      }
      for (final t in tokens) {
        t.fillRange(0, t.length, 0);
      }
      final vault = OpenVault._(real!, this, master);
      if (fingerprint) {
        final r = await setFingerprint(vault, enabled: true);
        if (r != VaultOutcome.opened) {
          // The vault exists; the fingerprint can be turned on later.
        }
      }
      return VaultOpenResult(VaultOutcome.opened, vault: vault);
    } on Object catch (e) {
      for (final d in made) {
        if (d.existsSync()) d.deleteSync(recursive: true);
      }
      try {
        await crypto.close(master);
      } on Object {
        // Nothing to release.
      }
      if (e is VaultCryptoException) return VaultOpenResult(outcomeOf(e));
      return const VaultOpenResult(VaultOutcome.unavailable);
    }
  }

  // ---- PIN -------------------------------------------------------------

  Future<Duration?> _waitLeft() async {
    final raw = await secure.read(_attemptsKey);
    if (raw == null) return null;
    final parts = raw.split(':');
    if (parts.length != 2) return null;
    final until = int.tryParse(parts[1]);
    if (until == null) return null;
    final left = DateTime.fromMillisecondsSinceEpoch(until)
        .difference(_clock());
    return left > Duration.zero ? left : null;
  }

  Future<void> _recordMiss() async {
    final raw = await secure.read(_attemptsKey);
    var n = int.tryParse(raw?.split(':').first ?? '') ?? 0;
    n++;
    var until = 0;
    if (n > freeAttempts) {
      final factor = 1 << min(n - freeAttempts - 1, 12);
      final wait = firstWait * factor;
      until = _clock()
          .add(wait > longestWait ? longestWait : wait)
          .millisecondsSinceEpoch;
    }
    await secure.write(_attemptsKey, '$n:$until');
  }

  Future<void> _forgetMisses() => secure.delete(_attemptsKey);

  /// Opens the vault [pin] belongs to. Both vaults are tried every time, so
  /// a right PIN of either costs the same as a wrong one.
  Future<VaultOpenResult> openWithPin(String pin) async {
    final dirs = _dirs();
    if (dirs.isEmpty) return const VaultOpenResult(VaultOutcome.needsSetup);
    final wait = await _waitLeft();
    if (wait != null) {
      return VaultOpenResult(VaultOutcome.waitToRetry, wait: wait);
    }
    VaultKeyHandle? master;
    final tokens = <Uint8List>[];
    try {
      final salts = [for (final d in dirs) await _salt(d)];
      tokens.addAll(
        await Future.wait([
          for (final s in salts) derivePinToken(pin, s.salt, s.rounds),
        ]),
      );
      master = await crypto.openMasterKey(requireBiometry: false);
      VaultContainer? found;
      for (var i = 0; i < dirs.length; i++) {
        try {
          final c = await VaultContainer.open(
            directory: dirs[i],
            crypto: crypto,
            master: master,
            token: tokens[i],
          );
          found ??= c;
          if (!identical(found, c)) c.close();
        } on VaultCorrupt {
          // Not this one.
        }
      }
      if (found != null) {
        await _forgetMisses();
        return VaultOpenResult(
          VaultOutcome.opened,
          vault: OpenVault._(found, this, master),
        );
      }
      await crypto.close(master);
      await _recordMiss();
      final left = await _waitLeft();
      return left == null
          ? const VaultOpenResult(VaultOutcome.wrongPin)
          : VaultOpenResult(VaultOutcome.waitToRetry, wait: left);
    } on VaultCryptoException catch (e) {
      if (master != null) await crypto.close(master);
      // The vault's own key (not the fingerprint's) no longer unwraps.
      final o = outcomeOf(e);
      return VaultOpenResult(
        o == VaultOutcome.fingerprintInvalidated ? VaultOutcome.keyLost : o,
      );
    } on Object {
      if (master != null) await crypto.close(master);
      return const VaultOpenResult(VaultOutcome.damaged);
    } finally {
      for (final t in tokens) {
        t.fillRange(0, t.length, 0);
      }
    }
  }

  // ---- fingerprint -----------------------------------------------------

  /// Whether the fingerprint opens a vault.
  Future<bool> get fingerprintOn async => await secure.read(_bioKey) != null;

  /// Opens the vault the fingerprint (or screen lock) was turned on in.
  Future<VaultOpenResult> openWithFingerprint() async {
    final raw = await secure.read(_bioKey);
    if (raw == null) return const VaultOpenResult(VaultOutcome.noFingerprint);
    final dirs = _dirs();
    if (dirs.isEmpty) return const VaultOpenResult(VaultOutcome.needsSetup);
    VaultKeyHandle? bio;
    VaultKeyHandle? master;
    Uint8List? token;
    try {
      final j = jsonDecode(raw) as Map<String, Object?>;
      final dir = dirs.firstWhere(
        (d) => d.path.split(Platform.pathSeparator).last == j['d'],
      );
      bio = await crypto.openMasterKey(requireBiometry: true);
      final wrapped = await crypto.adoptFileKey(
        bio,
        base64Decode(j['k']! as String),
      );
      token = await crypto.open(
        wrapped,
        base64Decode(j['n']! as String),
        Uint8List.fromList(_bioAad),
        base64Decode(j['s']! as String),
      );
      await crypto.close(bio);
      bio = null;
      master = await crypto.openMasterKey(requireBiometry: false);
      final c = await VaultContainer.open(
        directory: dir,
        crypto: crypto,
        master: master,
        token: token,
      );
      await _forgetMisses();
      return VaultOpenResult(
        VaultOutcome.opened,
        vault: OpenVault._(c, this, master),
      );
    } on VaultCryptoException catch (e) {
      final outcome = outcomeOf(e);
      if (outcome == VaultOutcome.fingerprintInvalidated ||
          outcome == VaultOutcome.damaged) {
        // The fingerprint key cannot open anything again; the PIN can.
        await secure.delete(_bioKey);
      }
      if (master != null) await crypto.close(master);
      return VaultOpenResult(outcome);
    } on Object {
      if (master != null) await crypto.close(master);
      await secure.delete(_bioKey);
      return const VaultOpenResult(VaultOutcome.damaged);
    } finally {
      if (bio != null) {
        try {
          await crypto.close(bio);
        } on Object {
          // Released with the process.
        }
      }
      token?.fillRange(0, token.length, 0);
    }
  }

  /// Turns fingerprint unlock on for [vault] (asking for the fingerprint or
  /// screen lock now) or off. Only one vault has it: turning it on in the
  /// other moves it.
  Future<VaultOutcome> setFingerprint(
    OpenVault vault, {
    required bool enabled,
  }) async {
    if (!enabled) {
      await secure.delete(_bioKey);
      return VaultOutcome.opened;
    }
    VaultKeyHandle? bio;
    final token = vault.container.tokenCopy();
    try {
      bio = await crypto.openMasterKey(requireBiometry: true);
      final wrapped = await crypto.newFileKey(bio);
      final nonce = randomBytes(VaultCryptoFacade.nonceLength);
      final sealed = await crypto.seal(
        wrapped,
        nonce,
        Uint8List.fromList(_bioAad),
        token,
      );
      await secure.write(
        _bioKey,
        jsonEncode({
          'd': vault.container.directory.path
              .split(Platform.pathSeparator)
              .last,
          'k': base64Encode(wrapped.bytes),
          'n': base64Encode(nonce),
          's': base64Encode(sealed),
        }),
      );
      return VaultOutcome.opened;
    } on VaultCryptoException catch (e) {
      return outcomeOf(e);
    } finally {
      token.fillRange(0, token.length, 0);
      if (bio != null) {
        try {
          await crypto.close(bio);
        } on Object {
          // Released with the process.
        }
      }
    }
  }

  // ---- changing and ending ---------------------------------------------

  /// Gives the open vault a new PIN. The fingerprint is turned off if it was
  /// on for this vault (it held the old token); turn it on again.
  Future<void> changePin(OpenVault vault, String newPin) async {
    final salt = randomBytes(16);
    final token = await derivePinToken(newPin, salt, iterations);
    try {
      await vault.container.rekey(token);
      await _writeSalt(vault.container.directory, salt, iterations);
      final raw = await secure.read(_bioKey);
      if (raw != null) {
        final j = jsonDecode(raw) as Map<String, Object?>;
        if (j['d'] ==
            vault.container.directory.path.split(Platform.pathSeparator).last) {
          await secure.delete(_bioKey);
        }
      }
    } finally {
      token.fillRange(0, token.length, 0);
    }
  }

  /// Deletes both vaults and everything in them, the fingerprint entry and
  /// the OS key behind them (`VaultCryptoFacade.reset`, ADR-039 amendment 1).
  /// Used when the vault can no longer be opened, after the user confirmed.
  /// The key goes first: if that fails nothing else is touched and the user
  /// can try again.
  Future<void> reset() async {
    await crypto.reset();
    if (root.existsSync()) {
      for (final d in _dirs()) {
        d.deleteSync(recursive: true);
      }
    }
    await secure.delete(_bioKey);
    await secure.delete(_attemptsKey);
  }
}
