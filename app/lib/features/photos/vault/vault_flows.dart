import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/features/photos/vault/vault_gate.dart';
import 'package:mediahro/features/photos/vault/vault_mover.dart';
import 'package:mediahro/features/photos/vault/vault_providers.dart';

/// The lock screen as a route of its own, for moving photos in from outside
/// the vault: pops with true once the vault is open.
class _GateScreen extends ConsumerStatefulWidget {
  const _GateScreen();

  @override
  ConsumerState<_GateScreen> createState() => _GateScreenState();
}

class _GateScreenState extends ConsumerState<_GateScreen> {
  late final SecureWindowScope _secure;

  @override
  void initState() {
    super.initState();
    _secure = ref.read(secureWindowScopeProvider)..enter();
  }

  @override
  void dispose() {
    _secure.leave();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.photosVault),
        leading: IconButton(
          tooltip: l10n.photosPickLocationClose,
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context, false),
        ),
      ),
      body: VaultGate(onOpened: () => Navigator.pop(context, true)),
    );
  }
}

/// Asks, then moves [photos] into the vault (IMG-011): the PIN pad first
/// (the vault the PIN opens takes them, whichever it is; no other prompt),
/// then the question, then the move with its progress. A vault that was
/// locked is locked again afterwards. Returns true when something moved.
Future<bool> moveToVaultFlow(
  BuildContext context,
  WidgetRef ref,
  List<PhotoEntry> photos,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final container = ProviderScope.containerOf(context);
  final images = photos.where((p) => !p.isVideo).toList();
  if (images.isEmpty) {
    messenger?.showSnackBar(SnackBar(content: Text(l10n.photosVaultNoVideos)));
    return false;
  }
  try {
    await container.read(vaultManagerProvider.future);
  } on Object {
    messenger?.showSnackBar(
      SnackBar(content: Text(l10n.photosVaultUnavailable)),
    );
    return false;
  }
  final session = container.read(vaultSessionProvider.notifier);
  final wasOpen = container.read(vaultSessionProvider).isOpen;
  if (!wasOpen) {
    if (!context.mounted) return false;
    final opened = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const _GateScreen(),
      ),
    );
    if (opened != true) {
      session.lock();
      return false;
    }
  }
  final vault = container.read(vaultSessionProvider).vault;
  if (vault == null || !context.mounted) {
    if (!wasOpen) session.lock();
    return false;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.photosVaultMoveTitle(images.length)),
      content: Text(l10n.photosVaultMoveBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.photosCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.photosVaultMoveConfirm),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) {
    if (!wasOpen) session.lock();
    return false;
  }
  final done = ValueNotifier<int>(0);
  final navigator = Navigator.of(context, rootNavigator: true);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: ValueListenableBuilder<int>(
            valueListenable: done,
            builder: (ctx, n, _) => Semantics(
              liveRegion: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.photosVaultMoving(n, images.length)),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: n / images.length),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  final VaultMoveReport report;
  try {
    report = await container
        .read(vaultMoverProvider)
        .moveIn(vault.container, images, onProgress: (n) => done.value = n);
  } finally {
    navigator.pop();
    done.dispose();
    if (!wasOpen) session.lock();
  }
  messenger?.showSnackBar(
    SnackBar(
      content: Text(
        [
          if (report.moved > 0) l10n.photosVaultMoved(report.moved),
          if (report.failed.isNotEmpty)
            l10n.photosVaultMoveFailed(report.failed.length),
          if (report.leftInLibrary.isNotEmpty)
            l10n.photosVaultMoveCleanup(report.leftInLibrary.length),
        ].join(' '),
      ),
    ),
  );
  return report.moved > 0;
}
