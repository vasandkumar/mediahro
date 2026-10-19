@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro_design/mediahro_design.dart';
import 'package:mediahro_design/testing.dart';

import 'specimens.dart';

/// docs/11 §1: goldens per platform family × light/dark × 3 text scales ×
/// LTR/RTL × reduced motion. Each file holds the seven variant cells.
void main() {
  for (final family in PlatformFamily.values) {
    for (final brightness in Brightness.values) {
      group('SYS-008 goldens ${family.name}/${brightness.name}', () {
        for (final entry in specimens.entries) {
          testWidgets(entry.key, (tester) async {
            await expectGoldenMatrix(
              tester,
              name: entry.key,
              family: family,
              brightness: brightness,
              builder: entry.value,
            );
          });
        }
      });
    }
  }
}
