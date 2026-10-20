import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Lane C4a: predictive back on an Android device (CORE-001). With
/// `enableOnBackInvokedCallback`, a system back reaches Flutter through the
/// activity's back dispatcher while a route can pop. The debug-only
/// `systemBack` op sends one the way the gesture or back button does.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final android = Platform.isAndroid;

  const hook = BasicMessageChannel<Object?>(
    'mediahro.test/session',
    StandardMessageCodec(),
  );

  testWidgets('CORE-001 system back pops the pushed route', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: ThemeData(
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: {
              TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
            },
          ),
        ),
        home: const SizedBox(key: Key('first')),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const SizedBox(key: Key('second')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('second')), findsOneWidget);

    expect(await hook.send(['systemBack']), isTrue);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('second')), findsNothing);
    expect(find.byKey(const Key('first')), findsOneWidget);
    expect(navigator.currentState!.canPop(), isFalse);
  }, skip: !android);
}
