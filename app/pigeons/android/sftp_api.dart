// Pigeon messages for SftpFacade on Android (lane C4a, NET-004, ADR-017:
// sshj over the platform JCA, no bundled crypto library).
//
//   dart run pigeon --input pigeons/android/sftp_api.dart   (from app/)
//
// Pigeon's schema is positional; named bool parameters do not map to Kotlin.
// ignore_for_file: avoid_positional_boolean_parameters

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/android/gen/sftp_api.pigeon.dart',
    kotlinOut:
        'android/app/src/main/kotlin/com/mediahro/mediahro/pigeon/SftpApi.g.kt',
    kotlinOptions: KotlinOptions(
      // Shares FlutterError with StorageApi.g.kt.
      package: 'com.mediahro.mediahro.pigeon',
      includeErrorClass: false,
    ),
    dartPackageName: 'mediahro',
  ),
)
class SftpEndpointMsg {
  SftpEndpointMsg(
    this.host,
    this.port,
    this.username,
    this.passwordSecretRef,
    this.privateKeySecretRef,
    this.keyPassphraseSecretRef,
    this.knownHostKeySha256,
  );
  String host;
  int port;
  String username;
  String? passwordSecretRef;
  String? privateKeySecretRef;
  String? keyPassphraseSecretRef;
  String? knownHostKeySha256;
}

class SftpSessionMsg {
  SftpSessionMsg(this.id, this.hostKeySha256, this.authenticated);
  String id;
  String hostKeySha256;

  /// False when the host key was unknown or changed: nothing was sent.
  bool authenticated;
}

class SftpEntryMsg {
  SftpEntryMsg(this.path, this.isDirectory, this.size, this.modifiedMs);
  String path;
  bool isDirectory;
  int? size;
  int? modifiedMs;
}

@HostApi()
abstract class SftpHostApi {
  @async
  SftpSessionMsg connect(SftpEndpointMsg endpoint);

  @async
  List<SftpEntryMsg> list(String sessionId, String path);

  @async
  SftpEntryMsg stat(String sessionId, String path);

  @async
  Uint8List read(String sessionId, String path, int offset, int length);

  @async
  void rename(String sessionId, String from, String to);

  @async
  void delete(String sessionId, String path);

  @async
  void mkdir(String sessionId, String path);

  /// Returns a write-sink id.
  @async
  String openWrite(String sessionId, String path, bool truncate);

  @async
  void write(String sinkId, Uint8List data);

  @async
  void closeWrite(String sinkId, bool abort);

  @async
  void close(String sessionId);
}
