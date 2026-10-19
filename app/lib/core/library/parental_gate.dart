import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/rules/rule_sql.dart';
import 'package:mediahro/platform/security.dart';

enum UnlockResult { unlocked, wrongPin, lockedOut, noPin, cancelled }

/// Why a parental-gate change was refused; the UI maps it to copy.
enum ParentalGateRefusal { invalidPin, locked, noPin }

final class ParentalGateException implements Exception {
  const ParentalGateException(this.reason);

  final ParentalGateRefusal reason;

  @override
  String toString() => 'ParentalGateException(${reason.name})';
}

/// Parental PIN / biometric gate for chosen sources and folders, and
/// hidden items (LIB-013). Locked content is excluded from search and rows
/// through [visibility] until the gate is opened for the session.
final class ParentalGate {
  ParentalGate({
    required this.db,
    required this.secureStorage,
    this.biometrics,
    this.relockAfter = const Duration(minutes: 10),
    DateTime Function()? clock,
    Random? random,
  }) : _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  final LibraryDatabase db;
  final SecureStorageFacade secureStorage;
  final BiometricsFacade? biometrics;

  /// The gate closes again after this much time (and on app background).
  final Duration relockAfter;
  final DateTime Function() _clock;
  final Random _random;

  static const _pinKey = 'parental.pin';
  static const _maxAttempts = 5;

  DateTime? _unlockedAt;
  int _failures = 0;
  DateTime? _lockedOutUntil;
  final _changes = StreamController<bool>.broadcast();

  /// Emits whenever the gate opens or closes.
  Stream<bool> get changes => _changes.stream;

  bool get isUnlocked {
    final at = _unlockedAt;
    if (at == null) return false;
    if (_clock().difference(at) > relockAfter) {
      _unlockedAt = null;
      return false;
    }
    return true;
  }

  Visibility get visibility => Visibility(unlocked: isUnlocked);

  Future<bool> get hasPin async => await secureStorage.read(_pinKey) != null;

  /// Sets or replaces the PIN (4–12 digits). Replacing needs an open gate.
  Future<void> setPin(String pin) async {
    if (!RegExp(r'^\d{4,12}$').hasMatch(pin)) {
      throw const ParentalGateException(ParentalGateRefusal.invalidPin);
    }
    if (await hasPin && !isUnlocked) {
      throw const ParentalGateException(ParentalGateRefusal.locked);
    }
    final salt = List<int>.generate(16, (_) => _random.nextInt(256));
    await secureStorage.write(
      _pinKey,
      jsonEncode({
        'salt': base64Encode(salt),
        'hash': base64Encode(await _deriveOffUi(pin, salt, _iterations)),
        'iter': _iterations,
      }),
    );
  }

  /// Removes the PIN and every lock (needs an open gate).
  Future<void> removePin() async {
    if (!isUnlocked) {
      throw const ParentalGateException(ParentalGateRefusal.locked);
    }
    await secureStorage.delete(_pinKey);
    await db.transaction(() async {
      await db
          .update(db.sources)
          .write(const SourcesCompanion(locked: Value(false)));
      await db.delete(db.lockedFolders).go();
    });
  }

  /// Opens the gate with biometrics when available and [preferBiometrics],
  /// else with [pin]. Five wrong PINs lock out for 30 s, doubling each time.
  Future<UnlockResult> unlock({
    String? pin,
    bool preferBiometrics = true,
    String reason = '',
  }) async {
    final raw = await secureStorage.read(_pinKey);
    if (raw == null) return UnlockResult.noPin;
    final until = _lockedOutUntil;
    if (until != null && _clock().isBefore(until)) {
      return UnlockResult.lockedOut;
    }
    final bio = biometrics;
    if (pin == null && preferBiometrics && bio != null) {
      if (await bio.available() == BiometricKind.none) {
        return UnlockResult.cancelled;
      }
      final ok = await bio.authenticate(reason: reason);
      if (!ok) return UnlockResult.cancelled;
      _open();
      return UnlockResult.unlocked;
    }
    if (pin == null) return UnlockResult.cancelled;
    final stored = jsonDecode(raw) as Map<String, Object?>;
    final salt = base64Decode(stored['salt']! as String);
    final expected = base64Decode(stored['hash']! as String);
    final actual = await _deriveOffUi(pin, salt, stored['iter']! as int);
    if (!_constantTimeEquals(expected, actual)) {
      _failures++;
      if (_failures >= _maxAttempts) {
        final rounds = _failures - _maxAttempts;
        _lockedOutUntil = _clock().add(
          Duration(seconds: 30 << rounds.clamp(0, 10)),
        );
        return UnlockResult.lockedOut;
      }
      return UnlockResult.wrongPin;
    }
    _open();
    return UnlockResult.unlocked;
  }

  void lock() {
    if (_unlockedAt == null) return;
    _unlockedAt = null;
    _changes.add(false);
  }

  /// Puts a whole source behind the gate (or releases it; needs an open gate).
  Future<void> setSourceLocked(int sourceId, {required bool locked}) async {
    await _requirePinAndOpenForRelease(locked);
    await (db.update(db.sources)..where((s) => s.id.equals(sourceId))).write(
      SourcesCompanion(locked: Value(locked)),
    );
  }

  Future<void> setFolderLocked(
    int sourceId,
    String relPath, {
    required bool locked,
  }) async {
    await _requirePinAndOpenForRelease(locked);
    if (locked) {
      await db
          .into(db.lockedFolders)
          .insertOnConflictUpdate(
            LockedFoldersCompanion.insert(sourceId: sourceId, relPath: relPath),
          );
    } else {
      await (db.delete(db.lockedFolders)..where(
            (f) => f.sourceId.equals(sourceId) & f.relPath.equals(relPath),
          ))
          .go();
    }
  }

  /// Hidden items never show in search or rows (no PIN needed to hide).
  Future<void> setHidden(Iterable<int> itemIds, {required bool hidden}) async {
    if (!hidden && !isUnlocked && await hasPin) {
      throw const ParentalGateException(ParentalGateRefusal.locked);
    }
    await (db.update(db.items)..where((i) => i.id.isIn(itemIds))).write(
      ItemsCompanion(hidden: Value(hidden)),
    );
  }

  Future<void> dispose() => _changes.close();

  void _open() {
    _failures = 0;
    _lockedOutUntil = null;
    _unlockedAt = _clock();
    _changes.add(true);
  }

  Future<void> _requirePinAndOpenForRelease(bool locking) async {
    if (!await hasPin) {
      throw const ParentalGateException(ParentalGateRefusal.noPin);
    }
    if (!locking && !isUnlocked) {
      throw const ParentalGateException(ParentalGateRefusal.locked);
    }
  }

  static const _iterations = 100000;

  /// PBKDF2 is CPU-heavy: never on the UI isolate (docs/05 §7).
  static Future<List<int>> _deriveOffUi(
    String pin,
    List<int> salt,
    int iterations,
  ) => Isolate.run(() => _derive(pin, salt, iterations));

  /// PBKDF2-HMAC-SHA256, 32 bytes.
  static List<int> _derive(String pin, List<int> salt, int iterations) {
    final hmac = Hmac(sha256, utf8.encode(pin));
    var u = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
    final out = List<int>.of(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < out.length; j++) {
        out[j] ^= u[j];
      }
    }
    return out;
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var d = 0;
    for (var i = 0; i < a.length; i++) {
      d |= a[i] ^ b[i];
    }
    return d == 0;
  }
}
