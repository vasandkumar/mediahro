import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/core/sources/source_repository.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_design/mediahro_design.dart';

T? _optional<T>(T Function() read) {
  try {
    return read();
  } on PlatformCapabilityUnavailable {
    return null;
  } on ProviderException catch (e) {
    if (e.exception is PlatformCapabilityUnavailable) return null;
    rethrow;
  }
}

/// What the app may read of the device's pictures (IMG-001, IMG-016):
/// granted, `limited` (Android 14+: only the photos the user selected),
/// denied, or not applicable where there is no such permission.
final FutureProvider<MediaPermission> photoAccessProvider =
    FutureProvider.autoDispose<MediaPermission>((ref) async {
      final storage = _optional(() => ref.watch(storageProvider));
      if (storage == null) return MediaPermission.notApplicable;
      try {
        return await storage.mediaPermission(PickKind.image);
      } on Object {
        return MediaPermission.notApplicable;
      }
    });

/// Scans a source again once the access it has changed; tests replace it.
final Provider<void Function(int sourceId)> deviceMediaRescanProvider =
    Provider<void Function(int sourceId)>(
      (ref) =>
          (id) => unawaited(ref.read(scanServiceProvider).scan(id)),
    );

/// The device-media source (the MediaStore), if the user added it.
SourceSummary? deviceMediaSource(List<SourceSummary> sources) {
  for (final s in sources) {
    if (s.source.rootUri.startsWith('mediastore:')) return s;
  }
  return null;
}

/// Above the Photos timeline when the device's pictures are only partly
/// visible: after "Select photos" (Android 14+) only those are shown, and
/// when access was refused none are. Offers to select more or allow all,
/// then looks again (IMG-016).
class PhotoAccessBanner extends ConsumerWidget {
  const PhotoAccessBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = deviceMediaSource(
      ref.watch(sourceSummariesProvider).value ?? const <SourceSummary>[],
    );
    final access = ref.watch(photoAccessProvider).value;
    if (source == null || access == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final (message, actions) = switch (access) {
      MediaPermission.denied => (
        l10n.photosAccessDenied,
        [
          KButton(
            label: l10n.photosAccessAllow,
            variant: KButtonVariant.primary,
            onPressed: () => unawaited(_allowAll(ref, source.source.id)),
          ),
        ],
      ),
      MediaPermission.limited => (
        l10n.photosAccessLimited,
        [
          KButton(
            label: l10n.photosAccessSelectMore,
            onPressed: () => unawaited(_selectMore(ref, source.source.id)),
          ),
          KButton(
            label: l10n.photosAccessAllowAll,
            variant: KButtonVariant.primary,
            onPressed: () => unawaited(_allowAll(ref, source.source.id)),
          ),
        ],
      ),
      _ => ('', const <Widget>[]),
    };
    if (actions.isEmpty) return const SizedBox.shrink();
    return Semantics(
      container: true,
      liveRegion: true,
      child: Material(
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(KSpacing.s12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              const SizedBox(height: KSpacing.s8),
              Wrap(spacing: KSpacing.s8, children: actions),
            ],
          ),
        ),
      ),
    );
  }

  /// The system asks again (all, or a new selection), then the device media
  /// are scanned for what is now visible.
  static Future<void> _allowAll(WidgetRef ref, int sourceId) async {
    final storage = _optional(() => ref.read(storageProvider));
    if (storage == null) return;
    try {
      await storage.requestMediaPermission(PickKind.image);
    } on Object {
      // The state below says what is still missing.
    }
    await _refresh(ref, sourceId);
  }

  static Future<void> _selectMore(WidgetRef ref, int sourceId) async {
    final library = _optional(() => ref.read(photoLibraryProvider));
    try {
      await library?.manageLimitedSelection();
    } on Object {
      // Falls back to the plain request below.
    }
    await _refresh(ref, sourceId);
  }

  static Future<void> _refresh(WidgetRef ref, int sourceId) async {
    ref.invalidate(photoAccessProvider);
    ref.read(deviceMediaRescanProvider)(sourceId);
  }
}
