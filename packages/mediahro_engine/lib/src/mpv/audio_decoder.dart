import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mediahro_engine/src/api/media_source.dart';
import 'package:mediahro_engine/src/api/models.dart';
import 'package:mediahro_engine/src/mpv/mpv_client.dart';
import 'package:mediahro_engine/src/mpv/mpv_node.dart';
import 'package:mediahro_engine/src/mpv/pcm_storage.dart';
import 'package:mediahro_engine/src/mpv/render_mapping.dart';
import 'package:mediahro_engine/src/mpv/scratch.dart';
import 'package:mediahro_engine/src/mpv/stream_protocol.dart';
// The mpv bindings are an engine-private part of mediahro_ffi (lane B1).
// ignore: implementation_imports
import 'package:mediahro_ffi/src/mpv/mpv.dart' show Libmpv;
import 'package:meta/meta.dart';

/// Offline audio decode for analysis (ADR-032): SUB-050 auto-sync, SUB-052
/// auto-captions and MUS-010 fingerprints need a source's audio faster
/// than playback and without playing it.
///
/// A silent libmpv core of its own (`ao=pcm`, `untimed`, no video) opens the
/// source once and decodes it as fast as the CPU allows (about 1000× real
/// time on a desktop) into [PcmStorage]; the stream hands it on in chunks.
///
/// mpv decodes far faster than a `pause` command can land, so the core
/// decodes in [window]s instead: `keep-open` with a moving `end` makes it
/// stop by itself at each window's end, and it continues (an exact seek to
/// that point, served from the demuxer cache) only once the consumer has
/// taken nearly everything decoded. Delivered PCM is released from the
/// storage, so a feature film needs about one window of memory.
final class AudioDecoder {
  AudioDecoder(
    this.source, {
    this.trackId,
    this.sampleRate = 16000,
    this.mono = true,
    this.start,
    this.end,
    this.libmpvPath,
    this.window = const Duration(seconds: 30),
  }) {
    _out = StreamController<Float32List>(
      onListen: () => unawaited(_run()),
      onCancel: () {
        _cancelled = true;
        _wake();
        return _finished.future;
      },
      onResume: _wake,
    );
  }

  final MediaSource source;
  final int? trackId;
  final int sampleRate;
  final bool mono;
  final Duration? start;
  final Duration? end;
  final String? libmpvPath;
  final Duration window;

  late final StreamController<Float32List> _out;
  final _finished = Completer<void>();
  bool _cancelled = false;
  Completer<void>? _waiter;

  /// Decoders whose core is running (tests: cancel stops the core).
  @visibleForTesting
  static int active = 0;

  /// Most decoded-but-undelivered PCM any decoder held, in bytes (tests:
  /// decoding stays about one window ahead of the consumer).
  @visibleForTesting
  static int peakBacklogBytes = 0;

  Stream<Float32List> get stream => _out.stream;

  int get _channels => mono ? 1 : 2;
  int get _frameBytes => _channels * 4;

  // Half a second of audio per chunk.
  int get _chunkBytes => (sampleRate ~/ 2) * _frameBytes;

  void _wake() {
    final w = _waiter;
    _waiter = null;
    if (w != null && !w.isCompleted) w.complete();
  }

  // Waits for a resume or cancel, or [timeout] at most.
  Future<void> _sleep(Duration timeout) {
    final w = _waiter ??= Completer<void>();
    return w.future.timeout(timeout, onTimeout: () {});
  }

