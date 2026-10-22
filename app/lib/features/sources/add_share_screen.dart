import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/core/sources/discovery/lan_discovery.dart';
import 'package:mediahro/core/sources/dlna/dlna_file_system.dart';
import 'package:mediahro/core/sources/dlna/upnp.dart';
import 'package:mediahro/core/sources/source_access.dart';
import 'package:mediahro/core/sources/source_repository.dart';
import 'package:mediahro/features/sources/errors.dart';
import 'package:mediahro_design/mediahro_design.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// Add a network share (SMB/NFS/WebDAV/FTP/SFTP) or a DLNA server: a
/// discovery list, then credentials, "Test connection", "Save"
/// (docs/06 §3.4; NET-001…005).
class AddShareScreen extends ConsumerStatefulWidget {
  const AddShareScreen({this.dlna = false, super.key});

  final bool dlna;

  @override
  ConsumerState<AddShareScreen> createState() => _AddShareScreenState();
}

class _AddShareScreenState extends ConsumerState<AddShareScreen> {
  final _form = GlobalKey<FormState>();
  final _host = TextEditingController();
  final _port = TextEditingController();
  final _path = TextEditingController();
  final _user = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  SourceKind _kind = SourceKind.smb;
  bool _guest = false;
  bool _tls = true;
  final _found = <DiscoveredShare>[];
  final _servers = <UpnpDevice>[];
  StreamSubscription<Object>? _discovery;
  bool _searching = true;
  String? _testResult;
  bool _testOk = false;
  bool _busy = false;

  /// Pins the user confirmed for this server (certificate or SSH host key).
  final Map<String, String> _trust = {};

  @override
  void initState() {
    super.initState();
    _discover();
  }

  void _discover() {
    setState(() => _searching = true);
    unawaited(_discovery?.cancel());
    if (widget.dlna) {
      _discovery = ref
          .read(mediaServerDiscoveryProvider)()
          .listen(
            (d) => setState(() => _servers.add(d)),
            onDone: () => mounted ? setState(() => _searching = false) : null,
            onError: (Object _) {},
          );
    } else {
      _discovery = ref
          .read(shareDiscoveryProvider)()
          .listen(
            (s) => setState(() => _found.add(s)),
            onDone: () => mounted ? setState(() => _searching = false) : null,
            onError: (Object _) {},
          );
    }
  }

  @override
  void dispose() {
    unawaited(_discovery?.cancel());
    for (final c in [_host, _port, _path, _user, _password, _name]) {
      c.dispose();
    }
    super.dispose();
  }

  void _pick(DiscoveredShare s) => setState(() {
    _trust.clear();
    _kind = s.kind;
    _host.text = s.host;
    _port.text = s.port?.toString() ?? '';
    _path.text = s.path ?? '';
    _name.text = s.name;
    _testResult = null;
  });

  Uri _root() {
    final port = int.tryParse(_port.text);
    final path = _path.text.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    final scheme = switch (_kind) {
      SourceKind.smb => 'smb',
      SourceKind.nfs => 'nfs',
      SourceKind.webdav => _tls ? 'davs' : 'dav',
      SourceKind.ftp => _tls ? 'ftpes' : 'ftp',
      SourceKind.sftp => 'sftp',
      _ => 'smb',
    };
    return Uri(
      scheme: scheme,
      host: _host.text.trim(),
      port: port,
      path: path.isEmpty ? '/' : '/$path/',
    );
  }

  NewSource _source() => NewSource(
    kind: _kind,
    name: _name.text.trim().isEmpty ? _host.text.trim() : _name.text.trim(),
    root: _root(),
    credential: _guest || _user.text.isEmpty
        ? (_guest ? const StoredCredential(kind: 'guest') : null)
        : StoredCredential(userName: _user.text, secret: _password.text),
    options: {
      if (_guest) 'guest': 'true',
      if (_kind == SourceKind.nfs)
        'export': '/${_path.text.trim().replaceAll(RegExp('^/+'), '')}',
      ..._trust,
    },
  );

