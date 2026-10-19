import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/core/sources/url_open.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// Plays an opened URL (lane C1 overrides with the player route).
final openUrlActionProvider =
    Provider<void Function(BuildContext context, OpenableUrl url)?>(
      (ref) => null,
    );

/// "Open URL" (CORE-005, NET-006): paste or type any supported URL, with
/// optional headers and user agent; the last 50 are kept. No bundled lists.
Future<void> showOpenUrlDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const OpenUrlDialog());

class OpenUrlDialog extends ConsumerStatefulWidget {
  const OpenUrlDialog({super.key});

  @override
  ConsumerState<OpenUrlDialog> createState() => _OpenUrlDialogState();
}

class _OpenUrlDialogState extends ConsumerState<OpenUrlDialog> {
  final _url = TextEditingController();
  final _ua = TextEditingController();
  final _headers = TextEditingController();
  bool _advanced = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _ua.dispose();
    _headers.dispose();
    super.dispose();
  }

  Map<String, String> _parseHeaders() => {
    for (final line in _headers.text.split('\n'))
      if (line.contains(':'))
        line.substring(0, line.indexOf(':')).trim(): line
            .substring(line.indexOf(':') + 1)
            .trim(),
  };

  Future<void> _open([UrlHistoryRow? fromHistory]) async {
    final l10n = AppLocalizations.of(context);
    final OpenableUrl url;
    try {
      url = fromHistory != null
          ? UrlHistoryRepository.toOpenable(fromHistory)
          : parseUserUrl(
              _url.text,
              headers: _parseHeaders(),
              userAgent: _ua.text,
            );
    } on UrlRejected catch (e) {
      setState(() => _error = l10n.sourcesUrlRejected(e.reason.name));
      return;
    }
    ref.read(networkPolicyProvider).allowForSession(url.uri.host);
    await ref.read(urlHistoryProvider).record(url);
    if (!mounted) return;
    final open = ref.read(openUrlActionProvider);
    Navigator.of(context).pop();
    if (open != null && mounted) open(context, url);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final history = ref.watch(urlHistoryProvider);
    return AlertDialog(
      title: Text(l10n.sourcesOpenUrl),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _url,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: l10n.sourcesUrl,
                hintText: l10n.sourcesUrlHint,
                errorText: _error,
              ),
              onSubmitted: (_) => _open(),
            ),
            TextButton(
              onPressed: () => setState(() => _advanced = !_advanced),
              child: Text(l10n.sourcesUrlAdvanced),
            ),
            if (_advanced) ...[
              TextField(
                controller: _ua,
                decoration: InputDecoration(labelText: l10n.sourcesUserAgent),
              ),
              TextField(
                controller: _headers,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: l10n.sourcesHeaders,
                  helperText: l10n.sourcesHeadersHelp,
                ),
              ),
            ],
            const SizedBox(height: KSpacing.s8),
            Flexible(
              child: StreamBuilder<List<UrlHistoryRow>>(
                stream: history.watch(),
                builder: (context, snap) {
                  final rows = snap.data ?? const <UrlHistoryRow>[];
                  if (rows.isEmpty) return const SizedBox.shrink();
                  return ListView(
                    shrinkWrap: true,
                    children: [
                      Text(
                        l10n.sourcesUrlHistory,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      for (final r in rows)
                        ListTile(
                          dense: true,
                          title: Text(
                            r.url,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _open(r),
                          trailing: IconButton(
                            tooltip: l10n.sourcesUrlForget,
                            icon: const Icon(Icons.close),
                            onPressed: () => history.remove(r.id),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.sourcesCancel),
        ),
        FilledButton(onPressed: _open, child: Text(l10n.sourcesOpen)),
      ],
    );
  }
}
