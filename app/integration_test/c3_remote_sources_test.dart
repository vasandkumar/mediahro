// Lane C3 device batch, photo sources (IMG-016): the gallery over a WebDAV
// share, on the phone. The share is served from this process on 127.0.0.1
// (the same in-memory server the desktop tests use); the scan runs on its
// isolate, the photos open through the real network stack, thumbnails come
// from the fake-codec pipeline, and a share that goes away leaves the
// library as it was.
//
//   flutter test integration_test/c3_remote_sources_test.dart -d <serial> \
//     --no-dds -P kotlin.incremental=false
import 'package:integration_test/integration_test.dart';

import '../test/features/photos/remote_sources_test.dart' as remote;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  remote.main();
}
