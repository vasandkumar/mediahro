import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:mediahro_engine/src/mpv/mpv_node.dart';
// The mpv bindings are an engine-private part of mediahro_ffi (lane B1).
// ignore: implementation_imports
import 'package:mediahro_ffi/src/mpv/mpv.dart';
import 'package:meta/meta.dart';

/// Events delivered by [MpvClient.events]. Produced on the event isolate and
/// sent to the owning isolate, so every field is a plain sendable value.
@immutable
sealed class MpvEvent {
  const MpvEvent();
}

final class MpvPropertyChange extends MpvEvent {
  const MpvPropertyChange(this.name, this.value);
  final String name;

  /// `null` when the property is unavailable (e.g. `duration` while idle).
  final Object? value;

  @override
  String toString() => 'MpvPropertyChange($name, $value)';
}

final class MpvStartFile extends MpvEvent {
  const MpvStartFile(this.playlistEntryId);
  final int playlistEntryId;
}

final class MpvEndFile extends MpvEvent {
  const MpvEndFile(this.reason, this.error, this.playlistEntryId);

  /// One of [MpvEndReason].
  final int reason;

  /// An [MpvError] value when [reason] is [MpvEndReason.error].
  final int error;
  final int playlistEntryId;

  @override
  String toString() => 'MpvEndFile(reason: $reason, error: $error)';
}

final class MpvFileLoaded extends MpvEvent {
  const MpvFileLoaded();
}

final class MpvSeekStarted extends MpvEvent {
  const MpvSeekStarted();
}

final class MpvPlaybackRestart extends MpvEvent {
  const MpvPlaybackRestart();
}

final class MpvVideoReconfig extends MpvEvent {
  const MpvVideoReconfig();
}

final class MpvAudioReconfig extends MpvEvent {
  const MpvAudioReconfig();
}

final class MpvLogMessage extends MpvEvent {
  const MpvLogMessage(this.prefix, this.level, this.text);
  final String prefix;
  final String level;
  final String text;

  @override
  String toString() => '[$prefix] $level: ${text.trimRight()}';
}

final class MpvShutdown extends MpvEvent {
  const MpvShutdown();
}

final class _MpvReply extends MpvEvent {
  const _MpvReply(this.id, this.error, this.value);
  final int id;
  final int error;
  final Object? value;
}

/// Failure of an mpv API call, carrying the [MpvError] code.
final class MpvException implements Exception {
  const MpvException(this.operation, this.code, [this.message]);

  final String operation;
  final int code;
  final String? message;

  @override
  String toString() =>
      'MpvException($operation: $code${message == null ? '' : ' $message'})';
}

/// Thin owner of one `mpv_handle` (ADR-004: own `dart:ffi` wrapper).
///
/// Requests are issued with the asynchronous client API from the owning
/// isolate and never block it; `mpv_wait_event` runs on a dedicated event
/// isolate (docs/05 §7), which converts events to Dart values and posts them
/// back in batches.
final class MpvClient {
  MpvClient._(this._mpv, this._handle);

  final Libmpv _mpv;
  final Pointer<mpv_handle> _handle;
  final _events = StreamController<MpvEvent>.broadcast(sync: true);
  final _pending = <int, Completer<Object?>>{};
  final _observed = <int, String>{};
  var _nextId = 1;
  ReceivePort? _port;
  Completer<void>? _shutdown;
  var _destroyed = false;

  MpvBindings get _b => _mpv.bindings;

  /// Native handle address, handed to render bridges and stream protocols.
  int get handleAddress => _handle.address;

  Pointer<mpv_handle> get handle => _handle;

  Libmpv get library => _mpv;

  bool get isDestroyed => _destroyed;

  /// Events in order. Property changes for one wakeup arrive together.
  Stream<MpvEvent> get events => _events.stream;

