import 'dart:typed_data';

/// Zeroes [bytes] (a key, a secret, a PIN token) when it is no longer needed.
/// Bytes that came over a platform channel can be a read-only view, which
/// cannot be written to: those are left (they are copied before use, see
/// [ownedCopy], so nothing the vault holds on to is one).
void wipe(Uint8List? bytes) {
  if (bytes == null) return;
  try {
    bytes.fillRange(0, bytes.length, 0);
    // The only way to know a view is read-only is to write to it.
    // ignore: avoid_catching_errors
  } on UnsupportedError {
    // A read-only view: nothing to zero here.
  }
}

/// A writable copy of [bytes] that the caller owns and will [wipe]. Anything
/// a platform returns that is kept for a while (the container secret) goes
/// through this first: the buffer the codec hands back may be read-only.
Uint8List ownedCopy(Uint8List bytes) => Uint8List.fromList(bytes);