  Future<void> _run() async {
    PcmStorage? storage;
    MpvClient? client;
    MpvStreamProtocol? protocol;
    RandomAccessFile? raf;
    StreamSubscription<MpvEvent>? events;
    (Object, StackTrace)? failure;
    active++;
    try {
      storage = await PcmStorage.create(
        slice: false,
        memoryOnly: isSensitiveSource(source),
      );
      client = await MpvClient.create(
        options: {
          'config': 'no',
          'terminal': 'no',
          'load-scripts': 'no',
          'ytdl': 'no',
          'idle': 'yes',
          'vid': 'no',
          'sid': 'no',
          'ao': 'pcm',
          'ao-pcm-file': storage.pcmPath,
          'ao-pcm-waveheader': 'no',
          'ao-pcm-append': 'yes',
          'audio-format': 'float',
          'audio-channels': mono ? 'mono' : 'stereo',
          'audio-samplerate': '$sampleRate',
          // As fast as the CPU allows.
          'untimed': 'yes',
          'hr-seek': 'yes',
          // Each window ends paused at its end instead of unloading.
          'keep-open': 'yes',
          'keep-open-pause': 'yes',
        },
        library: Libmpv.open(path: libmpvPath),
      );
      protocol = MpvStreamProtocol.register(client);
      final ended = Completer<int>();
      var atWindowEnd = false;
      events = client.events.listen((e) {
        switch (e) {
          case MpvEndFile(:final reason) when !ended.isCompleted:
            ended.complete(reason);
          case MpvPropertyChange(name: 'eof-reached', :final value):
            atWindowEnd = value == true;
            _wake();
          default:
            break;
        }
      });
      client.observe('eof-reached', MpvFormat.flag);
      final src = source;
      final url = switch (src) {
        UriSource(:final uri) =>
          uri.scheme == 'file' ? uri.toFilePath() : uri.toString(),
        VirtualFileSource(:final file) =>
          protocol == null
              ? throw const EngineException(
                  EngineError(
                    code: EngineErrorCode.sourceUnavailable,
                    detail: 'stream shim missing',
                  ),
                )
              : protocol.urlFor(file),
      };
      final perFile = <String, String>{
        if (trackId != null) 'aid': '$trackId',
        if (start != null) 'start': secondsValue(start!),
        if (src case UriSource(:final headers) when headers.isNotEmpty)
          'http-header-fields': headers.entries
              .map((e) => '${e.key}: ${e.value}')
              .join(','),
        if (src case UriSource(:final userAgent?)) 'user-agent': userAgent,
      };
      final from = start ?? Duration.zero;
      var windowEnd = _windowEnd(from);
      perFile['end'] = secondsValue(windowEnd);
      await client.loadfile(url, options: _encode(perFile));
      raf = await File(storage.pcmPath).open();
      Duration? duration;
      var read = 0;
      var total = 0;
      var idle = 0;
      while (!_cancelled && !ended.isCompleted) {
        // One writer keeps one file open for the whole decode, so once it
        // has written, the file's name can go: nothing is left on disk if
        // the app dies mid-decode.
        if (!storage.unlinked && storage.pcmLength > 0) {
          storage.unlinkWhileOpen(raf);
        }
        final backlog = storage.pcmLength - read;
        if (backlog > peakBacklogBytes) peakBacklogBytes = backlog;
        if (!_out.isPaused && backlog >= _chunkBytes) {
          final n = await _deliver(raf, read, backlog);
          read += n;
          total += n;
          storage.release(read);
          idle = 0;
          continue;
        }
        // A window can end before its eof-reached change is observed again.
        if (!atWindowEnd && ++idle % 20 == 0) {
          atWindowEnd = await client.getProperty('eof-reached') == true;
        }
        if (atWindowEnd && backlog < _chunkBytes) {
          duration ??= _seconds(await client.getProperty('duration'));
          final pos = _seconds(await client.getProperty('time-pos'));
          final last =
              (end != null && windowEnd >= end!) ||
              (duration != null &&
                  windowEnd >= duration - const Duration(milliseconds: 50)) ||
              // The media ended inside the window.
              (pos != null && pos < windowEnd - const Duration(seconds: 1));
          if (last) break;
          // The next window continues exactly where this one stopped.
          final from = windowEnd;
          windowEnd = _windowEnd(from);
          atWindowEnd = false;
          await client.setProperty('end', secondsValue(windowEnd));
          await client.command(['seek', secondsValue(from), 'absolute+exact']);
          await client.setProperty('pause', 'no');
          continue;
        }
        await _sleep(const Duration(milliseconds: 10));
      }
      if (_cancelled) return;
      final reason = ended.isCompleted ? await ended.future : null;
      // Closing the core flushes the PCM file.
      await _closeCore(client, protocol);
      client = null;
      if (reason == MpvEndReason.error) {
        throw const EngineException(
          EngineError(code: EngineErrorCode.decodeFailed),
        );
      }
      while (!_cancelled) {
        final backlog = storage.pcmLength - read;
        if (backlog < _frameBytes) break;
        if (_out.isPaused) {
          await _sleep(const Duration(milliseconds: 100));
          continue;
        }
        final n = await _deliver(raf, read, backlog);
        read += n;
        total += n;
        storage.release(read);
      }
      if (total == 0 && !_cancelled) {
        throw const EngineException(
          EngineError(
            code: EngineErrorCode.unsupportedFormat,
            detail: 'no audio',
          ),
        );
      }
    } on Object catch (e, st) {
      failure = (e, st);
    } finally {
      await events?.cancel();
      await raf?.close().catchError((Object _) => raf!);
      if (client != null) await _closeCore(client, protocol);
      await protocol?.dispose();
      await storage?.dispose();
      active--;
      if (!_finished.isCompleted) _finished.complete();
      // Errors and the end arrive once the core is gone.
      if (!_cancelled) {
        if (failure != null) _out.addError(failure.$1, failure.$2);
        await _out.close();
      }
    }
  }

  Duration _windowEnd(Duration from) {
    final next = from + window;
    final e = end;
    return e != null && e < next ? e : next;
  }

  static Duration? _seconds(Object? v) =>
      v is num ? Duration(microseconds: (v * 1e6).round()) : null;

  static Future<void> _closeCore(
    MpvClient client,
    MpvStreamProtocol? protocol,
  ) async {
    protocol?.shutdown();
    await client.destroy();
  }

  // Sends up to one chunk from [offset]; returns the bytes delivered.
  Future<int> _deliver(RandomAccessFile raf, int offset, int backlog) async {
    var n = backlog < _chunkBytes ? backlog : _chunkBytes;
    n -= n % _frameBytes;
    await raf.setPosition(offset);
    final bytes = await raf.read(n);
    final whole = bytes.length - bytes.length % _frameBytes;
    if (whole == 0) return 0;
    final copy = Uint8List.fromList(bytes.sublist(0, whole));
    _out.add(copy.buffer.asFloat32List(0, whole ~/ 4));
    return whole;
  }
}

// mpv per-file options with each value length-prefixed (no escaping).
String _encode(Map<String, String> options) => options.entries
    .map((e) => '${e.key}=%${utf8.encode(e.value).length}%${e.value}')
    .join(',');
