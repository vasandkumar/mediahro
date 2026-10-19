@Tags(['ffi'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'conformance/suites.dart';

/// Desktop FFI contract tests (docs/11 §1): the engine conformance suites
/// against real libmpv. They skip when libmpv or the corpus is missing.
void main() => runConformanceSuites();
