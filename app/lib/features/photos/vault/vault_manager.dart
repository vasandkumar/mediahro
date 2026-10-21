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

  /// The PIN chosen is one another vault already uses.
  pinNotAllowed,
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
    this.minRounds = vaultKdfIterations,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Directory root;
  final VaultCryptoFacade crypto;
  final SecureStorageFacade secure;
  final int iterations;

  /// The fewest rounds a salt file may name; a file that names fewer is read
  /// as this many.
  final int minRounds;
  static const int maxRounds = 10000000;
  final DateTime Function() _clock;

  static const String _bioKey = 'photos.vault.fingerprint';
  static const String _attemptsKey = 'photos.vault.attempts';
  static final List<int> _bioAad = utf8.encode('MVL2 fingerprint');

  /// Wrong PINs that cost nothing, then the wait starts at 30 s and doubles,
  /// to a day.
  static const int freeAttempts = 3;
  static const Duration firstWait = Duration(seconds: 30);
  static const Duration longestWait = Duration(days: 1);

  /// A miss is forgiven after four hours.
  static const double missesForgivenPerHour = 0.25;

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

  File _saltNextFile(Directory d) =>
      File('${d.path}${Platform.pathSeparator}salt.next');

  Future<void> _writeSalt(
    Directory d,
    Uint8List salt,
    int rounds, {
    bool next = false,
  }) async {
    final b = BytesBuilder()
      ..add(salt)
      ..add((ByteData(4)..setUint32(0, rounds)).buffer.asUint8List());
    final target = next ? _saltNextFile(d) : _saltFile(d);
    final part = File('${target.path}.part');
    try {
      await part.writeAsBytes(b.takeBytes(), flush: true);
      await part.rename(target.path);
    } on Object {
      if (part.existsSync()) part.deleteSync();
      rethrow;
    }
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

  // ---- wrong PINs ------------------------------------------------------

  Future<_Misses> _loadMisses() async {
    final now = _clock().millisecondsSinceEpoch;
    final raw = await secure.read(_attemptsKey);
    final parts = raw?.split(':');
    if (parts == null || parts.length != 4 || parts[0] != 'v2') {
      return _Misses(0, now, 0);
    }
    var count = double.tryParse(parts[1]) ?? 0;
    final stamp = int.tryParse(parts[2]) ?? now;
    var until = int.tryParse(parts[3]) ?? 0;
    // A clock set back earns no forgiveness and cannot stretch a wait past
    // the longest one.
    final hours = now > stamp
        ? (now - stamp) / Duration.millisecondsPerHour
        : 0;
    count = max<double>(0, count - hours * missesForgivenPerHour);
    final cap = now + longestWait.inMilliseconds;
    if (until > cap) until = cap;
    return _Misses(count, now, until);
  }

  Future<void> _saveMisses(_Misses m) => secure.write(
    _attemptsKey,
    'v2:${m.count.toStringAsFixed(4)}:${m.stamp}:${m.until}',
  );

  Duration _waitFor(double misses) {
    final n = misses.ceil();
    if (n <= freeAttempts) return Duration.zero;
    final wait = firstWait * (1 << min(n - freeAttempts - 1, 12));
    return wait > longestWait ? longestWait : wait;
  }

  /// Counts an attempt BEFORE the work that tells whether the PIN is right,
  /// so stopping the app in the middle buys no free guess. Null: go ahead;
  /// otherwise the wait still to run. Misses are not cleared by success
  /// (whoever holds one PIN cannot reset the count for the other); they fade
  /// by [missesForgivenPerHour].
  Future<Duration?> _countAttempt() async {
    final m = await _loadMisses();
    final left = Duration(milliseconds: m.until - m.stamp);
    if (left > Duration.zero) return left;
    final next = _Misses(m.count + 1, m.stamp, 0);
    final wait = _waitFor(next.count);
    await _saveMisses(
      _Misses(
        next.count,
        next.stamp,
        wait == Duration.zero ? 0 : m.stamp + wait.inMilliseconds,
      ),
    );
    return null;
  }

  /// Gives back the attempt that [_countAttempt] counted (a PIN that opened
  /// the vault it was for); earlier misses stay.
  Future<void> _refundAttempt() async {
    final m = await _loadMisses();
    final count = max<double>(0, m.count - 1);
    await _saveMisses(_Misses(count, m.stamp, 0));
  }

  /// The wait now running, if any.
  Future<Duration?> _waitLeft() async {
    final m = await _loadMisses();
    final left = Duration(milliseconds: m.until - m.stamp);
    return left > Duration.zero ? left : null;
  }

  // ---- opening with a PIN ----------------------------------------------

  /// The salt (and rounds) of [d], or of the pair a cut-off Change PIN left
  /// beside it. The rounds are kept within [minRounds] and [maxRounds], so a
  /// salt file edited to make the PIN cheap to guess does not.
  Future<({Uint8List salt, int rounds})?> _readSalt(
    Directory d, {
    bool next = false,
  }) async {
    final f = next ? _saltNextFile(d) : _saltFile(d);
    if (!f.existsSync()) return null;
    final b = await f.readAsBytes();
    if (b.length != 20) return null;
    final rounds = ByteData.sublistView(b).getUint32(16);
    return (
      salt: Uint8List.fromList(b.sublist(0, 16)),
      rounds: rounds.clamp(minRounds, maxRounds),
    );
  }

  /// Tries a PIN on the folder [d]: the pair of files it normally has, and
  /// the pair a Change PIN that was cut short wrote. The pair that opens
  /// becomes the folder's, the other is removed.
  Future<VaultContainer?> _openDir(
    Directory d,
    VaultKeyHandle master,
    Future<Uint8List>? current,
    Future<Uint8List>? pending,
  ) async {
    final tokens = <Uint8List?>[
      if (current == null) null else await current,
      if (pending == null) null else await pending,
    ];
    try {
      for (var s = 0; s < 2; s++) {
        final token = tokens[s];
        if (token == null) continue;
        for (final nextIndex in [false, true]) {
          if (nextIndex &&
              !File(
                '${d.path}${Platform.pathSeparator}${VaultContainer.indexName}'
                '${VaultContainer.nextSuffix}',
              ).existsSync()) {
            continue;
          }
          try {
            final c = await VaultContainer.open(
              directory: d,
              crypto: crypto,
              master: master,
              token: token,
              next: nextIndex,
            );
            await _settle(d, saltNext: s == 1, indexNext: nextIndex);
            return c;
          } on VaultCorrupt {
            // Not this pair.
          }
        }
      }
      return null;
    } finally {
      for (final t in tokens) {
        t?.fillRange(0, t.length, 0);
      }
    }
  }

  /// Makes the pair that opened the folder's own and drops what is left of
  /// the other.
  Future<void> _settle(
    Directory d, {
    required bool saltNext,
    required bool indexNext,
  }) async {
    final sep = Platform.pathSeparator;
    final index = '${d.path}$sep${VaultContainer.indexName}';
    final indexNextFile = File('$index${VaultContainer.nextSuffix}');
    try {
      if (saltNext) await _saltNextFile(d).rename(_saltFile(d).path);
      if (indexNext) await indexNextFile.rename(index);
      if (_saltNextFile(d).existsSync()) _saltNextFile(d).deleteSync();
      if (indexNextFile.existsSync()) indexNextFile.deleteSync();
    } on FileSystemException {
      // The pair that opened still opens next time.
    }
  }

  /// Opens the vault [pin] belongs to. Both vaults are tried every time, so
  /// a right PIN of either costs the same as a wrong one, and the attempt is
  /// counted before the work starts.
  Future<VaultOpenResult> openWithPin(String pin) async {
    final dirs = _dirs();
    if (dirs.isEmpty) return const VaultOpenResult(VaultOutcome.needsSetup);
    final wait = await _countAttempt();
    if (wait != null) {
      return VaultOpenResult(VaultOutcome.waitToRetry, wait: wait);
    }
    VaultKeyHandle? master;
    try {
      final cur = <Future<Uint8List>?>[];
      final nxt = <Future<Uint8List>?>[];
      for (final d in dirs) {
        final a = await _readSalt(d);
        final b = await _readSalt(d, next: true);
        cur.add(a == null ? null : derivePinToken(pin, a.salt, a.rounds));
        nxt.add(b == null ? null : derivePinToken(pin, b.salt, b.rounds));
      }
      master = await crypto.openMasterKey(requireBiometry: false);
      VaultContainer? found;
      var lost = 0;
      for (var i = 0; i < dirs.length; i++) {
        try {
          final c = await _openDir(dirs[i], master, cur[i], nxt[i]);
          if (c == null) continue;
          if (found == null) {
            found = c;
          } else {
            c.close();
          }
        } on VaultCryptoException catch (e) {
          // One folder whose key is gone or whose data is damaged is not
          // this PIN's vault; it must not shut out the other.
          if (e.error == VaultCryptoError.keyLost ||
              e.error == VaultCryptoError.keyInvalidated ||
              e.error == VaultCryptoError.integrityFailure) {
            lost++;
          } else {
            rethrow;
          }
        }
      }
      if (found != null) {
        await _refundAttempt();
        return VaultOpenResult(
          VaultOutcome.opened,
          vault: OpenVault._(found, this, master),
        );
      }
      await crypto.close(master);
      if (lost == dirs.length) {
        return const VaultOpenResult(VaultOutcome.keyLost);
      }
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

  /// Gives the open vault a new PIN, safely: the new index and the new salt
  /// are written beside the old ones, then swapped in, and opening takes
  /// whichever pair the PIN fits, so a stop at any moment leaves a vault that
  /// opens. The new PIN is first tried on the other vaults (counted like any
  /// attempt): one of theirs is refused, because the two would collide. The
  /// fingerprint is turned off if it was on for this vault (it held the old
  /// token). Returns [VaultOutcome.opened] when it worked,
  /// [VaultOutcome.pinNotAllowed] for a PIN another vault uses.
  Future<VaultOutcome> changePin(OpenVault vault, String newPin) async {
    final here = vault.container.directory;
    final wait = await _countAttempt();
    if (wait != null) return VaultOutcome.waitToRetry;
    // Does the new PIN already open another vault?
    for (final d in _dirs()) {
      if (d.path == here.path) continue;
      final a = await _readSalt(d);
      final b = await _readSalt(d, next: true);
      final other = await _openDir(
        d,
        vault._master,
        a == null ? null : derivePinToken(newPin, a.salt, a.rounds),
        b == null ? null : derivePinToken(newPin, b.salt, b.rounds),
      );
      if (other != null) {
        other.close();
        return VaultOutcome.pinNotAllowed;
      }
    }
    final salt = randomBytes(16);
    final token = await derivePinToken(newPin, salt, iterations);
    try {
      await vault.container.prepareRekey(token);
      await _writeSalt(here, salt, iterations, next: true);
      await vault.container.commitRekey(token);
      await _saltNextFile(here).rename(_saltFile(here).path);
    } on Object {
      await vault.container.abandonRekey();
      if (_saltNextFile(here).existsSync()) _saltNextFile(here).deleteSync();
      rethrow;
    } finally {
      token.fillRange(0, token.length, 0);
    }
    final raw = await secure.read(_bioKey);
    if (raw != null) {
      final j = jsonDecode(raw) as Map<String, Object?>;
      if (j['d'] == here.path.split(Platform.pathSeparator).last) {
        await secure.delete(_bioKey);
      }
    }
    return VaultOutcome.opened;
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

/// How many wrong guesses are on record, when that was last worked out, and
/// until when the next try must wait (milliseconds since the epoch).
final class _Misses {
  const _Misses(this.count, this.stamp, this.until);

  final double count;
  final int stamp;
  final int until;
}
