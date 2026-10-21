import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/net/network_policy.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/features/music/music_providers.dart';
import 'package:mediahro/features/music/scrobble/scrobble_services.dart';
import 'package:mediahro/features/settings/core_settings.dart';
import 'package:mediahro/features/settings/settings_providers.dart';
import 'package:mediahro_design/mediahro_design.dart';

Future<void> openScrobbleSettings(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => const ScrobbleSettingsScreen()));

/// Scrobbling accounts and options (MUS-009). Each service is off until the
/// user connects it; connecting turns on its PRIV-004 endpoint after the
/// user has read what is sent.
class ScrobbleSettingsScreen extends ConsumerStatefulWidget {
  const ScrobbleSettingsScreen({super.key});

  @override
  ConsumerState<ScrobbleSettingsScreen> createState() =>
      _ScrobbleSettingsScreenState();
}

final class _View {
  const _View({
    required this.connected,
    required this.enabled,
    required this.pending,
    required this.excluded,
    required this.sources,
  });

  final Set<String> connected;
  final Set<String> enabled;
  final Map<String, int> pending;
  final Set<int> excluded;
  final List<SourceRow> sources;
}

NetworkEndpoint? _endpoint(String id) => switch (id) {
  'listenbrainz' => Endpoints.listenBrainz,
  _ => null,
};