  /// Creates and initialises a core with [options] (set before
  /// `mpv_initialize`, so they act as command-line options).
  ///
  /// Options that the loaded libmpv does not know are skipped and reported in
  /// [rejectedOptions] instead of failing, so newer defaults degrade on older
  /// builds.
  static Future<MpvClient> create({
    Map<String, String> options = const {},
    String logLevel = 'warn',
    Libmpv? library,
  }) async {
    final mpv = library ?? Libmpv.open();
    final b = mpv.bindings;
    final handle = b.mpv_create();
    if (handle == nullptr) {
      throw const MpvException('mpv_create', MpvError.nomem);
    }
    final client = MpvClient._(mpv, handle);
    using((arena) {
      for (final MapEntry(:key, :value) in options.entries) {
        final rc = b.mpv_set_option_string(
          handle,
          key.toNativeUtf8(allocator: arena).cast(),
          value.toNativeUtf8(allocator: arena).cast(),
        );
        if (rc < 0) client.rejectedOptions[key] = rc;
      }
    });
    final rc = b.mpv_initialize(handle);
    if (rc < 0) {
      b.mpv_terminate_destroy(handle);
      throw MpvException('mpv_initialize', rc);
    }
    using((arena) {
      b.mpv_request_log_messages(
        handle,
        logLevel.toNativeUtf8(allocator: arena).cast(),
      );
    });
    await client._startEventIsolate();
    return client;
  }

  /// Options the core refused at creation, with the [MpvError] code.
  final Map<String, int> rejectedOptions = {};

  Future<void> _startEventIsolate() async {
    final port = _port = ReceivePort('mpv-events');
    _shutdown = Completer<void>();
    port.listen((message) {
      if (message is! List<MpvEvent>) return;
      message.forEach(_dispatch);
    });
    await Isolate.spawn(
      _eventLoop,
      (_handle.address, port.sendPort, _mpv.path),
      debugName: 'mpv-events',
      errorsAreFatal: false,
    );
  }

  void _dispatch(MpvEvent e) {
    switch (e) {
      case _MpvReply(:final id, :final error, :final value):
        final c = _pending.remove(id);
        if (c == null) return;
        if (error < 0) {
          c.completeError(MpvException('async request', error));
        } else {
          c.complete(value);
        }
        return;
      case MpvShutdown():
        if (!(_shutdown?.isCompleted ?? true)) _shutdown!.complete();
      default:
        break;
    }
    if (!_events.isClosed) _events.add(e);
  }

  void _checkAlive() {
    if (_destroyed) {
      throw const MpvException('use after destroy', MpvError.uninitialized);
    }
  }

  Future<Object?> _track(int id, int rc, String op) {
    if (rc < 0) {
      return Future.error(MpvException(op, rc));
    }
    return (_pending[id] = Completer<Object?>()).future;
  }

  /// Runs an mpv command (`loadfile`, `seek`, …); completes with its result.
  Future<Object?> command(List<String> args) {
    _checkAlive();
    final id = _nextId++;
    final rc = using((arena) {
      final argv = arena<Pointer<Char>>(args.length + 1);
      for (var i = 0; i < args.length; i++) {
        argv[i] = args[i].toNativeUtf8(allocator: arena).cast();
      }
      argv[args.length] = nullptr;
      return _b.mpv_command_async(_handle, id, argv);
    });
    return _track(id, rc, 'command ${args.first}');
  }

  /// Sets a property from its string form (as on the command line).
  Future<void> setProperty(String name, String value) {
    _checkAlive();
    final id = _nextId++;
    final rc = using((arena) {
      final data = arena<Pointer<Char>>()
        ..value = value.toNativeUtf8(allocator: arena).cast();
      return _b.mpv_set_property_async(
        _handle,
        id,
        name.toNativeUtf8(allocator: arena).cast(),
        mpv_format.MPV_FORMAT_STRING,
        data.cast(),
      );
    });
    return _track(id, rc, 'set $name');
  }

  /// Reads a property as a node (maps, lists and scalars).
  Future<Object?> getProperty(String name) {
    _checkAlive();
    final id = _nextId++;
    final rc = using(
      (arena) => _b.mpv_get_property_async(
        _handle,
        id,
        name.toNativeUtf8(allocator: arena).cast(),
        mpv_format.MPV_FORMAT_NODE,
      ),
    );
    return _track(id, rc, 'get $name');
  }

  /// Synchronous string read, for values needed before the first event
  /// (e.g. `mpv-version`). Cheap; never call it on per-frame paths.
  String? getPropertyStringSync(String name) {
    _checkAlive();
    return using((arena) {
      final p = _b.mpv_get_property_string(
        _handle,
        name.toNativeUtf8(allocator: arena).cast(),
      );
      if (p == nullptr) return null;
      final s = p.cast<Utf8>().toDartString();
      _b.mpv_free(p.cast());
      return s;
    });
  }

