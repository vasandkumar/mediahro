// VM-only: 64-bit constants and wrapping arithmetic (never compiled to JS).
// ignore_for_file: avoid_js_rounded_ints
import 'dart:typed_data';

/// XXH3-64 (seed 0, default secret), bit-exact with xxHash 0.8 `XXH3_64bits`.
///
/// Pure Dart so the scanner isolates need no native library. Relies on the
/// VM's wrapping 64-bit integer arithmetic (not for the web).
int xxh3(Uint8List input) {
  final len = input.length;
  final d = ByteData.sublistView(input);
  if (len <= 16) return _len0to16(input, d, len);
  if (len <= 128) return _len17to128(d, len);
  if (len <= 240) return _len129to240(d, len);
  return _hashLong(d, len);
}

/// Lower-case, zero-padded hex of [xxh3].
String xxh3Hex(Uint8List input) =>
    xxh3(input).toUnsigned(64).toRadixString(16).padLeft(16, '0');

const int _p32_1 = 0x9E3779B1;
const int _p32_2 = 0x85EBCA77;
const int _p32_3 = 0xC2B2AE3D;
const int _p64_1 = 0x9E3779B185EBCA87;
const int _p64_2 = 0xC2B2AE3D27D4EB4F;
const int _p64_3 = 0x165667B19E3779F9;
const int _p64_4 = 0x85EBCA77C2B2AE63;
const int _p64_5 = 0x27D4EB2F165667C5;
const int _mx1 = 0x165667919E3779F9;
const int _mx2 = 0x9FB21C651E98DF25;
const int _m32 = 0xFFFFFFFF;

const int _stripeLen = 64;
const int _secretSize = 192;
const int _accNb = 8;

final ByteData _secret = ByteData.sublistView(
  Uint8List.fromList(const [
    0xb8, 0xfe, 0x6c, 0x39, 0x23, 0xa4, 0x4b, 0xbe, 0x7c, 0x01, 0x81, 0x2c, //
    0xf7, 0x21, 0xad, 0x1c, 0xde, 0xd4, 0x6d, 0xe9, 0x83, 0x90, 0x97, 0xdb,
    0x72, 0x40, 0xa4, 0xa4, 0xb7, 0xb3, 0x67, 0x1f, 0xcb, 0x79, 0xe6, 0x4e,
    0xcc, 0xc0, 0xe5, 0x78, 0x82, 0x5a, 0xd0, 0x7d, 0xcc, 0xff, 0x72, 0x21,
    0xb8, 0x08, 0x46, 0x74, 0xf7, 0x43, 0x24, 0x8e, 0xe0, 0x35, 0x90, 0xe6,
    0x81, 0x3a, 0x26, 0x4c, 0x3c, 0x28, 0x52, 0xbb, 0x91, 0xc3, 0x00, 0xcb,
    0x88, 0xd0, 0x65, 0x8b, 0x1b, 0x53, 0x2e, 0xa3, 0x71, 0x64, 0x48, 0x97,
    0xa2, 0x0d, 0xf9, 0x4e, 0x38, 0x19, 0xef, 0x46, 0xa9, 0xde, 0xac, 0xd8,
    0xa8, 0xfa, 0x76, 0x3f, 0xe3, 0x9c, 0x34, 0x3f, 0xf9, 0xdc, 0xbb, 0xc7,
    0xc7, 0x0b, 0x4f, 0x1d, 0x8a, 0x51, 0xe0, 0x4b, 0xcd, 0xb4, 0x59, 0x31,
    0xc8, 0x9f, 0x7e, 0xc9, 0xd9, 0x78, 0x73, 0x64, 0xea, 0xc5, 0xac, 0x83,
    0x34, 0xd3, 0xeb, 0xc3, 0xc5, 0x81, 0xa0, 0xff, 0xfa, 0x13, 0x63, 0xeb,
    0x17, 0x0d, 0xdd, 0x51, 0xb7, 0xf0, 0xda, 0x49, 0xd3, 0x16, 0x55, 0x26,
    0x29, 0xd4, 0x68, 0x9e, 0x2b, 0x16, 0xbe, 0x58, 0x7d, 0x47, 0xa1, 0xfc,
    0x8f, 0xf8, 0xb8, 0xd1, 0x7a, 0xd0, 0x31, 0xce, 0x45, 0xcb, 0x3a, 0x8f,
    0x95, 0x16, 0x04, 0x28, 0xaf, 0xd7, 0xfb, 0xca, 0xbb, 0x4b, 0x40, 0x7e,
  ]),
);

int _r64(ByteData d, int o) => d.getUint64(o, Endian.little);
int _r32(ByteData d, int o) => d.getUint32(o, Endian.little);
int _s64(int o) => _secret.getUint64(o, Endian.little);
int _s32(int o) => _secret.getUint32(o, Endian.little);

int _rotl64(int x, int r) => (x << r) | (x >>> (64 - r));

int _swap32(int x) =>
    ((x << 24) & 0xFF000000) |
    ((x << 8) & 0x00FF0000) |
    ((x >>> 8) & 0x0000FF00) |
    ((x >>> 24) & 0x000000FF);

int _swap64(int x) => (_swap32(x & _m32) << 32) | _swap32(x >>> 32);

int _mul128Fold64(int a, int b) {
  final aLo = a & _m32;
  final aHi = a >>> 32;
  final bLo = b & _m32;
  final bHi = b >>> 32;
  final loLo = aLo * bLo;
  final hiLo = aHi * bLo;
  final loHi = aLo * bHi;
  final hiHi = aHi * bHi;
  final cross = (loLo >>> 32) + (hiLo & _m32) + loHi;
  final upper = (hiLo >>> 32) + (cross >>> 32) + hiHi;
  final lower = (cross << 32) | (loLo & _m32);
  return lower ^ upper;
}

