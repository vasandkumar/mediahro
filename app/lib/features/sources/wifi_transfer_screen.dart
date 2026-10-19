import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/files/wifi_transfer.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro_design/mediahro_design.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// Wi-Fi transfer (FILE-005): off until started; shows the address and a QR
/// code; files land in the app's "Transfers" folder (a local source).
class WifiTransferScreen extends ConsumerStatefulWidget {
  const WifiTransferScreen({super.key});

  @override
  ConsumerState<WifiTransferScreen> createState() => _WifiTransferScreenState();
}

class _WifiTransferScreenState extends ConsumerState<WifiTransferScreen> {
  WifiTransferServer? _server;
  Uri? _url;
  final _received = <String>[];
  StreamSubscription<String>? _sub;

  Future<void> _toggle(bool on) async {
    final l10n = AppLocalizations.of(context);
    if (!on) {
      await _sub?.cancel();
      await _server?.dispose();
      setState(() {
        _server = null;
        _url = null;
      });
      return;
    }
    final dir = Directory(
      '${ref.read(appDataDirectoryProvider).path}${Platform.pathSeparator}Transfers',
    );
    await dir.create(recursive: true);
    final s = WifiTransferServer(
      fileSystem: const LocalFileSystem(),
      folder: dir.uri,
      strings: TransferPageStrings(
        title: l10n.sourcesTransferPageTitle,
        upload: l10n.sourcesTransferUpload,
        download: l10n.sourcesTransferFiles,
        empty: l10n.sourcesTransferEmpty,
        uploaded: l10n.sourcesTransferUploaded,
      ),
    );
    final url = await s.start();
    _sub = s.uploads.listen((n) => setState(() => _received.add(n)));
    setState(() {
      _server = s;
      _url = url;
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    unawaited(_server?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final url = _url;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.sourcesWifiTransfer)),
      body: ListView(
        padding: const EdgeInsets.all(KSpacing.s16),
        children: [
          SwitchListTile(
            title: Text(l10n.sourcesTransferOn),
            subtitle: Text(l10n.sourcesTransferHint),
            value: _server != null,
            onChanged: _toggle,
          ),
          if (url != null) ...[
            const SizedBox(height: KSpacing.s16),
            SelectableText(
              url.toString(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: KSpacing.s16),
            Center(
              child: Semantics(
                label: l10n.sourcesTransferQr,
                child: CustomPaint(
                  size: const Size.square(220),
                  painter: _QrPainter(
                    qrModules(url.toString()),
                    Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ),
            const SizedBox(height: KSpacing.s16),
            Text(
              l10n.sourcesTransferPrivacy,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            for (final n in _received)
              ListTile(
                leading: const Icon(Icons.download_done),
                title: Text(n),
              ),
          ],
        ],
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.modules, this.color);

  final List<List<bool>> modules;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final n = modules.length + 8; // 4-module quiet zone
    final cell = size.width / n;
    final paint = Paint()..color = color;
    for (var r = 0; r < modules.length; r++) {
      for (var c = 0; c < modules.length; c++) {
        if (modules[r][c]) {
          canvas.drawRect(
            Rect.fromLTWH((c + 4) * cell, (r + 4) * cell, cell, cell),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) =>
      old.modules != modules || old.color != color;
}