  /// Observes [name]; changes arrive as [MpvPropertyChange] in [format]
  /// ([MpvFormat.node] for structured values).
  void observe(String name, int format) {
    _checkAlive();
    final id = _nextId++;
    _observed[id] = name;
    final rc = using(
      (arena) => _b.mpv_observe_property(
        _handle,
        id,
        name.toNativeUtf8(allocator: arena).cast(),
        mpv_format.fromValue(format),
      ),
    );
    if (rc < 0) throw MpvException('observe $name', rc);
  }

  /// Shuts the core down and frees it. Safe to call twice.
  Future<void> destroy() async {
    if (_destroyed) return;
    _destroyed = true;
    final done = _shutdown;
    // `quit` makes the core send MPV_EVENT_SHUTDOWN, which ends the event
    // isolate's wait loop before the handle is freed.
    using((arena) {
      final argv = arena<Pointer<Char>>(2);
      argv[0] = 'quit'.toNativeUtf8(allocator: arena).cast();
      argv[1] = nullptr;
      _b.mpv_command_async(_handle, 0, argv);
    });
    if (done != null) {
      await done.future.timeout(const Duration(seconds: 5), onTimeout: () {});
    }
    _b.mpv_terminate_destroy(_handle);
    for (final c in _pending.values) {
      c.completeError(
        const MpvException('core destroyed', MpvError.uninitialized),
      );
    }
    _pending.clear();
    _port?.close();
    await _events.close();
  }
}

/// Event loop on its own isolate: blocks in `mpv_wait_event`, drains the
/// queue, converts events and posts them as one batch per wakeup.
void _eventLoop((int, SendPort, String) args) {
  final (address, port, path) = args;
  final b = MpvBindings(DynamicLibrary.open(path));
  final handle = Pointer<mpv_handle>.fromAddress(address);
  final names = <int, String>{};
  var running = true;
  while (running) {
    final batch = <MpvEvent>[];
    var timeout = -1.0;
    while (true) {
      final ev = b.mpv_wait_event(handle, timeout).ref;
      timeout = 0;
      final id = ev.event_idAsInt;
      if (id == MpvEventId.none) break;
      final e = _convert(b, ev, names);
      if (e != null) batch.add(e);
      if (id == MpvEventId.shutdown) {
        running = false;
        break;
      }
    }
    if (batch.isNotEmpty) port.send(batch);
  }
}

MpvEvent? _convert(MpvBindings b, mpv_event ev, Map<int, String> names) {
  switch (ev.event_idAsInt) {
    case MpvEventId.shutdown:
      return const MpvShutdown();
    case MpvEventId.logMessage:
      final m = ev.data.cast<mpv_event_log_message>().ref;
      return MpvLogMessage(
        m.prefix.cast<Utf8>().toDartString(),
        m.level.cast<Utf8>().toDartString(),
        m.text.cast<Utf8>().toDartString(),
      );
    case MpvEventId.getPropertyReply:
      final p = ev.data.cast<mpv_event_property>();
      return _MpvReply(
        ev.reply_userdata,
        ev.error,
        p == nullptr ? null : readMpvValue(p.ref.formatAsInt, p.ref.data),
      );
    case MpvEventId.setPropertyReply:
      return _MpvReply(ev.reply_userdata, ev.error, null);
    case MpvEventId.commandReply:
      final c = ev.data.cast<mpv_event_command>();
      return _MpvReply(
        ev.reply_userdata,
        ev.error,
        c == nullptr ? null : readMpvNode(c.ref.result),
      );
    case MpvEventId.startFile:
      final s = ev.data.cast<mpv_event_start_file>();
      return MpvStartFile(s == nullptr ? 0 : s.ref.playlist_entry_id);
    case MpvEventId.endFile:
      final e = ev.data.cast<mpv_event_end_file>().ref;
      return MpvEndFile(e.reasonAsInt, e.error, e.playlist_entry_id);
    case MpvEventId.fileLoaded:
      return const MpvFileLoaded();
    case MpvEventId.seek:
      return const MpvSeekStarted();
    case MpvEventId.playbackRestart:
      return const MpvPlaybackRestart();
    case MpvEventId.videoReconfig:
      return const MpvVideoReconfig();
    case MpvEventId.audioReconfig:
      return const MpvAudioReconfig();
    case MpvEventId.propertyChange:
      final p = ev.data.cast<mpv_event_property>().ref;
      final name = names[ev.reply_userdata] ??= p.name
          .cast<Utf8>()
          .toDartString();
      return MpvPropertyChange(name, readMpvValue(p.formatAsInt, p.data));
    default:
      return null;
  }
}
