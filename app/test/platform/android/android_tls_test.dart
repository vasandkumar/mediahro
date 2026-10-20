import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/platform/android/android_tls.dart';
import 'package:mediahro/platform/android/gen/tls_api.pigeon.dart';
import 'package:mediahro/platform/secure_transport.dart';

/// The Dart half of lane C4a's TLS facades: event routing and errors.
final class _FakeSockets extends TlsSocketHostApi {
  final reading = <String>[];
  final closed = <String>[];
  PlatformException? failConnect;

  TlsSocketInfoMsg _info(String id, {bool tls = true}) => TlsSocketInfoMsg(
    id: id,
    isTls: tls,
    protocolVersion: tls ? 'TLSv1.3' : '',
    peerCertificateSha256: tls ? 'AB:CD' : '',
  );

  @override
  Future<TlsSocketInfoMsg> connect(
    String host,
    int port,
    String? serverName,
    String? pinnedSha256,
    List<String> alpn,
    int timeoutMs,
    String? resumeSessionOf,
  ) async {
    if (failConnect case final e?) throw e;
    return _info('t1');
  }

  @override
  Future<TlsSocketInfoMsg> connectPlain(
    String host,
    int port,
    int timeoutMs,
  ) async => _info('t2', tls: false);

  @override
  Future<TlsSocketInfoMsg> upgrade(
    String connectionId,
    String? serverName,
    String? pinnedSha256,
  ) async => _info('t3');

  @override
  Future<void> startReading(String socketId) async => reading.add(socketId);

  @override
  Future<void> close(String socketId) async => closed.add(socketId);
}

TlsEventMsg _data(String id, List<int> bytes) => TlsEventMsg(
  kind: TlsEventKindMsg.data,
  socketId: id,
  data: Uint8List.fromList(bytes),
);

void main() {
  late StreamController<TlsEventMsg> events;
  late _FakeSockets api;
  late AndroidTlsSocketFacade tls;

  setUp(() {
    events = StreamController.broadcast();
    api = _FakeSockets();
    tls = AndroidTlsSocketFacade(api: api, events: () => events.stream);
  });

  test(
    'NET-004 data reaches the right socket; closed ends its stream',
    () async {
      final s = await tls.connect('h', 21);
      expect(api.reading, ['t1']);
      expect(s.isTls, isTrue);
      expect(s.protocolVersion, 'TLSv1.3');
      final got = <int>[];
      final done = Completer<void>();
      s.input.listen(got.addAll, onDone: done.complete);
      events
        ..add(_data('other', [9]))
        ..add(_data('t1', [1, 2]))
        ..add(_data('t1', [3]))
        ..add(TlsEventMsg(kind: TlsEventKindMsg.closed, socketId: 't1'));
      await done.future;
      expect(got, [1, 2, 3]);
    },
  );

  test('NET-004 untrusted certificates carry the fingerprint', () async {
    api.failConnect = PlatformException(
      code: 'untrusted',
      message: 'Untrusted certificate',
      details: 'AA:BB',
    );
    await expectLater(
      tls.connect('nas.local', 990),
      throwsA(
        isA<UntrustedCertificate>()
            .having((e) => e.host, 'host', 'nas.local')
            .having((e) => e.sha256, 'sha256', 'AA:BB'),
      ),
    );
  });

  test('NET-004 an upgrade moves the data to the TLS socket', () async {
    final plain = await tls.connectPlain('h', 21);
    expect(plain.isTls, isFalse);
    final secure = await tls.upgrade(plain.id, pinnedSha256: 'AB:CD');
    expect(secure.id, 't3');
    expect(api.reading, ['t2', 't3']);
    final got = <int>[];
    secure.input.listen(got.addAll);
    events
      ..add(_data('t2', [0]))
      ..add(_data('t3', [7]));
    await pumpEventQueue();
    expect(got, [7]);
    await secure.close();
    expect(api.closed, ['t3']);
  });

  test('NET-004 read errors surface on the input stream', () async {
    final s = await tls.connect('h', 21);
    final errors = <Object>[];
    final done = Completer<void>();
    s.input.listen((_) {}, onError: errors.add, onDone: done.complete);
    events.add(
      TlsEventMsg(
        kind: TlsEventKindMsg.error,
        socketId: 't1',
        message: 'reset',
      ),
    );
    await done.future;
    expect(errors.single, isA<SocketException>());
  });
}
