import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/platform/android/android_sftp.dart';
import 'package:mediahro/platform/android/gen/sftp_api.pigeon.dart';
import 'package:mediahro/platform/secure_transport.dart';

/// The Dart half of lane C4a's SFTP: endpoint mapping (references only)
/// and the error mapping B2's SFTP file system relies on.
final class _FakeSftp extends SftpHostApi {
  SftpEndpointMsg? endpoint;
  PlatformException? fail;

  @override
  Future<SftpSessionMsg> connect(SftpEndpointMsg endpoint) async {
    this.endpoint = endpoint;
    if (fail case final e?) throw e;
    return SftpSessionMsg(
      id: 's1',
      hostKeySha256: 'AB:CD',
      authenticated: true,
    );
  }

  @override
  Future<SftpEntryMsg> stat(String sessionId, String path) async {
    if (fail case final e?) throw e;
    return SftpEntryMsg(
      path: path,
      isDirectory: false,
      size: 5,
      modifiedMs: 1000,
    );
  }
}

void main() {
  const endpoint = SftpEndpoint(
    host: 'nas.local',
    username: 'me',
    passwordSecretRef: 'src1/password',
    knownHostKeySha256: 'AB:CD',
  );

  test('NET-004 only secret references cross to the platform', () async {
    final api = _FakeSftp();
    final s = await AndroidSftp(api: api).connect(endpoint);
    expect(api.endpoint!.passwordSecretRef, 'src1/password');
    expect(api.endpoint!.port, 22);
    expect(api.endpoint!.knownHostKeySha256, 'AB:CD');
    expect(s.hostKeySha256, 'AB:CD');
    final e = await s.stat('/a');
    expect(e.size, 5);
    expect(e.modified, DateTime.fromMillisecondsSinceEpoch(1000));
  });

  test('NET-004 errors map to what the SFTP file system expects', () async {
    final api = _FakeSftp();
    final sftp = AndroidSftp(api: api);
    api.fail = PlatformException(code: 'connectFailed', message: 'refused');
    await expectLater(sftp.connect(endpoint), throwsA(isA<SocketException>()));
    api.fail = PlatformException(code: 'timeout');
    await expectLater(sftp.connect(endpoint), throwsA(isA<TimeoutException>()));
    api.fail = null;
    final s = await sftp.connect(endpoint);
    api.fail = PlatformException(code: 'notFound', message: 'gone');
    await expectLater(s.stat('/x'), throwsA(isA<PathNotFoundException>()));
    api.fail = PlatformException(code: 'authFailed');
    await expectLater(
      s.stat('/x'),
      throwsA(
        isA<PlatformException>().having((e) => e.code, 'code', 'authFailed'),
      ),
    );
  });
}
