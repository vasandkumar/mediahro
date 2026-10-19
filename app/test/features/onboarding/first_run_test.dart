import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mediahro/features/onboarding/first_run_actions.dart';
import 'package:mediahro/platform/platform_facades.dart';

import '../../helpers.dart';

final class _RecordingActions implements FirstRunActions {
  final calls = <String>[];

  @override
  Future<void> openFile(BuildContext context) async => calls.add('file');
  @override
  Future<void> openUrl(BuildContext context) async => calls.add('url');
  @override
  Future<void> addFolder(BuildContext context) async => calls.add('folder');
  @override
  Future<void> addServer(BuildContext context) async => calls.add('server');
  @override
  Future<void> openPrivacy(BuildContext context) async => calls.add('privacy');
}

void main() {
  testWidgets('CORE-002 the three actions reach the owning lanes', (
    tester,
  ) async {
    final actions = _RecordingActions();
    await pumpApp(
      tester,
      overrides: [firstRunActionsProvider.overrideWithValue(actions)],
    );
    await tester.tap(find.text('Open a file'));
    await tester.tap(find.text('Add a folder'));
    await tester.tap(find.text('Add a server'));
    await tester.pump();
    expect(actions.calls, ['file', 'folder', 'server']);
  });

  testWidgets('CORE-002 no permission or platform call happens on launch', (
    tester,
  ) async {
    var storageTouched = false;
    await pumpApp(
      tester,
      overrides: [
        storageProvider.overrideWith((ref) {
          storageTouched = true;
          throw const PlatformCapabilityUnavailable('storage');
        }),
      ],
    );
    expect(storageTouched, isFalse);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('CORE-002 default actions route to Sources with the add kind', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('Add a folder'));
    await tester.pumpAndSettle();
    final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      '/sources?add=folder',
    );
  });
}