  Future<void> _test() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    ref.read(networkPolicyProvider).allowForSession(_host.text.trim());
    try {
      final n = await ref.read(sourceRepositoryProvider).test(_source());
      setState(() {
        _testOk = true;
        _testResult = l10n.sourcesTestOk(n);
      });
    } on VirtualFileException catch (e) {
      setState(() {
        _testOk = false;
        _testResult = fileErrorMessage(l10n, e.error);
      });
      if (e.error == VirtualFileError.untrustedCertificate &&
          mounted &&
          await _confirmTrust(e.detail)) {
        if (mounted) setState(() => _busy = false);
        return await _test();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// docs/05 §9: a self-signed certificate or a new SSH host key is used
  /// only after the user compares and accepts its fingerprint.
  Future<bool> _confirmTrust(String? detail) async {
    final l10n = AppLocalizations.of(context);
    // The fingerprint comes from the platform (TlsSocketFacade, SftpFacade)
    // or the HTTP gateway; without one there is nothing to compare: refuse.
    if (detail == null || detail.isEmpty) return false;
    final hostKey = _kind == SourceKind.sftp ? detail : null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l10n.sourcesTrustTitle),
        content: SelectableText(
          hostKey != null
              ? l10n.sourcesTrustHostKey(hostKey)
              : l10n.sourcesTrustCertificate(detail),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: Text(l10n.sourcesCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: Text(l10n.sourcesTrust),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    setState(() {
      if (hostKey != null) {
        _trust['hostKeySha256'] = hostKey;
      } else {
        _trust['certSha256'] = detail;
      }
    });
    return true;
  }

  Future<void> _save() async {
    final nav = Navigator.of(context);
    final id = await ref.read(sourceRepositoryProvider).add(_source());
    await ref.read(networkPolicyProvider).refreshUserHosts();
    unawaited(ref.read(scanServiceProvider).scan(id));
    nav.pop();
  }

  Future<void> _addDlna(UpnpDevice d) async {
    final nav = Navigator.of(context);
    final cd = d.service(UpnpDevice.contentDirectory)!;
    final id = await ref
        .read(sourceRepositoryProvider)
        .add(
          NewSource(
            kind: SourceKind.dlna,
            name: d.friendlyName,
            root: dlnaRootUri(d.udn),
            options: {'controlUrl': cd.controlUrl.toString()},
          ),
        );
    await ref.read(networkPolicyProvider).refreshUserHosts();
    unawaited(ref.read(scanServiceProvider).scan(id));
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.dlna ? l10n.sourcesAddDlna : l10n.sourcesAddShare),
        actions: [
          IconButton(
            tooltip: l10n.sourcesSearchAgain,
            icon: const Icon(Icons.refresh),
            onPressed: _discover,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(KSpacing.s16),
        children: [
          Text(
            l10n.sourcesOnThisNetwork,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (_searching) const LinearProgressIndicator(),
          if (widget.dlna)
            for (final d in _servers)
              ListTile(
                leading: const Icon(Icons.cast_outlined),
                title: Text(d.friendlyName),
                subtitle: Text(d.location.host),
                onTap: () => _addDlna(d),
              )
          else
            for (final s in _found)
              ListTile(
                leading: const Icon(Icons.lan_outlined),
                title: Text(s.name),
                subtitle: Text(
                  l10n.sourcesDiscoveredVia(s.kind.name.toUpperCase(), s.host),
                ),
                onTap: () => _pick(s),
              ),
          if (!_searching && _found.isEmpty && _servers.isEmpty)
            Text(l10n.sourcesNothingFound),
          if (!widget.dlna) ...[
            const SizedBox(height: KSpacing.s24),
            Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<SourceKind>(
                    initialValue: _kind,
                    decoration: InputDecoration(
                      labelText: l10n.sourcesProtocol,
                    ),
                    items: [
                      for (final k in const [
                        SourceKind.smb,
                        SourceKind.nfs,
                        SourceKind.webdav,
                        SourceKind.ftp,
                        SourceKind.sftp,
                      ])
                        DropdownMenuItem(
                          value: k,
                          child: Text(l10n.sourcesProtocolName(k.name)),
                        ),
                    ],
                    onChanged: (k) => setState(() {
                      _kind = k ?? _kind;
                      _trust.clear();
                    }),
                  ),
                  TextFormField(
                    controller: _host,
                    decoration: InputDecoration(labelText: l10n.sourcesHost),
                    keyboardType: TextInputType.url,
                    onChanged: (_) => _trust.clear(),
                    validator: (v) => (v ?? '').trim().isEmpty
                        ? l10n.sourcesHostRequired
                        : null,
                  ),
                  TextFormField(
                    controller: _port,
                    decoration: InputDecoration(
                      labelText: l10n.sourcesPort,
                      helperText: l10n.sourcesPortHelp,
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  TextFormField(
                    controller: _path,
                    decoration: InputDecoration(
                      labelText: _kind == SourceKind.smb
                          ? l10n.sourcesShare
                          : l10n.sourcesPath,
                    ),
                  ),
                  if (_kind == SourceKind.webdav || _kind == SourceKind.ftp)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.sourcesUseTls),
                      value: _tls,
                      onChanged: (v) => setState(() {
                        _tls = v;
                        _trust.clear();
                      }),
                    ),
                  if (_kind == SourceKind.smb)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.sourcesGuest),
                      value: _guest,
                      onChanged: (v) => setState(() => _guest = v),
                    ),
                  if (!_guest) ...[
                    TextFormField(
                      controller: _user,
                      decoration: InputDecoration(labelText: l10n.sourcesUser),
                      autofillHints: const [AutofillHints.username],
                    ),
                    TextFormField(
                      controller: _password,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: l10n.sourcesPassword,
                      ),
                      autofillHints: const [AutofillHints.password],
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: KSpacing.s8,
                      ),
                      child: Text(
                        l10n.sourcesCredentialsNote,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                  TextFormField(
                    controller: _name,
                    decoration: InputDecoration(labelText: l10n.sourcesName),
                  ),
                  const SizedBox(height: KSpacing.s16),
                  if (_testResult != null)
                    Text(
                      _testResult!,
                      style: TextStyle(
                        color: _testOk
                            ? null
                            : Theme.of(context).colorScheme.error,
                      ),
                    ),
                  const SizedBox(height: KSpacing.s8),
                  Wrap(
                    spacing: KSpacing.s8,
                    children: [
                      OutlinedButton(
                        onPressed: _busy ? null : _test,
                        child: Text(l10n.sourcesTestConnection),
                      ),
                      FilledButton(
                        onPressed: _testOk && !_busy ? _save : null,
                        child: Text(l10n.sourcesSave),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
