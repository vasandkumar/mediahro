// Host side of `flutter drive` for profile-mode performance tests
// (docs/11 §5). Writes the test's reportData to
// build/integration_response_data.json.
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
