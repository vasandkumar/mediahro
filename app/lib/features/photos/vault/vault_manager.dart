import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:mediahro/features/photos/vault/vault_bytes.dart';
import 'package:mediahro/features/photos/vault/vault_container.dart';
import 'package:mediahro/features/photos/vault/vault_framing.dart';
import 'package:mediahro/features/photos/vault/vault_kdf.dart';
import 'package:mediahro/features/photos/vault/vault_secret.dart';
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

  /// The PIN chosen has fewer than [VaultManager.minPinLength] digits.
  pinTooShort,
}

/// A vault that is open: its container, the container's secret and the
/// keystore handle opened with it. Closing it zeroes the secret and releases
/// the handle.
final class OpenVault {
  OpenVault._(this.container, this._manager, this._master, this._secret);

  final VaultContainer container;
  final VaultManager _manager;
  final VaultKeyHandle _master;
  final Uint8List _secret;
  bool _closed = false;

  bool get isClosed => _closed;

  /// A copy of the container secret for work that takes a while (a Change
  /// PIN waits for the KDF): the vault locking in the middle zeroes the
  /// original and must not turn this into zeros. Throws [VaultLocked] when the
  /// vault is locked or the secret is already zeroed; the caller zeroes the
  /// copy.
  Uint8List secretCopy() {
    if (_closed || _secret.every((b) => b == 0)) throw const VaultLocked();
    return Uint8List.fromList(_secret);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    container.close();
    wipe(_secret);
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
/// Each container has a random secret S (ADR-039 amendment 2). Everything in
/// the folder is wrapped under a keystore handle opened with S, and S is
/// sealed in a small file under a handle opened with the PIN's token (PBKDF2
/// on an isolate, never stored); on Android every guess costs one operation
/// of a device-bound key, so it cannot be tested away from the phone. Change
/// PIN seals S again and leaves the files alone. A wrong PIN is answered
/// after the same work as a right one and, from the fourth miss on, with a
/// wait that doubles each time and survives restarts.
final class VaultManager {
  VaultManager({
    required this.root,
    required this.crypto,
    required this.secure,
    int iterations = vaultKdfIterations,
    int minRounds = vaultKdfIterations,
    this.kdf = derivePinToken,
    DateTime Function()? clock,
  }) : minRounds = minRounds,
       iterations = iterations.clamp(minRounds, maxRounds),
       _clock = clock ?? DateTime.now;

  final Directory root;
  final VaultCryptoFacade crypto;
  final SecureStorageFacade secure;

  /// Turns a PIN into its token; tests pass one that runs in place, so the
  /// result does not depend on how long an isolate takes to start.
  final PinKdf kdf;

  /// The rounds new PINs are stretched with, kept within [minRounds] and
  /// [maxRounds].
  final int iterations;

  /// The fewest rounds a salt file may name; a file that names fewer is read
  /// as this many.
  final int minRounds;
  static const int maxRounds = 10000000;
  final DateTime Function() _clock;

  /// The fewest digits of a vault PIN. A longer one is what protects the
  /// vault if the phone itself is compromised.
  static const int minPinLength = 6;

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

  /// In the vault root while set-up is making the folders. Deleting it is the
  /// one step that makes them a vault: while it exists there is no vault, and
  /// the next start removes whatever was made.
  static const String _setupMarker = '.setup';

  /// In the vault root while a reset is under way: it was confirmed, so a stop
  /// in the middle is finished (rolled forward) at the next start.
  static const String _resetJournal = '.reset';

  static const String _trashPrefix = '.trash-';

  File get _setupFile =>
      File('${root.path}${Platform.pathSeparator}$_setupMarker');

  File get _resetFile =>
      File('${root.path}${Platform.pathSeparator}$_resetJournal');

  bool get _pending => _setupFile.existsSync() || _resetFile.existsSync();

  List<Directory> _dirs() {
    if (!root.existsSync() || _pending) return const [];
    return [
      for (final e in root.listSync(followLinks: false))
        if (e is Directory &&
            _dirName.hasMatch(e.path.split(Platform.pathSeparator).last))
          e,
    ]..sort((a, b) => a.path.compareTo(b.path));
  }

  Future<void> _flag(File f) async {
    await root.create(recursive: true);
    final part = File('${f.path}.part');
    await part.writeAsBytes(const [], flush: true);
    await part.rename(f.path);
  }

  Future<void> _deleteTrash() async {
    if (!root.existsSync()) return;
    try {
      await for (final e in root.list(followLinks: false)) {
        if (e is Directory &&
            e.path
                .split(Platform.pathSeparator)
                .last
                .startsWith(_trashPrefix)) {
          await e.delete(recursive: true);
        }
      }
    } on FileSystemException {
      // Left for the next time.
    }
  }

  /// Finishes what a stopped reset or set-up left, as the app starts, so the
  /// screens never see a half-done state. Best effort: a failure (the key
  /// cannot be deleted just now) leaves the journal for the next start.
  Future<void> recoverPending() async {
    try {
      await _recover();
    } on Object {
      // Tried again by set-up and at the next start.
    }
  }

  /// Finishes what a stopped reset or set-up left, before anything else. A
  /// reset that was confirmed is rolled forward (folders moved away, the
  /// phone key deleted, folders and the fingerprint and back-off records
  /// deleted); a set-up that did not reach its last step is rolled back (every
  /// folder it made is removed). Throws the keystore's failure if the key
  /// cannot be deleted; the journal then stays and the next start tries again.
  Future<void> _recover() async {
    if (!root.existsSync()) return;
    for (final name in ['$_setupMarker.part', '$_resetJournal.part']) {
      final stale = File('${root.path}${Platform.pathSeparator}$name');
      if (stale.existsSync()) await stale.delete();
    }
    if (_resetFile.existsSync()) {
      await _moveAway();
      await crypto.reset();
      await _deleteTrash();
      await secure.delete(_bioKey);
      await secure.delete(_attemptsKey);
      await _resetFile.delete();
    }
    if (_setupFile.existsSync()) {
      for (final e in root.listSync(followLinks: false)) {
        if (e is Directory &&
            _dirName.hasMatch(e.path.split(Platform.pathSeparator).last)) {
          await e.delete(recursive: true);
        }
      }
      await _setupFile.delete();
    }
    await _deleteTrash();
  }

  /// Renames every vault folder to a name that is not a vault; returns what
  /// was moved, so it can be put back.
  Future<List<(Directory, Directory)>> _moveAway({
    List<(Directory, Directory)>? into,
  }) async {
    final moved = into ?? <(Directory, Directory)>[];
    final dirs = [
      for (final e in root.listSync(followLinks: false))
        if (e is Directory &&
            _dirName.hasMatch(e.path.split(Platform.pathSeparator).last))
          e,
    ];
    for (final d in dirs) {
      final to = Directory(
        '${root.path}${Platform.pathSeparator}$_trashPrefix${_folderName(d)}',
      );
      await d.rename(to.path);
      moved.add((d, to));
    }
    return moved;
  }

  /// Whether a vault has been set up.
  bool get exists => _dirs().isNotEmpty;

  File _saltFile(Directory d) => File('${d.path}${Platform.pathSeparator}salt');

  File _saltNextFile(Directory d) =>
      File('${d.path}${Platform.pathSeparator}salt.next');

  File _secretFile(Directory d) =>
      File('${d.path}${Platform.pathSeparator}${VaultSecretFile.name}');

  File _secretNextFile(Directory d) => File(
    '${d.path}${Platform.pathSeparator}${VaultSecretFile.name}'
    '${VaultSecretFile.nextSuffix}',
  );

  static String _folderName(Directory d) =>
      d.path.split(Platform.pathSeparator).last;

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
    try {
      await _recover();
    } on VaultCryptoException catch (e) {
      return VaultOpenResult(outcomeOf(e));
    } on Object {
      return const VaultOpenResult(VaultOutcome.unavailable);
    }
    if (exists) return const VaultOpenResult(VaultOutcome.damaged);
    final decoy = decoyPin ?? randomPin();
    if (pin.length < minPinLength || decoy.length < minPinLength) {
      return const VaultOpenResult(VaultOutcome.pinTooShort);
    }
    if (pin == decoy) {
      return const VaultOpenResult(VaultOutcome.pinNotAllowed);
    }
    // The plain key must be there (a device without a screen lock says so
    // here) before anything is made.
    try {
      await crypto.close(await crypto.openMasterKey(requireBiometry: false));
    } on VaultCryptoException catch (e) {
      return VaultOpenResult(outcomeOf(e));
    }
    final made = <Directory>[];
    final handles = <VaultKeyHandle>[];
    final secrets = <Uint8List>[];
    final containers = <VaultContainer>[];
    var committed = false;
    try {
      // Before any folder: until this is deleted at the end there is no vault.
      await _flag(_setupFile);
      final pins = [pin, decoy];
      final order = [0, 1]..shuffle(Random.secure());
      final salts = [randomBytes(16), randomBytes(16)];
      final tokens = await Future.wait([
        for (var i = 0; i < 2; i++) kdf(pins[i], salts[i], iterations),
      ]);
      VaultContainer? real;
      VaultKeyHandle? realHandle;
      Uint8List? realSecret;
      try {
        for (final i in order) {
          final dir = Directory(
            '${root.path}${Platform.pathSeparator}${_randomName()}',
          );
          made.add(dir);
          await dir.create(recursive: true);
          await _writeSalt(dir, salts[i], iterations);
          final s = randomBytes(VaultSecretFile.length);
          secrets.add(s);
          final pinHandle = await crypto.openMasterKey(
            requireBiometry: false,
            secret: tokens[i],
          );
          try {
            await VaultSecretFile.write(
              target: _secretFile(dir),
              crypto: crypto,
              pinHandle: pinHandle,
              secret: s,
              folder: _folderName(dir),
            );
          } finally {
            await crypto.close(pinHandle);
          }
          final master = await crypto.openMasterKey(
            requireBiometry: false,
            secret: s,
          );
          handles.add(master);
          final c = await VaultContainer.create(
            directory: dir,
            crypto: crypto,
            master: master,
          );
          containers.add(c);
          if (i == 0) {
            real = c;
            realHandle = master;
            realSecret = s;
          } else {
            c.close();
          }
        }
      } finally {
        tokens.forEach(wipe);
      }
      // The commit: both folders are whole, and now they are the vault.
      await _setupFile.delete();
      committed = true;
      // From here on the vault exists and nothing is ever deleted: a failure
      // below only costs a handle or the fingerprint.
      // The other vault's handle and secret are not needed any more.
      for (final h in handles) {
        if (h == realHandle) continue;
        try {
          await crypto.close(h);
        } on Object {
          // Released with the process.
        }
      }
      for (final s in secrets) {
        if (s != realSecret) wipe(s);
      }
      final vault = OpenVault._(real!, this, realHandle!, realSecret!);
      if (fingerprint) {
        try {
          await setFingerprint(vault, enabled: true);
        } on Object {
          // The vault exists; the fingerprint can be turned on later.
        }
      }
      return VaultOpenResult(VaultOutcome.opened, vault: vault);
    } on Object catch (e) {
      if (committed) {
        // Not reachable by design; if it ever is, the vault stays.
        return const VaultOpenResult(VaultOutcome.unavailable);
      }
      for (final c in containers) {
        c.close();
      }
      for (final d in made) {
        if (d.existsSync()) d.deleteSync(recursive: true);
      }
      if (_setupFile.existsSync()) _setupFile.deleteSync();
      for (final h in handles) {
        try {
          await crypto.close(h);
        } on Object {
          // Nothing to release.
        }
      }
      secrets.forEach(wipe);
      if (e is VaultCryptoException) return VaultOpenResult(outcomeOf(e));
      return const VaultOpenResult(VaultOutcome.unavailable);
    }
  }

  // ---- PIN -------------------------------------------------------------

  // ---- wrong PINs ------------------------------------------------------

  Future<_Misses> _loadMisses() async {
    final clock = _clock().millisecondsSinceEpoch;
    final raw = await secure.read(_attemptsKey);
    final parts = raw?.split(':');
    if (parts == null || parts.length != 4 || parts[0] != 'v2') {
      return _Misses(0, clock, 0);
    }
    var count = double.tryParse(parts[1]) ?? 0;
    final stored = int.tryParse(parts[2]) ?? clock;
    var until = int.tryParse(parts[3]) ?? 0;
    // The stored time never goes backwards: a clock set back changes nothing
    // (no forgiveness, no longer wait). A clock set forward is not guarded
    // against; it counts as time passed.
    final now = max(clock, stored);
    final hours = (now - stored) / Duration.millisecondsPerHour;
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
  Future<Duration?> _countAttempt() => _oneAtATime(_countAttemptNow);

  Future<Duration?> _countAttemptNow() async {
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
  Future<void> _refundAttempt() => _oneAtATime(() async {
    final m = await _loadMisses();
    final count = max<double>(0, m.count - 1);
    await _saveMisses(_Misses(count, m.stamp, 0));
  });

  Future<void> _attemptsTail = Future<void>.value();

  /// Runs [op] after the earlier ones: two tries at once must not both read
  /// the same count.
  Future<T> _oneAtATime<T>(Future<T> Function() op) {
    final result = _attemptsTail.then((_) => op());
    _attemptsTail = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// The wait now running, if any.
  Future<Duration?> get waitLeft => _waitLeft();

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

  /// What a folder gave for a PIN: its secret S (the caller zeroes it) and
  /// which pair of files opened it, or nothing; `lost` when some handle said
  /// the key was lost (which, with a secret, can mean a wrong PIN).
  Future<_Unsealed> _unseal(
    Directory d,
    Future<Uint8List>? current,
    Future<Uint8List>? pending,
  ) async {
    final tokens = <Uint8List?>[
      if (current == null) null else await current,
      if (pending == null) null else await pending,
    ];
    var lost = false;
    try {
      for (var s = 0; s < 2; s++) {
        final token = tokens[s];
        if (token == null) continue;
        VaultKeyHandle? pinHandle;
        try {
          pinHandle = await crypto.openMasterKey(
            requireBiometry: false,
            secret: token,
          );
          for (final nextFile in [false, true]) {
            final file = nextFile ? _secretNextFile(d) : _secretFile(d);
            if (!file.existsSync()) continue;
            try {
              final secret = await VaultSecretFile.read(
                file: file,
                crypto: crypto,
                pinHandle: pinHandle,
                folder: _folderName(d),
              );
              return _Unsealed(
                secret: secret,
                saltNext: s == 1,
                secretNext: nextFile,
              );
            } on VaultCorrupt {
              // Not this pair.
            } on VaultCryptoException catch (e) {
              // A wrong token and a lost key look the same here; the caller
              // finds out which by asking for the plain key.
              if (!_isNotThisPin(e)) rethrow;
              lost = true;
            }
          }
        } on VaultCryptoException catch (e) {
          if (!_isNotThisPin(e)) rethrow;
          lost = true;
        } finally {
          if (pinHandle != null) {
            try {
              await crypto.close(pinHandle);
            } on Object {
              // Released with the process.
            }
          }
        }
      }
      return _Unsealed(lost: lost);
    } finally {
      tokens.forEach(wipe);
    }
  }

  static bool _isNotThisPin(VaultCryptoException e) =>
      e.error == VaultCryptoError.keyLost ||
      e.error == VaultCryptoError.keyInvalidated ||
      e.error == VaultCryptoError.integrityFailure;

  /// Makes the pair that opened the folder's own and drops what is left of
  /// the other.
  Future<void> _settle(
    Directory d, {
    required bool saltNext,
    required bool secretNext,
  }) async {
    try {
      if (secretNext) await _secretNextFile(d).rename(_secretFile(d).path);
      if (saltNext) await _saltNextFile(d).rename(_saltFile(d).path);
      if (_saltNextFile(d).existsSync()) _saltNextFile(d).deleteSync();
      if (_secretNextFile(d).existsSync()) _secretNextFile(d).deleteSync();
    } on FileSystemException {
      // The pair that opened still opens next time.
    }
  }

  /// After an open that did not say which pair of files the PIN fits (the
  /// fingerprint, which gives the secret itself): a Change PIN that was cut
  /// short is finished only when it had got as far as swapping the secret
  /// file (the new salt without a new secret file: that salt is then the one
  /// that opens the folder's secret file). In every other state the change
  /// is dropped and the old PIN keeps working.
  Future<void> _finishChange(Directory d) async {
    try {
      final saltNext = _saltNextFile(d);
      final secretNext = _secretNextFile(d);
      if (saltNext.existsSync() && !secretNext.existsSync()) {
        await saltNext.rename(_saltFile(d).path);
      } else {
        if (saltNext.existsSync()) saltNext.deleteSync();
        if (secretNext.existsSync()) secretNext.deleteSync();
      }
    } on FileSystemException {
      // The next open tries again.
    }
  }

  /// Opens the vault [pin] belongs to. Both vaults are tried every time, so
  /// a right PIN of either costs the same as a wrong one, and the attempt is
  /// counted before the work starts. A PIN that fits no vault is a wrong PIN
  /// even when the handles say "key lost" (that is what a wrong token looks
  /// like); the vault is reported lost only when the phone's own keys are
  /// gone, which is asked of the keystore directly.
  Future<VaultOpenResult> openWithPin(String pin) async {
    final dirs = _dirs();
    if (dirs.isEmpty) return const VaultOpenResult(VaultOutcome.needsSetup);
    final wait = await _countAttempt();
    if (wait != null) {
      return VaultOpenResult(VaultOutcome.waitToRetry, wait: wait);
    }
    unawaited(_deleteTrash());
    dirs.forEach(VaultContainer.sweepStaleParts);
    OpenVault? found;
    var lost = false;
    final tokens = <Future<Uint8List>>[];
    try {
      final cur = <Future<Uint8List>?>[];
      final nxt = <Future<Uint8List>?>[];
      for (final d in dirs) {
        final a = await _readSalt(d);
        final b = await _readSalt(d, next: true);
        final ta = a == null ? null : kdf(pin, a.salt, a.rounds);
        final tb = b == null ? null : kdf(pin, b.salt, b.rounds);
        cur.add(ta);
        nxt.add(tb);
        tokens
          ..addAll([?ta])
          ..addAll([?tb]);
      }
      for (var i = 0; i < dirs.length; i++) {
        final u = await _unseal(dirs[i], cur[i], nxt[i]);
        if (u.lost) lost = true;
        final secret = u.secret;
        if (secret == null) continue;
        if (found != null) {
          wipe(secret);
          continue;
        }
        final r = await _openWith(dirs[i], secret, u);
        if (r.keyLost) lost = true;
        found = r.vault;
      }
    } on VaultCryptoException catch (e) {
      await found?.close();
      found = null;
      if (e.error == VaultCryptoError.keyLost ||
          e.error == VaultCryptoError.keyInvalidated) {
        // Asked of the keystore below.
        lost = true;
      } else {
        return VaultOpenResult(outcomeOf(e));
      }
    } on Object {
      await found?.close();
      return const VaultOpenResult(VaultOutcome.damaged);
    } finally {
      _zeroLater(tokens);
    }
    if (found != null) {
      await _refundAttempt();
      return VaultOpenResult(VaultOutcome.opened, vault: found);
    }
    if (lost) {
      final gone = await _probeDeviceKeys();
      if (gone != null) return VaultOpenResult(gone);
    }
    final left = await _waitLeft();
    return left == null
        ? const VaultOpenResult(VaultOutcome.wrongPin)
        : VaultOpenResult(VaultOutcome.waitToRetry, wait: left);
  }

  /// Zeroes tokens that were derived but never used because something failed
  /// first.
  static void _zeroLater(Iterable<Future<Uint8List>> tokens) {
    for (final t in tokens) {
      unawaited(t.then(wipe, onError: (Object _) {}));
    }
  }

  /// Whether the phone's own keys are there: opens the plain key and the
  /// device-bound one (with a throwaway secret). Null when both open;
  /// otherwise the answer to give, [VaultOutcome.keyLost] when a key is gone.
  Future<VaultOutcome?> _probeDeviceKeys() async {
    final dummy = randomBytes(VaultSecretFile.length);
    try {
      await crypto.close(await crypto.openMasterKey(requireBiometry: false));
      await crypto.close(
        await crypto.openMasterKey(requireBiometry: false, secret: dummy),
      );
      return null;
    } on VaultCryptoException catch (e) {
      final o = outcomeOf(e);
      return o == VaultOutcome.fingerprintInvalidated
          ? VaultOutcome.keyLost
          : o;
    } finally {
      wipe(dummy);
    }
  }

  /// Opens the container of [d] with its secret; the vault takes over the
  /// secret. No vault when the container cannot be read (damaged, or the
  /// secret does not fit it), in which case the secret is zeroed and the
  /// handle closed; `keyLost` says the handles reported the key as lost.
  Future<({OpenVault? vault, bool keyLost})> _openWith(
    Directory d,
    Uint8List secret,
    _Unsealed u, {
    bool viaPin = true,
  }) async {
    VaultKeyHandle? master;
    VaultContainer? c;
    try {
      master = await crypto.openMasterKey(
        requireBiometry: false,
        secret: secret,
      );
      c = await VaultContainer.open(
        directory: d,
        crypto: crypto,
        master: master,
      );
      if (viaPin) {
        await _settle(d, saltNext: u.saltNext, secretNext: u.secretNext);
      } else {
        await _finishChange(d);
      }
      return (vault: OpenVault._(c, this, master, secret), keyLost: false);
    } on Object catch (e) {
      c?.close();
      wipe(secret);
      if (master != null) {
        try {
          await crypto.close(master);
        } on Object {
          // Released with the process.
        }
      }
      if (e is VaultCorrupt) return (vault: null, keyLost: false);
      if (e is VaultCryptoException) {
        if (e.error == VaultCryptoError.keyLost ||
            e.error == VaultCryptoError.keyInvalidated) {
          return (vault: null, keyLost: true);
        }
        if (e.error == VaultCryptoError.integrityFailure) {
          return (vault: null, keyLost: false);
        }
      }
      rethrow;
    }
  }

  // ---- fingerprint -----------------------------------------------------

  /// Whether the fingerprint opens a vault.
  Future<bool> get fingerprintOn async => await secure.read(_bioKey) != null;

  /// Opens the vault the fingerprint was turned on in. The fingerprint gives
  /// the container's secret straight, so it does not touch the wrong-PIN
  /// count. A fingerprint key that is gone or invalidated means only that the
  /// fingerprint no longer works (the entry is removed, the PIN still opens
  /// the vault); the vault is called lost only when the phone's own keys are.
  Future<VaultOpenResult> openWithFingerprint() async {
    final raw = await secure.read(_bioKey);
    if (raw == null) return const VaultOpenResult(VaultOutcome.noFingerprint);
    final dirs = _dirs();
    if (dirs.isEmpty) return const VaultOpenResult(VaultOutcome.needsSetup);
    VaultKeyHandle? bio;
    Uint8List? secret;
    try {
      final j = jsonDecode(raw) as Map<String, Object?>;
      final dir = dirs.firstWhere((d) => _folderName(d) == j['d']);
      bio = await crypto.openMasterKey(requireBiometry: true);
      final wrapped = await crypto.adoptFileKey(
        bio,
        base64Decode(j['k']! as String),
      );
      secret = ownedCopy(
        await crypto.open(
          wrapped,
          base64Decode(j['n']! as String),
          Uint8List.fromList(_bioAad),
          base64Decode(j['s']! as String),
        ),
      );
      await crypto.close(bio);
      bio = null;
      final r = await _openWith(dir, secret, const _Unsealed(), viaPin: false);
      secret = null;
      final vault = r.vault;
      if (vault != null) {
        return VaultOpenResult(VaultOutcome.opened, vault: vault);
      }
      if (r.keyLost) {
        final gone = await _probeDeviceKeys();
        if (gone != null) return VaultOpenResult(gone);
      }
      // The entry does not fit the folder any more, or the folder is damaged.
      await secure.delete(_bioKey);
      return VaultOpenResult(
        r.keyLost ? VaultOutcome.fingerprintInvalidated : VaultOutcome.damaged,
      );
    } on VaultCryptoException catch (e) {
      if (e.error == VaultCryptoError.keyLost ||
          e.error == VaultCryptoError.keyInvalidated) {
        // The fingerprint key cannot open anything again; the PIN can.
        await secure.delete(_bioKey);
        return const VaultOpenResult(VaultOutcome.fingerprintInvalidated);
      }
      final outcome = outcomeOf(e);
      if (outcome == VaultOutcome.damaged) await secure.delete(_bioKey);
      return VaultOpenResult(outcome);
    } on Object {
      await secure.delete(_bioKey);
      return const VaultOpenResult(VaultOutcome.damaged);
    } finally {
      wipe(secret);
      if (bio != null) {
        try {
          await crypto.close(bio);
        } on Object {
          // Released with the process.
        }
      }
    }
  }

  /// Turns fingerprint unlock on for [vault] (asking for the fingerprint now)
  /// or off. Only one vault has it: turning it on in the other moves it. The
  /// entry holds the container's secret sealed under the fingerprint key, so
  /// it keeps working when the PIN is changed.
  Future<VaultOutcome> setFingerprint(
    OpenVault vault, {
    required bool enabled,
  }) async {
    if (!enabled) {
      await secure.delete(_bioKey);
      return VaultOutcome.opened;
    }
    // A copy: the prompt can take long, and the vault locking meanwhile
    // zeroes the original.
    final Uint8List secret;
    try {
      secret = vault.secretCopy();
    } on VaultLocked {
      return VaultOutcome.unavailable;
    }
    VaultKeyHandle? bio;
    try {
      bio = await crypto.openMasterKey(requireBiometry: true);
      final wrapped = await crypto.newFileKey(bio);
      final nonce = randomBytes(VaultCryptoFacade.nonceLength);
      final sealed = await crypto.seal(
        wrapped,
        nonce,
        Uint8List.fromList(_bioAad),
        secret,
      );
      await secure.write(
        _bioKey,
        jsonEncode({
          'd': _folderName(vault.container.directory),
          'k': base64Encode(wrapped.bytes),
          'n': base64Encode(nonce),
          's': base64Encode(sealed),
        }),
      );
      return VaultOutcome.opened;
    } on VaultCryptoException catch (e) {
      return outcomeOf(e);
    } finally {
      wipe(secret);
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

  /// Gives the open vault a new PIN, safely: the container's secret is
  /// sealed again under the new PIN's token, read back and compared, written
  /// beside the old file with the new salt, then both are swapped in. Opening
  /// takes whichever pair the PIN fits, so a stop at any moment leaves a
  /// vault that opens. No file is touched and the fingerprint keeps working.
  /// The new PIN is first tried on the other vaults (counted like any
  /// attempt): one of theirs is refused, because the two would collide.
  /// Returns [VaultOutcome.opened] when it worked (also when only the last
  /// rename failed: the next open finishes it), [VaultOutcome.pinNotAllowed]
  /// for a PIN another vault uses and [VaultOutcome.pinTooShort] for one
  /// under [minPinLength] digits. Throws [VaultLocked] for a locked vault.
  Future<VaultOutcome> changePin(OpenVault vault, String newPin) async {
    if (newPin.length < minPinLength) return VaultOutcome.pinTooShort;
    // A copy of S taken now: the KDF below takes seconds, and the vault
    // locking meanwhile zeroes the original.
    final secret = vault.secretCopy();
    try {
      return await _changePin(vault, newPin, secret);
    } finally {
      wipe(secret);
    }
  }

  static bool _sameBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<VaultOutcome> _changePin(
    OpenVault vault,
    String newPin,
    Uint8List secret,
  ) async {
    final here = vault.container.directory;
    final wait = await _countAttempt();
    if (wait != null) return VaultOutcome.waitToRetry;
    // Does the new PIN already open another vault?
    for (final d in _dirs()) {
      if (d.path == here.path) continue;
      final tokens = <Future<Uint8List>>[];
      try {
        final a = await _readSalt(d);
        final b = await _readSalt(d, next: true);
        final ta = a == null ? null : kdf(newPin, a.salt, a.rounds);
        final tb = b == null ? null : kdf(newPin, b.salt, b.rounds);
        tokens
          ..addAll([?ta])
          ..addAll([?tb]);
        final other = await _unseal(d, ta, tb);
        final s = other.secret;
        if (s != null) {
          wipe(s);
          return VaultOutcome.pinNotAllowed;
        }
      } on VaultCorrupt {
        // A damaged other vault cannot be opened by this PIN either.
        continue;
      } on FileSystemException {
        continue;
      } on FormatException {
        continue;
      } on VaultCryptoException catch (e) {
        return outcomeOf(e);
      } finally {
        _zeroLater(tokens);
      }
    }
    final salt = randomBytes(16);
    final token = await kdf(newPin, salt, iterations);
    var swapped = false;
    try {
      final pinHandle = await crypto.openMasterKey(
        requireBiometry: false,
        secret: token,
      );
      try {
        await VaultSecretFile.write(
          target: _secretNextFile(here),
          crypto: crypto,
          pinHandle: pinHandle,
          secret: secret,
          folder: _folderName(here),
        );
        // Before anything is swapped: the new file must give S back. A secret
        // that does not come back would lock the vault for good.
        final back = await VaultSecretFile.read(
          file: _secretNextFile(here),
          crypto: crypto,
          pinHandle: pinHandle,
          folder: _folderName(here),
        );
        final same = _sameBytes(back, secret);
        wipe(back);
        if (!same) throw const VaultCorrupt('the new secret file differs');
      } finally {
        await crypto.close(pinHandle);
      }
      await _writeSalt(here, salt, iterations, next: true);
      // The salt on disk must be the one the token was made from.
      final written = await _readSalt(here, next: true);
      if (written == null ||
          written.rounds != iterations ||
          written.salt.length != salt.length ||
          !_sameBytes(written.salt, salt)) {
        throw const VaultCorrupt('the new salt file differs');
      }
      await _secretNextFile(here).rename(_secretFile(here).path);
      swapped = true;
      try {
        await _saltNextFile(here).rename(_saltFile(here).path);
      } on FileSystemException {
        // The new salt is what opens the new secret file; it stays, and the
        // next open finishes the rename.
      }
    } on Object {
      // Before the swap the old pair is still whole and the new files are
      // dropped.
      if (!swapped) {
        for (final f in [_secretNextFile(here), _saltNextFile(here)]) {
          if (f.existsSync()) f.deleteSync();
        }
      }
      rethrow;
    } finally {
      wipe(token);
    }
    return VaultOutcome.opened;
  }

  /// Deletes both vaults and everything in them, the fingerprint entry and
  /// the OS key behind them (`VaultCryptoFacade.reset`, ADR-039 amendment 1).
  /// Used when the vault can no longer be opened, after the user confirmed.
  /// A journal file is written first; the folders are renamed out of the way
  /// (and put back, journal removed, if anything fails), then the key goes;
  /// only when that worked is anything deleted. A stop in the middle is
  /// finished at the next start. Throws [VaultResetPending] when a failure
  /// could not be undone (the reset then finishes at the next start).
  Future<void> reset() async {
    await _flag(_resetFile);
    final moved = <(Directory, Directory)>[];
    try {
      await _moveAway(into: moved);
      await crypto.reset();
    } on Object {
      var undone = true;
      for (final (from, to) in moved) {
        try {
          if (!to.existsSync()) {
            undone = false;
          } else {
            await to.rename(from.path);
          }
        } on Object {
          undone = false;
        }
      }
      if (undone) {
        try {
          await _resetFile.delete();
        } on Object {
          undone = false;
        }
      }
      if (!undone) throw const VaultResetPending();
      rethrow;
    }
    await _deleteTrash();
    await secure.delete(_bioKey);
    await secure.delete(_attemptsKey);
    await _resetFile.delete();
  }
}

/// A reset could not be finished or undone right now; it finishes the next
/// time the app starts.
final class VaultResetPending implements Exception {
  const VaultResetPending();

  @override
  String toString() => 'VaultResetPending';
}

/// How many wrong guesses are on record, when that was last worked out, and
/// until when the next try must wait (milliseconds since the epoch).
final class _Misses {
  const _Misses(this.count, this.stamp, this.until);

  final double count;
  final int stamp;
  final int until;
}

/// What unsealing one folder found.
final class _Unsealed {
  const _Unsealed({
    this.secret,
    this.saltNext = false,
    this.secretNext = false,
    this.lost = false,
  });

  /// The container's secret, or null when the PIN did not unseal it.
  final Uint8List? secret;

  /// Whether the pair that opened it was the one a Change PIN left beside the
  /// old.
  final bool saltNext;
  final bool secretNext;

  /// A handle said the key was lost (a wrong token looks like that).
  final bool lost;
}
