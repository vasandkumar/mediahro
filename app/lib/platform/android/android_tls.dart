import 'dart:async';

import 'package:flutter/services.dart';
import 'package:mediahro/platform/android/gen/tls_api.pigeon.dart';
import 'package:mediahro/platform/secure_transport.dart';

/// Routes the one TLS event channel (`TlsHub` in Kotlin) to sockets and
/// listeners by id.
final class _TlsEvents {
  _TlsEvents(Stream<TlsEventMsg> Function() events) {
    _sub = events().listen(_on);
  }

  late final StreamSubscription<TlsEventMsg> _sub;
  final Map<String, StreamController<Uint8List>> _sockets = {};
  final Map<String, void Function(TlsSocketInfoMsg)> _listeners = {};

  void _on(TlsEventMsg e) {
    switch (e.kind) {
      case TlsEventKindMsg.data:
        if (e.data case final data?) _sockets[e.socketId]?.add(data);
      case TlsEventKindMsg.closed:
        unawaited(_sockets.remove(e.socketId)?.close());
      case TlsEventKindMsg.error:
        final c = _sockets.remove(e.socketId);
        c?.addError(SocketException(e.message ?? 'connection error'));
        unawaited(c?.close());
      case TlsEventKindMsg.accepted:
        if (e.accepted case final info?) _listeners[e.listenerId]?.call(info);
    }
  }

  StreamController<Uint8List> open(String id) =>
      _sockets[id] = StreamController<Uint8List>();

  /// Stops routing to [id] without closing its stream (after an upgrade the
  /// plain socket simply goes quiet).
  void detach(String id) => _sockets.remove(id);

  void close(String id) => unawaited(_sockets.remove(id)?.close());

  void onAccepted(String listenerId, void Function(TlsSocketInfoMsg) f) =>
      _listeners[listenerId] = f;

  void forget(String listenerId) => _listeners.remove(listenerId);

  Future<void> dispose() => _sub.cancel();
}

/// Socket I/O errors reported by the platform.
final class SocketException implements Exception {
  const SocketException(this.message);

  final String message;

  @override
  String toString() => 'SocketException($message)';
}

final class _AndroidTlsSocket implements TlsSocket {
  _AndroidTlsSocket(this._api, this._events, this._info)
    : _input = _events.open(_info.id) {
    unawaited(_api.startReading(_info.id));
  }

  final TlsSocketHostApi _api;
  final _TlsEvents _events;
  final TlsSocketInfoMsg _info;
  final StreamController<Uint8List> _input;

  @override
  String get id => _info.id;

  @override
  bool get isTls => _info.isTls;

  @override
  String get protocolVersion => _info.protocolVersion;

  @override
  String get peerCertificateSha256 => _info.peerCertificateSha256;

  @override
  Stream<Uint8List> get input => _input.stream;

  @override
  Future<void> write(Uint8List data) => _api.write(id, data);

  @override
  Future<void> close() async {
    _events.close(id);
    await _api.close(id);
  }
}

/// [TlsSocketFacade] on Android (ADR-017; NET-004 FTPS, CAST-001): SSLSocket
/// on the OS stack, TLS 1.2/1.3, system CAs with hostname checks or a
/// user-confirmed fingerprint pin (`TlsModules.kt`).
final class AndroidTlsSocketFacade implements TlsSocketFacade {
  AndroidTlsSocketFacade({
    TlsSocketHostApi? api,
    Stream<TlsEventMsg> Function()? events,
  }) : _api = api ?? TlsSocketHostApi(),
       _events = _shared(events);

  final TlsSocketHostApi _api;
  final _TlsEvents _events;

  @override
  Future<TlsSocket> connect(
    String host,
    int port, {
    String? serverName,
    String? pinnedSha256,
    List<String> alpn = const [],
    Duration timeout = const Duration(seconds: 15),
    String? resumeSessionOf,
  }) => _untrusted(
    host,
    () async => _AndroidTlsSocket(
      _api,
      _events,
      await _api.connect(
        host,
        port,
        serverName,
        pinnedSha256,
        alpn,
        timeout.inMilliseconds,
        resumeSessionOf,
      ),
    ),
  );

