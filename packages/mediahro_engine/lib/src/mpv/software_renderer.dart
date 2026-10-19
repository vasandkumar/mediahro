import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:mediahro_engine/src/mpv/mpv_client.dart';
// The mpv bindings are an engine-private part of mediahro_ffi (lane B1).
// ignore: implementation_imports
import 'package:mediahro_ffi/src/mpv/mpv.dart';
import 'package:meta/meta.dart';

/// One rendered frame (`rgb0`, 4 bytes per pixel, rows of [stride] bytes).
@immutable
final class SoftwareFrame {
  const SoftwareFrame({
    required this.width,
    required this.height,
    required this.stride,
    required this.pixels,
    required this.index,
  });

  final int width;
  final int height;
  final int stride;
  final Uint8List pixels;

  /// 0 for the first frame after the renderer was created.
  final int index;

  /// `(r, g, b)` at ([x], [y]).
  (int, int, int) pixel(int x, int y) {
    final o = y * stride + x * 4;
    return (pixels[o], pixels[o + 1], pixels[o + 2]);
  }
}

/// `mpv_render_context` with the software backend (`vo=libmpv`).
///
/// Used where no GPU surface exists: the corpus and perf harnesses on CI
/// runners, FFI contract tests, and thumbnails. It renders video, OSD and
/// burned-in subtitles exactly as the GPU path composes them, which lets
/// tests check subtitle rendering by pixels (SUB-010, SUB-011, SUB-014).
/// On-screen playback never uses it.
final class SoftwareRenderer {
  SoftwareRenderer._(this._client, this._ctx, this._width, this._height);

  final MpvClient _client;
  final Pointer<mpv_render_context> _ctx;
  final int _width;
  final int _height;
  late final NativeCallable<mpv_render_update_fnFunction> _callable;
  Pointer<Uint8> _buffer = nullptr;
  final _frames = StreamController<SoftwareFrame>.broadcast();
  var _index = 0;
  var _rendering = false;
  var _disposed = false;
  final _first = Completer<Duration>();
  final Stopwatch _clock = Stopwatch()..start();

  /// Frames as they are rendered.
  Stream<SoftwareFrame> get frames => _frames.stream;

  /// Latest rendered frame.
  SoftwareFrame? latest;

  /// Time from [restartClock] (or creation) to the first rendered frame.
  Future<Duration> get firstFrame => _first.future;

  /// Restarts the first-frame clock (call right before `open`).
  void restartClock() {
    _clock.reset();
  }

  int get _stride => (_width * 4 + 63) & ~63;

  /// Creates a renderer of [width]×[height] pixels on [client]'s core.
  static SoftwareRenderer create(
    MpvClient client, {
    int width = 320,
    int height = 180,
  }) {
    final b = client.library.bindings;
    final ctx = using((arena) {
      final out = arena<Pointer<mpv_render_context>>();
      final params = arena<mpv_render_param>(2);
      params[0]
        ..typeAsInt = mpv_render_param_type.MPV_RENDER_PARAM_API_TYPE.value
        ..data = MPV_RENDER_API_TYPE_SW.toNativeUtf8(allocator: arena).cast();
      params[1]
        ..typeAsInt = mpv_render_param_type.MPV_RENDER_PARAM_INVALID.value
        ..data = nullptr;
      final rc = b.mpv_render_context_create(out, client.handle, params);
      if (rc < 0) throw MpvException('mpv_render_context_create', rc);
      return out.value;
    });
    final r = SoftwareRenderer._(client, ctx, width, height);
    r._buffer = malloc<Uint8>(r._stride * height);
    r._callable = NativeCallable<mpv_render_update_fnFunction>.listener(
      (Pointer<Void> _) => r._onUpdate(),
    );
    b.mpv_render_context_set_update_callback(
      ctx,
      r._callable.nativeFunction,
      nullptr,
    );
    return r;
  }

  void _onUpdate() {
    if (_disposed || _rendering) return;
    final b = _client.library.bindings;
    final flags = b.mpv_render_context_update(_ctx);
    if (flags & mpv_render_update_flag.MPV_RENDER_UPDATE_FRAME.value == 0) {
      return;
    }
    _rendering = true;
    try {
      using((arena) {
        final size = arena<Int>(2);
        size[0] = _width;
        size[1] = _height;
        final stride = arena<Size>()..value = _stride;
        final params = arena<mpv_render_param>(5);
        void set(int i, mpv_render_param_type t, Pointer<Void> data) {
          params[i]
            ..typeAsInt = t.value
            ..data = data;
        }

        set(0, mpv_render_param_type.MPV_RENDER_PARAM_SW_SIZE, size.cast());
        set(
          1,
          mpv_render_param_type.MPV_RENDER_PARAM_SW_FORMAT,
          'rgb0'.toNativeUtf8(allocator: arena).cast(),
        );
        set(2, mpv_render_param_type.MPV_RENDER_PARAM_SW_STRIDE, stride.cast());
        set(
          3,
          mpv_render_param_type.MPV_RENDER_PARAM_SW_POINTER,
          _buffer.cast(),
        );
        set(4, mpv_render_param_type.MPV_RENDER_PARAM_INVALID, nullptr);
        final rc = b.mpv_render_context_render(_ctx, params);
        if (rc < 0) return;
      });
      final frame = SoftwareFrame(
        width: _width,
        height: _height,
        stride: _stride,
        pixels: Uint8List.fromList(_buffer.asTypedList(_stride * _height)),
        index: _index++,
      );
      latest = frame;
      if (!_first.isCompleted) _first.complete(_clock.elapsed);
      if (!_frames.isClosed) _frames.add(frame);
    } finally {
      _rendering = false;
    }
  }

  /// Frees the render context. Must run before the core is destroyed.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _client.library.bindings
      ..mpv_render_context_set_update_callback(_ctx, nullptr, nullptr)
      ..mpv_render_context_free(_ctx);
    _callable.close();
    malloc.free(_buffer);
    unawaited(_frames.close());
  }
}
