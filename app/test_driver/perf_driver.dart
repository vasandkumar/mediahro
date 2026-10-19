import 'package:integration_test/integration_test_driver.dart';

/// Driver for profile-mode perf tests (`integration_test/*_perf_test.dart`).
/// Writes each test's `binding.reportData` to
/// `build/integration_response_data.json`; CI keeps one file per test.
Future<void> main() => integrationDriver();
