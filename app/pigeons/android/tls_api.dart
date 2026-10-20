// Pigeon messages for TlsSocketFacade and TlsServerFacade on Android
// (lane C4a, ADR-017: the OS TLS stack; NET-004 FTPS, CAST-001, NET-017).
//
//   dart run pigeon --input pigeons/android/tls_api.dart   (from app/)
//
// Pigeon's schema is positional; named bool parameters do not map to Kotlin.
// ignore_for_file: avoid_positional_boolean_parameters

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/android/gen/tls_api.pigeon.dart',
    kotlinOut:
        'android/app/src/main/kotlin/com/mediahro/mediahro/pigeon/TlsApi.g.kt',
    kotlinOptions: KotlinOptions(
      // Shares FlutterError and the event-channel classes of StorageApi.g.kt.
      package: 'com.mediahro.mediahro.pigeon',
      includeErrorClass: false,
    ),
    dartPackageName: 'mediahro',
  ),
)
class TlsSocketInfoMsg {
  TlsSocketInfoMsg(
    this.id,
    this.isTls,
    this.protocolVersion,
    this.peerCertificateSha256,
  );
  String id;
  bool isTls;
  String protocolVersion;
  String peerCertificateSha256;
}

class TlsIdentityMsg {
  TlsIdentityMsg(this.label, this.certificateSha256);
  String label;
  String certificateSha256;
}

class TlsListenerMsg {
  TlsListenerMsg(this.id, this.port);
  String id;
  int port;
}

enum TlsEventKindMsg { data, closed, error, accepted }

class TlsEventMsg {
  TlsEventMsg(
    this.kind,
    this.socketId,
    this.data,
    this.message,
    this.listenerId,
    this.accepted,
  );
  TlsEventKindMsg kind;
  String socketId;
  Uint8List? data;
  String? message;
  String? listenerId;
  TlsSocketInfoMsg? accepted;
}

@HostApi()
abstract class TlsSocketHostApi {
  /// Fails with code `untrusted` (details: the peer SHA-256) when the
  /// certificate is neither trusted by the system nor pinned.
  @async
  TlsSocketInfoMsg connect(
    String host,
    int port,
    String? serverName,
    String? pinnedSha256,
    List<String> alpn,
    int timeoutMs,
    String? resumeSessionOf,
  );

  @async
  TlsSocketInfoMsg connectPlain(String host, int port, int timeoutMs);

  /// Returns the upgraded socket under a new id; the plain one stops.
  @async
  TlsSocketInfoMsg upgrade(
    String connectionId,
    String? serverName,
    String? pinnedSha256,
  );

  /// Starts delivering `data` events for [socketId] (after Dart listens).
  void startReading(String socketId);

  @async
  void write(String socketId, Uint8List data);

  @async
  void close(String socketId);
}

@HostApi()
abstract class TlsServerHostApi {
  @async
  TlsIdentityMsg identity(String label);

  @async
  TlsListenerMsg listen(String label, List<String> trustedPeers, int port);

  void setTrustedPeers(String listenerId, List<String> trustedPeers);

  @async
  void closeListener(String listenerId);

  @async
  TlsSocketInfoMsg connectMutual(
    String host,
    int port,
    String label,
    String peerSha256,
  );
}

@EventChannelApi(
  kotlinOptions: KotlinEventChannelOptions(includeSharedClasses: false),
)
abstract class TlsEventsApi {
  TlsEventMsg tlsEvents();
}
