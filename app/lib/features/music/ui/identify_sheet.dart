import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/net/network_policy.dart';
import 'package:mediahro/features/music/fingerprint/acoustid_client.dart';
import 'package:mediahro/features/music/library/music_library.dart';
import 'package:mediahro/features/music/music_providers.dart';
import 'package:mediahro/features/settings/core_settings.dart';
import 'package:mediahro/features/settings/settings_providers.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// "Identify song" (MUS-010): fingerprints the song on the device, asks
/// AcoustID once, and lists what it knows; the user picks the match to write
/// into the file's tags. Opt-in: the AcoustID endpoint is off until the user
/// allows it here (PRIV-004).
Future<void> showIdentifySheet(BuildContext context, MusicTrack track) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => IdentifySheet(track: track),
    );

class IdentifySheet extends ConsumerStatefulWidget {
  const IdentifySheet({required this.track, super.key});

  final MusicTrack track;

  @override
  ConsumerState<IdentifySheet> createState() => _IdentifySheetState();
}

enum _Phase {
  consent,
  unavailable,
  listening,
  lookingUp,
  results,
  none,
  error,
  writing,
}

class _IdentifySheetState extends ConsumerState<IdentifySheet> {
  _Phase _phase = _Phase.consent;
  List<SongMatch> _matches = const [];

  @override
  void initState() {
    super.initState();
    final identifier = ref.read(trackIdentifierProvider);
    if (!identifier.available) {
      _phase = _Phase.unavailable;
    } else if (_enabled) {
      unawaited(Future.microtask(_identify));
    }
  }

  bool get _enabled => ref
      .read(settingsStoreProvider)
      .get(CoreSettings.endpoint(Endpoints.acoustId.id));

  Future<void> _allow() async {
    ref
        .read(settingsStoreProvider)
        .set(CoreSettings.endpoint(Endpoints.acoustId.id), true);
    await _identify();
  }

  Future<void> _identify() async {
    setState(() => _phase = _Phase.listening);
    try {
      final found = await ref
          .read(trackIdentifierProvider)
          .identify(
            widget.track,
            onFingerprinted: () {
              if (mounted) setState(() => _phase = _Phase.lookingUp);
            },
          );
      if (!mounted) return;
      setState(() {
        _matches = found;
        _phase = found.isEmpty ? _Phase.none : _Phase.results;
      });
    } on NetworkBlocked {
      if (mounted) setState(() => _phase = _Phase.consent);
    } on Exception {
      if (mounted) setState(() => _phase = _Phase.error);
    }
  }

  Future<void> _apply(SongMatch m) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final nav = Navigator.of(context);
    setState(() => _phase = _Phase.writing);
    final res = await ref.read(trackIdentifierProvider).apply(widget.track, m);
    if (!mounted) return;
    if (res.changed == 1) {
      nav.pop();
      messenger?.showSnackBar(
        SnackBar(content: Text(l10n.musicIdentifyApplied)),
      );
    } else {
      messenger?.showSnackBar(
        SnackBar(content: Text(l10n.musicIdentifyNotWritten)),
      );
      setState(() => _phase = _Phase.results);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    Widget busy(String text) => Padding(
      padding: const EdgeInsets.all(KSpacing.s24),
      child: Row(
        children: [
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: KSpacing.s16),
          Expanded(child: Text(text)),
        ],
      ),
    );
    Widget message(String text, {List<Widget> actions = const []}) => Padding(
      padding: const EdgeInsets.all(KSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: KSpacing.s16),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
          ],
        ],
      ),
    );
    final body = switch (_phase) {
      _Phase.consent => message(
        l10n.musicIdentifyConsent,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.musicCancel),
          ),
          const SizedBox(width: KSpacing.s8),
          FilledButton(
            onPressed: () => unawaited(_allow()),
            child: Text(l10n.musicIdentifyAllow),
          ),
        ],
      ),
      _Phase.unavailable => message(l10n.musicIdentifyUnavailable),
      _Phase.listening => busy(l10n.musicIdentifyListening),
      _Phase.lookingUp => busy(l10n.musicIdentifyLookingUp),
      _Phase.writing => busy(l10n.musicIdentifyWriting),
      _Phase.none => message(l10n.musicIdentifyNone),
      _Phase.error => message(
        l10n.musicIdentifyError,
        actions: [
          FilledButton(
            onPressed: () => unawaited(_identify()),
            child: Text(l10n.musicIdentifyRetry),
          ),
        ],
      ),
      _Phase.results => Flexible(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final m in _matches)
              ListTile(
                minVerticalPadding: KSpacing.s8,
                title: Text(m.title),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (m.artist != null) Text(m.artist!),
                    if (m.album != null && m.year != null)
                      Text(l10n.musicIdentifyAlbumYear(m.album!, '${m.year}'))
                    else if (m.album != null)
                      Text(m.album!),
                    Text(l10n.musicIdentifyScore((m.score * 100).round())),
                  ],
                ),
                onTap: () => unawaited(_apply(m)),
              ),
          ],
        ),
      ),
    };
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: KSpacing.s16),
            child: Text(l10n.musicIdentify, style: theme.textTheme.titleLarge),
          ),
          if (_phase == _Phase.results)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                KSpacing.s16,
                KSpacing.s4,
                KSpacing.s16,
                KSpacing.s8,
              ),
              child: Text(l10n.musicIdentifyPick(widget.track.title)),
            ),
          body,
        ],
      ),
    );
  }
}
