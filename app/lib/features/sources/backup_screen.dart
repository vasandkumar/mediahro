import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/backup/backup_crypto.dart';
import 'package:mediahro/core/files/picked_files.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_design/mediahro_design.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// Backup and restore (CORE-014): one encrypted file with positions,
/// playlists, ratings, tags, settings; restores on any platform.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  bool _credentials = false;
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _pass.dispose();
    _pass2.dispose();
    super.dispose();
  }

  StorageFacade? get _storage {
    try {
      return ref.read(storageProvider);
    } on PlatformCapabilityUnavailable {
      return null;
    }
  }

  Future<void> _export() async {
    final l10n = AppLocalizations.of(context);
    if (_pass.text.length < 8) {
      return setState(() => _message = l10n.sourcesBackupPassShort);
    }
    if (_pass.text != _pass2.text) {
      return setState(() => _message = l10n.sourcesBackupPassMismatch);
    }
    final storage = _storage;
    if (storage == null) {
      return setState(() => _message = l10n.sourcesFolderPickerUnavailable);
    }
    setState(() => _busy = true);
    try {
      final bytes = await ref
          .read(backupServiceProvider)
          .export(_pass.text, includeCredentials: _credentials);
      final stamp = DateTime.now().toIso8601String().substring(0, 10);
      final name = 'mediahro-backup-$stamp.mhrobackup';
      // The system save dialog: works in SAF trees, sandboxes and pickers.
      final saved = await storage.saveFile(
        suggestedName: name,
        mimeType: 'application/octet-stream',
        content: Stream.value(bytes),
      );
      if (saved == null) return;
      setState(() => _message = l10n.sourcesBackupSaved(name));
    } on VirtualFileException {
      setState(() => _message = l10n.sourcesErrorIo);
    } on Exception {
      setState(() => _message = l10n.sourcesErrorIo);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final l10n = AppLocalizations.of(context);
    final storage = _storage;
    if (storage == null) {
      return setState(() => _message = l10n.sourcesFolderPickerUnavailable);
    }
    setState(() => _busy = true);
    try {
      final picked = await storage.pickFiles();
      if (picked.isEmpty) return;
      final bytes = await readPickedFile(
        storage,
        picked.first.uri,
        io: ref.read(fdIoProvider),
      );
      final r = await ref
          .read(backupServiceProvider)
          .restore(bytes, _pass.text);
      setState(
        () => _message = l10n.sourcesRestoreDone(
          r.matchedItems,
          r.playlists,
          r.unmatchedItems,
        ),
      );
    } on VirtualFileException {
      setState(() => _message = l10n.sourcesErrorIo);
    } on BackupDecryptError catch (e) {
      setState(
        () => _message = e.reason == 'wrongPassphrase'
            ? l10n.sourcesBackupWrongPass
            : l10n.sourcesBackupInvalid,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.sourcesBackup)),
      body: ListView(
        padding: const EdgeInsets.all(KSpacing.s16),
        children: [
          Text(l10n.sourcesBackupIntro),
          const SizedBox(height: KSpacing.s16),
          TextField(
            controller: _pass,
            obscureText: true,
            decoration: InputDecoration(labelText: l10n.sourcesBackupPass),
          ),
          TextField(
            controller: _pass2,
            obscureText: true,
            decoration: InputDecoration(
              labelText: l10n.sourcesBackupPassRepeat,
            ),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.sourcesBackupCredentials),
            subtitle: Text(l10n.sourcesBackupCredentialsHint),
            value: _credentials,
            onChanged: (v) => setState(() => _credentials = v ?? false),
          ),
          const SizedBox(height: KSpacing.s8),
          Wrap(
            spacing: KSpacing.s8,
            children: [
              FilledButton(
                onPressed: _busy ? null : _export,
                child: Text(l10n.sourcesBackupExport),
              ),
              OutlinedButton(
                onPressed: _busy ? null : _restore,
                child: Text(l10n.sourcesBackupRestore),
              ),
            ],
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: KSpacing.s16),
              child: LinearProgressIndicator(),
            ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: KSpacing.s16),
              child: Text(_message!),
            ),
        ],
      ),
    );
  }
}