int _xxh64Avalanche(int h) {
  var x = h;
  x ^= x >>> 33;
  x *= _p64_2;
  x ^= x >>> 29;
  x *= _p64_3;
  return x ^ (x >>> 32);
}

int _avalanche(int h) {
  var x = h;
  x ^= x >>> 37;
  x *= _mx1;
  return x ^ (x >>> 32);
}

int _rrmxmx(int h, int len) {
  var x = h;
  x ^= _rotl64(x, 49) ^ _rotl64(x, 24);
  x *= _mx2;
  x ^= (x >>> 35) + len;
  x *= _mx2;
  return x ^ (x >>> 28);
}

int _len0to16(Uint8List input, ByteData d, int len) {
  if (len > 8) {
    final bitflip1 = _s64(24) ^ _s64(32);
    final bitflip2 = _s64(40) ^ _s64(48);
    final lo = _r64(d, 0) ^ bitflip1;
    final hi = _r64(d, len - 8) ^ bitflip2;
    final acc = len + _swap64(lo) + hi + _mul128Fold64(lo, hi);
    return _avalanche(acc);
  }
  if (len >= 4) {
    final input1 = _r32(d, 0);
    final input2 = _r32(d, len - 4);
    final bitflip = _s64(8) ^ _s64(16);
    final input64 = input2 + (input1 << 32);
    return _rrmxmx(input64 ^ bitflip, len);
  }
  if (len > 0) {
    final c1 = input[0];
    final c2 = input[len >> 1];
    final c3 = input[len - 1];
    final combined = (c1 << 16) | (c2 << 24) | c3 | (len << 8);
    final bitflip = (_s32(0) ^ _s32(4)) & _m32;
    return _xxh64Avalanche((combined & _m32) ^ bitflip);
  }
  return _xxh64Avalanche(_s64(56) ^ _s64(64));
}

int _mix16(ByteData d, int o, int s) =>
    _mul128Fold64(_r64(d, o) ^ _s64(s), _r64(d, o + 8) ^ _s64(s + 8));

int _len17to128(ByteData d, int len) {
  var acc = len * _p64_1;
  if (len > 32) {
    if (len > 64) {
      if (len > 96) {
        acc += _mix16(d, 48, 96);
        acc += _mix16(d, len - 64, 112);
      }
      acc += _mix16(d, 32, 64);
      acc += _mix16(d, len - 48, 80);
    }
    acc += _mix16(d, 16, 32);
    acc += _mix16(d, len - 32, 48);
  }
  acc += _mix16(d, 0, 0);
  acc += _mix16(d, len - 16, 16);
  return _avalanche(acc);
}

int _len129to240(ByteData d, int len) {
  var acc = len * _p64_1;
  final rounds = len ~/ 16;
  for (var i = 0; i < 8; i++) {
    acc += _mix16(d, 16 * i, 16 * i);
  }
  acc = _avalanche(acc);
  for (var i = 8; i < rounds; i++) {
    acc += _mix16(d, 16 * i, 16 * (i - 8) + 3);
  }
  // XXH3_SECRET_SIZE_MIN (136) - XXH3_MIDSIZE_LASTOFFSET (17).
  acc += _mix16(d, len - 16, 136 - 17);
  return _avalanche(acc);
}

void _accumulate512(Int64List acc, ByteData d, int o, int s) {
  for (var i = 0; i < _accNb; i++) {
    final dataVal = _r64(d, o + 8 * i);
    final dataKey = dataVal ^ _s64(s + 8 * i);
    acc[i ^ 1] += dataVal;
    acc[i] += (dataKey & _m32) * (dataKey >>> 32);
  }
}

void _scramble(Int64List acc, int s) {
  for (var i = 0; i < _accNb; i++) {
    var a = acc[i];
    a ^= a >>> 47;
    a ^= _s64(s + 8 * i);
    a *= _p32_1;
    acc[i] = a;
  }
}

int _hashLong(ByteData d, int len) {
  final acc = Int64List.fromList(const [
    _p32_3,
    _p64_1,
    _p64_2,
    _p64_3,
    _p64_4,
    _p32_2,
    _p64_5,
    _p32_1,
  ]);
  const stripesPerBlock = (_secretSize - _stripeLen) ~/ 8;
  const blockLen = _stripeLen * stripesPerBlock;
  final blocks = (len - 1) ~/ blockLen;
  for (var n = 0; n < blocks; n++) {
    for (var s = 0; s < stripesPerBlock; s++) {
      _accumulate512(acc, d, n * blockLen + s * _stripeLen, s * 8);
    }
    _scramble(acc, _secretSize - _stripeLen);
  }
  final stripes = ((len - 1) - blockLen * blocks) ~/ _stripeLen;
  for (var s = 0; s < stripes; s++) {
    _accumulate512(acc, d, blocks * blockLen + s * _stripeLen, s * 8);
  }
  // XXH_SECRET_LASTACC_START = 7.
  _accumulate512(acc, d, len - _stripeLen, _secretSize - _stripeLen - 7);
  // XXH_SECRET_MERGEACCS_START = 11.
  var result = len * _p64_1;
  for (var i = 0; i < 4; i++) {
    result += _mul128Fold64(
      acc[2 * i] ^ _s64(11 + 16 * i),
      acc[2 * i + 1] ^ _s64(11 + 16 * i + 8),
    );
  }
  return _avalanche(result);
}
