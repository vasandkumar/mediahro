import 'dart:ffi';

import 'package:ffi/ffi.dart';
// The mpv bindings are an engine-private part of mediahro_ffi (lane B1).
// ignore: implementation_imports
import 'package:mediahro_ffi/src/mpv/mpv.dart';

/// `mpv_format` values (client.h). Used as plain ints because ffigen's enum
/// wrappers throw on values added by newer libmpv releases.
abstract final class MpvFormat {
  static const none = 0;
  static const string = 1;
  static const osdString = 2;
  static const flag = 3;
  static const int64 = 4;
  static const double_ = 5;
  static const node = 6;
  static const nodeArray = 7;
  static const nodeMap = 8;
  static const byteArray = 9;
}

/// `mpv_event_id` values (client.h).
abstract final class MpvEventId {
  static const none = 0;
  static const shutdown = 1;
  static const logMessage = 2;
  static const getPropertyReply = 3;
  static const setPropertyReply = 4;
  static const commandReply = 5;
  static const startFile = 6;
  static const endFile = 7;
  static const fileLoaded = 8;
  static const clientMessage = 16;
  static const videoReconfig = 17;
  static const audioReconfig = 18;
  static const seek = 20;
  static const playbackRestart = 21;
  static const propertyChange = 22;
  static const queueOverflow = 24;
  static const hook = 25;
}

/// `mpv_end_file_reason` values.
abstract final class MpvEndReason {
  static const eof = 0;
  static const stop = 2;
  static const quit = 3;
  static const error = 4;
  static const redirect = 5;
}

/// `mpv_error` values used for error mapping (CORE-011).
abstract final class MpvError {
  static const success = 0;
  static const eventQueueFull = -1;
  static const nomem = -2;
  static const uninitialized = -3;
  static const invalidParameter = -4;
  static const optionNotFound = -5;
  static const optionFormat = -6;
  static const optionError = -7;
  static const propertyNotFound = -8;
  static const propertyFormat = -9;
  static const propertyUnavailable = -10;
  static const propertyError = -11;
  static const command = -12;
  static const loadingFailed = -13;
  static const aoInitFailed = -14;
  static const voInitFailed = -15;
  static const nothingToPlay = -16;
  static const unknownFormat = -17;
  static const unsupported = -18;
  static const notImplemented = -19;
  static const generic = -20;
}

/// Converts an `mpv_node` (or a property value of [format] at [data]) into
/// plain Dart values: `String`, `bool`, `int`, `double`, `List<Object?>`,
/// `Map<String, Object?>`, `List<int>` (byte arrays) or `null`.
///
/// Only sendable values are produced, so results cross isolate ports as-is.
Object? readMpvValue(int format, Pointer<Void> data) {
  if (data == nullptr) return null;
  return switch (format) {
    MpvFormat.string ||
    MpvFormat.osdString => data.cast<Pointer<Utf8>>().value.toDartString(),
    MpvFormat.flag => data.cast<Int>().value != 0,
    MpvFormat.int64 => data.cast<Int64>().value,
    MpvFormat.double_ => data.cast<Double>().value,
    MpvFormat.node => readMpvNode(data.cast<mpv_node>().ref),
    _ => null,
  };
}

Object? readMpvNode(mpv_node node) {
  switch (node.formatAsInt) {
    case MpvFormat.none:
      return null;
    case MpvFormat.string:
    case MpvFormat.osdString:
      return node.u.string.cast<Utf8>().toDartString();
    case MpvFormat.flag:
      return node.u.flag != 0;
    case MpvFormat.int64:
      return node.u.int64;
    case MpvFormat.double_:
      return node.u.double_;
    case MpvFormat.nodeArray:
      final list = node.u.list.ref;
      return [for (var i = 0; i < list.num; i++) readMpvNode(list.values[i])];
    case MpvFormat.nodeMap:
      final list = node.u.list.ref;
      return <String, Object?>{
        for (var i = 0; i < list.num; i++)
          list.keys[i].cast<Utf8>().toDartString(): readMpvNode(list.values[i]),
      };
    case MpvFormat.byteArray:
      final ba = node.u.ba.ref;
      return ba.data.cast<Uint8>().asTypedList(ba.size).toList();
    default:
      return null;
  }
}