class _ScrobbleSettingsScreenState
    extends ConsumerState<ScrobbleSettingsScreen> {
  _View? _view;
  final Map<String, String> _names = {};
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final scrobbler = ref.read(scrobblerProvider);
    final db = ref.read(libraryDatabaseProvider);
    final connected = <String>{
      for (final s in scrobbler.services)
        if (await s.connected()) s.id,
    };
    final view = _View(
      connected: connected,
      enabled: await scrobbler.enabledServices(),
      pending: await scrobbler.pending(),
      excluded: await scrobbler.excludedSources(),
      sources: await db.select(db.sources).get(),
    );
    if (mounted) setState(() => _view = view);
  }

  String _title(AppLocalizations l10n, String id) =>
      l10n.musicScrobbleListenBrainz;

  /// Shows what is sent and turns the endpoint on; false when declined.
  Future<bool> _consent(ScrobbleService svc) async {
    final endpoint = _endpoint(svc.id);
    if (endpoint == null) return false;
    final store = ref.read(settingsStoreProvider);
    final key = CoreSettings.endpoint(endpoint.id);
    if (store.get(key)) return true;
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(l10n.musicScrobbleConnectTo(_title(l10n, svc.id))),
        content: Text(l10n.musicScrobbleConsent(endpoint.hosts.first)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: Text(l10n.musicCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(d).pop(true),
            child: Text(l10n.musicScrobbleConnect),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    store.set(key, true);
    return true;
  }

  Future<void> _connect(ScrobbleService svc) async {
    if (!await _consent(svc) || !mounted) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _SignInDialog(
        service: svc,
        title: l10n.musicScrobbleConnectTo(_title(l10n, svc.id)),
        onError: (e) => e is ScrobbleError
            ? l10n.musicScrobbleSignInFailed
            : l10n.musicScrobbleOffline,
      ),
    );
    if (name == null) return;
    _names[svc.id] = name;
    await ref.read(scrobblerProvider).setEnabled(svc.id, enabled: true);
    messenger?.showSnackBar(
      SnackBar(content: Text(l10n.musicScrobbleConnectedAs(name))),
    );
    await _load();
  }

  Future<void> _disconnect(ScrobbleService svc) async {
    await svc.signOut();
    await ref.read(scrobblerProvider).setEnabled(svc.id, enabled: false);
    final endpoint = _endpoint(svc.id);
    if (endpoint != null) {
      ref
          .read(settingsStoreProvider)
          .set(CoreSettings.endpoint(endpoint.id), false);
    }
    _names.remove(svc.id);
    await _load();
  }

  Future<void> _toggle(ScrobbleService svc, {required bool on}) async {
    if (on && !await _consent(svc)) return;
    await ref.read(scrobblerProvider).setEnabled(svc.id, enabled: on);
    await _load();
  }

  Future<void> _sendNow() async {
    setState(() => _sending = true);
    await ref.read(scrobblerProvider).flush();
    if (!mounted) return;
    setState(() => _sending = false);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final services = ref.watch(scrobblerProvider).services;
    final v = _view;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.musicScrobbling)),
      body: v == null
          ? const KSkeletonRows()
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(KSpacing.s16),
                  child: Text(
                    services.isEmpty
                        ? l10n.musicScrobbleUnavailable
                        : l10n.musicScrobbleIntro,
                  ),
                ),
                for (final svc in services) ...[
                  ListTile(
                    title: Text(
                      _title(l10n, svc.id),
                      style: theme.textTheme.titleMedium,
                    ),
                    subtitle: Text(
                      !v.connected.contains(svc.id)
                          ? l10n.musicScrobbleNotConnected
                          : _names[svc.id] != null
                          ? l10n.musicScrobbleConnectedAs(_names[svc.id]!)
                          : l10n.musicScrobbleConnected,
                    ),
                    trailing: v.connected.contains(svc.id)
                        ? TextButton(
                            onPressed: () => unawaited(_disconnect(svc)),
                            child: Text(l10n.musicScrobbleDisconnect),
                          )
                        : FilledButton(
                            onPressed: () => unawaited(_connect(svc)),
                            child: Text(l10n.musicScrobbleConnect),
                          ),
                  ),
                  if (v.connected.contains(svc.id)) ...[
                    SwitchListTile(
                      title: Text(l10n.musicScrobbleSend),
                      subtitle: v.enabled.contains(svc.id)
                          ? Text(
                              l10n.musicScrobblePending(v.pending[svc.id] ?? 0),
                            )
                          : (v.pending[svc.id] ?? 0) > 0
                          ? Text(l10n.musicScrobbleSignInAgain)
                          : null,
                      value: v.enabled.contains(svc.id),
                      onChanged: (on) => unawaited(_toggle(svc, on: on)),
                    ),
                  ],
                  const Divider(),
                ],
                if (v.pending.values.any((n) => n > 0))
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: KSpacing.s16,
                    ),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: OutlinedButton(
                        onPressed: _sending
                            ? null
                            : () => unawaited(_sendNow()),
                        child: Text(l10n.musicScrobbleSendNow),
                      ),
                    ),
                  ),
                if (services.isNotEmpty && v.sources.isNotEmpty) ...[
                  ListTile(
                    title: Text(
                      l10n.musicScrobbleExclude,
                      style: theme.textTheme.titleSmall,
                    ),
                    subtitle: Text(l10n.musicScrobbleExcludeHint),
                  ),
                  for (final src in v.sources)
                    SwitchListTile(
                      title: Text(src.name),
                      value: !v.excluded.contains(src.id),
                      onChanged: (on) async {
                        await ref
                            .read(scrobblerProvider)
                            .setSourceExcluded(src.id, excluded: !on);
                        await _load();
                      },
                    ),
                ],
              ],
            ),
    );
  }
}

class _SignInDialog extends StatefulWidget {
  const _SignInDialog({
    required this.service,
    required this.title,
    required this.onError,
  });

  final ScrobbleService service;
  final String title;
  final String Function(Object error) onError;

  @override
  State<_SignInDialog> createState() => _SignInDialogState();
}

class _SignInDialogState extends State<_SignInDialog> {
  final _secret = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _secret.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final svc = widget.service;
      final name = switch (svc) {
        ListenBrainzService() => await svc.signIn(_secret.text),
        _ => throw StateError('unknown service'),
      };
      if (mounted) Navigator.of(context).pop(name);
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = widget.onError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _secret,
        autofocus: true,
        obscureText: true,
        decoration: InputDecoration(
          labelText: l10n.musicScrobbleToken,
          helperText: l10n.musicScrobbleTokenHint,
          helperMaxLines: 3,
          errorText: _error,
          errorMaxLines: 3,
        ),
        onSubmitted: (_) => unawaited(_submit()),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.musicCancel),
        ),
        FilledButton(
          onPressed: _busy ? null : () => unawaited(_submit()),
          child: Text(l10n.musicScrobbleConnect),
        ),
      ],
    );
  }
}
