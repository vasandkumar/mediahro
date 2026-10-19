// Host side of profile/release integration runs (`flutter drive`), e.g. the
// LIB-003/LIB-005 perf budgets that debug `flutter test` runs only report.
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