  @override
  Future<TlsSocket> connectPlain(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 15),
  }) async => _AndroidTlsSocket(
    _api,
    _events,
    await _api.connectPlain(host, port, timeout.inMilliseconds),
  );

  @override
  Future<TlsSocket> upgrade(
    String connectionId, {
    String? serverName,
    String? pinnedSha256,
  }) => _untrusted(serverName ?? connectionId, () async {
    final info = await _api.upgrade(connectionId, serverName, pinnedSha256);
    _events.detach(connectionId);
    return _AndroidTlsSocket(_api, _events, info);
  });
}

/// [TlsServerFacade] on Android (NET-017): a Keystore EC identity,
/// mutual-TLS listeners that accept only paired fingerprints, and pinned
/// mutual-TLS client connections (`TlsModules.kt`).
final class AndroidTlsServerFacade implements TlsServerFacade {
  AndroidTlsServerFacade({
    TlsServerHostApi? api,
    TlsSocketHostApi? sockets,
    Stream<TlsEventMsg> Function()? events,
    this.mutualTimeout = const Duration(seconds: 30),
  }) : _api = api ?? TlsServerHostApi(),
       _sockets = sockets ?? TlsSocketHostApi(),
       _events = _shared(events);

  /// The most a mutual-TLS connect may take: the native side has its own 15 s
  /// limits on the connection and the handshake; this is the safety net.
  final Duration mutualTimeout;

  final TlsServerHostApi _api;
  final TlsSocketHostApi _sockets;
  final _TlsEvents _events;

  @override
  Future<TlsIdentity> identity(String label) async {
    final i = await _api.identity(label);
    return TlsIdentity(label: i.label, certificateSha256: i.certificateSha256);
  }

  @override
  Future<TlsListener> listen(
    TlsIdentity identity, {
    required Set<String> trustedPeers,
    int port = 0,
  }) async {
    final l = await _api.listen(identity.label, trustedPeers.toList(), port);
    final connections = StreamController<TlsSocket>();
    _events.onAccepted(
      l.id,
      (info) => connections.add(_AndroidTlsSocket(_sockets, _events, info)),
    );
    return _AndroidTlsListener(_api, _events, l, connections);
  }

  @override
  Future<TlsSocket> connectMutual(
    String host,
    int port, {
    required TlsIdentity identity,
    required String peerSha256,
  }) async => _AndroidTlsSocket(
    _sockets,
    _events,
    await _api
        .connectMutual(host, port, identity.label, peerSha256)
        .timeout(
          mutualTimeout,
          onTimeout: () => throw PlatformException(
            code: 'timeout',
            message: 'The paired device did not answer in time',
          ),
        ),
  );
}

final class _AndroidTlsListener implements TlsListener {
  _AndroidTlsListener(this._api, this._events, this._msg, this._connections);

  final TlsServerHostApi _api;
  final _TlsEvents _events;
  final TlsListenerMsg _msg;
  final StreamController<TlsSocket> _connections;

  @override
  int get port => _msg.port;

  @override
  Stream<TlsSocket> get connections => _connections.stream;

  @override
  Future<void> setTrustedPeers(Set<String> sha256s) =>
      _api.setTrustedPeers(_msg.id, sha256s.toList());

  @override
  Future<void> close() async {
    _events.forget(_msg.id);
    await _api.closeListener(_msg.id);
    // Not awaited: a controller's close() completes only once its listener has
    // seen the end of the stream, and a listener that is paused (a StreamIterator
    // between moveNext calls) never does, which hung every caller of close().
    unawaited(_connections.close());
  }
}

_TlsEvents? _sharedEvents;

/// One subscription to the event channel for every facade instance (a second
/// listener on the same channel would replace the first natively).
_TlsEvents _shared(Stream<TlsEventMsg> Function()? events) => events != null
    ? _TlsEvents(events)
    : _sharedEvents ??= _TlsEvents(tlsEvents);

/// `untrusted` from the module carries the peer fingerprint for the prompt.
Future<T> _untrusted<T>(String host, Future<T> Function() op) async {
  try {
    return await op();
  } on PlatformException catch (e) {
    if (e.code == 'untrusted' && e.details is String) {
      throw UntrustedCertificate(host, e.details! as String);
    }
    rethrow;
  }
}
