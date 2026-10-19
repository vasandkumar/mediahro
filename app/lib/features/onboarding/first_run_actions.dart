import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mediahro/app/router.dart';

/// The first-run and empty-library actions (CORE-002, docs/06 §3.7). No
/// permission is requested before one of these is chosen: each hands off
/// to the lane that owns the flow, which asks for access in context.
abstract interface class FirstRunActions {
  Future<void> openFile(BuildContext context);
  Future<void> openUrl(BuildContext context);
  Future<void> addFolder(BuildContext context);
  Future<void> addServer(BuildContext context);
  Future<void> openPrivacy(BuildContext context);
}

/// Default: navigate to the owning lanes' routes. B2 reads
/// `/sources?add=folder|server`; C1 reads `/video?open=file|url`. Lanes may
/// instead override [firstRunActionsProvider] with direct calls.
final class RouteFirstRunActions implements FirstRunActions {
  const RouteFirstRunActions();

  @override
  Future<void> openFile(BuildContext context) async =>
      context.go(AppRoutes.openFile);

  @override
  Future<void> openUrl(BuildContext context) async =>
      context.go(AppRoutes.openUrl);

  @override
  Future<void> addFolder(BuildContext context) async =>
      context.go(AppRoutes.addFolder);

  @override
  Future<void> addServer(BuildContext context) async =>
      context.go(AppRoutes.addServer);

  @override
  Future<void> openPrivacy(BuildContext context) async =>
      context.go(AppRoutes.settingsPrivacy);
}

final firstRunActionsProvider = Provider<FirstRunActions>(
  (ref) => const RouteFirstRunActions(),
);
