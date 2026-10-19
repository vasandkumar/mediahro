import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/settings/settings_providers.dart';
import 'package:mediahro/features/settings/settings_store.dart';
import 'package:mediahro_design/mediahro_design.dart';
import 'package:path_provider/path_provider.dart';

/// Writes an exported settings file and returns where it went. The default
/// saves to the app's documents folder (visible in Files on iOS, the
/// Documents folder on desktop); lane C4 can override it with a save
/// dialog once `StorageFacade` offers one.
typedef SettingsFileSaver = Future<String> Function(String json);

final settingsFileSaverProvider = Provider<SettingsFileSaver>(
  (ref) => (json) async {
    final dir = await getApplicationDocumentsDirectory();
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    final file = File(
      '${dir.path}${Platform.pathSeparator}mediahro-settings-$stamp.json',
    );
    await file.writeAsString(json, flush: true);
    return file.path;
  },
);

enum _Menu { export, import, resetAll }

/// Overflow menu on the settings screen: export, import, reset all
/// (CORE-006).
class SettingsTransferMenu extends ConsumerWidget {
  const SettingsTransferMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return PopupMenuButton<_Menu>(
      tooltip: l10n.settingsMoreActions,
      onSelected: (m) => switch (m) {
        _Menu.export => _export(context, ref),
        _Menu.import => _import(context, ref),
        _Menu.resetAll => _resetAll(context, ref),
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: _Menu.export, child: Text(l10n.settingsExport)),
        PopupMenuItem(value: _Menu.import, child: Text(l10n.settingsImport)),
        PopupMenuItem(
          value: _Menu.resetAll,
          child: Text(l10n.settingsResetAll),
        ),
      ],
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final json = ref.read(settingsStoreProvider).exportJson();
    final messenger = ScaffoldMessenger.maybeOf(context);
    return KSheet.show<void>(
      context,
      title: l10n.settingsExport,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.all(KSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.settingsExportDescription),
            const SizedBox(height: KSpacing.s12),
            Wrap(
              spacing: KSpacing.s8,
              runSpacing: KSpacing.s8,
              children: [
                KButton(
                  label: l10n.settingsExportSave,
                  icon: KIcon.exportFile,
                  variant: KButtonVariant.primary,
                  onPressed: () async {
                    final path = await ref.read(settingsFileSaverProvider)(
                      json,
                    );
                    messenger?.showSnackBar(
                      SnackBar(content: Text(l10n.settingsExportSaved(path))),
                    );
                  },
                ),
                KButton(
                  label: l10n.settingsExportCopy,
                  icon: KIcon.copy,
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: json));
                    messenger?.showSnackBar(
                      SnackBar(content: Text(l10n.settingsExportCopied)),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: KSpacing.s12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: SingleChildScrollView(
                child: SelectableText(
                  json,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final json = await showDialog<String>(
      context: context,
      builder: (_) => const _ImportDialog(),
    );
    if (json == null || json.trim().isEmpty) return;
    final store = ref.read(settingsStoreProvider);
    try {
      final r = store.importJson(
        json,
        known: ref.read(settingsRegistryProvider).keys,
      );
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            l10n.settingsImportDone(
              r.imported,
              r.skippedManaged + r.skippedInvalid,
            ),
          ),
        ),
      );
    } on SettingsImportException catch (e) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(switch (e.reason) {
            SettingsImportError.notJson ||
            SettingsImportError.notSettings => l10n.settingsImportNotSettings,
            SettingsImportError.newerSchema => l10n.settingsImportNewer,
          }),
        ),
      );
    }
  }

  Future<void> _resetAll(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l10n.settingsResetAllTitle),
        content: Text(l10n.settingsResetAllBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(l10n.settingsCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(l10n.settingsReset),
          ),
        ],
      ),
    );
    if (ok ?? false) ref.read(settingsStoreProvider).resetAll();
  }
}

class _ImportDialog extends StatefulWidget {
  const _ImportDialog();

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.settingsImport),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.settingsImportDescription),
            const SizedBox(height: KSpacing.s12),
            TextField(
              controller: _text,
              minLines: 4,
              maxLines: 10,
              decoration: InputDecoration(
                labelText: l10n.settingsImportField,
                border: const OutlineInputBorder(),
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: KButton(
                label: l10n.settingsImportPaste,
                variant: KButtonVariant.tertiary,
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  if (data?.text != null) _text.text = data!.text!;
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.settingsCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _text.text),
          child: Text(l10n.settingsImport),
        ),
      ],
    );
  }
}
