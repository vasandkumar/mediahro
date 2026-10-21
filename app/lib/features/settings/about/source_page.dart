import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mediahro/app/capabilities.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/settings/about/native_notices.dart';

/// The source offer the LGPL asks for (docs/09 §2, CORE-013): where the
/// complete source of every library in this build is, the exact build options
/// of FFmpeg, mpv and libplacebo, the patches applied, and which libraries
/// are LGPL. Addresses are shown to copy; nothing is opened or fetched.
class SourcePage extends StatelessWidget {
  const SourcePage({required this.notices, required this.platform, super.key});

  final NativeNotices notices;
  final AppPlatform platform;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final shipped = notices.forPlatform(platform);
    final withLine = [
      for (final c in shipped)
        if (c.configure != null) c,
    ];
    final lgpl = [
      for (final c in shipped)
        if (c.isLgpl) c,
    ];
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsAboutSourceTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l10n.settingsAboutSourceOffer(notices.release),
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          _Address(l10n.settingsAboutSourceRelease, notices.releaseUrl),
          if (notices.sourcesUrl != null)
            _Address(l10n.settingsAboutSourceArchive, notices.sourcesUrl!),
          if (notices.sourcesSha256 != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SelectableText(
                l10n.settingsAboutChecksum(notices.sourcesSha256!),
                style: theme.textTheme.bodySmall,
              ),
            ),
          for (final c in withLine) _BuildLine(c),
          const SizedBox(height: 8),
          Semantics(
            header: true,
            child: Text(
              l10n.settingsAboutLgplHeading,
              style: theme.textTheme.titleSmall,
            ),
          ),
          const SizedBox(height: 4),
          for (final c in lgpl)
            ListTile(
              key: ValueKey('lgpl.${c.name}'),
              dense: true,
              title: Text(l10n.settingsAboutLibraryLine(c.name, c.version)),
              subtitle: Text(c.license),
            ),
        ],
      ),
    );
  }
}

class _Address extends StatelessWidget {
  const _Address(this.label, this.url);

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: SelectableText(url),
      trailing: IconButton(
        tooltip: l10n.settingsAboutCopy,
        icon: const Icon(Icons.copy),
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: url));
          if (!context.mounted) return;
          ScaffoldMessenger.maybeOf(context)
              ?.showSnackBar(SnackBar(content: Text(l10n.settingsAboutCopied)));
        },
      ),
    );
  }
}

/// The exact configure line of one library, with the patches applied to it.
class _BuildLine extends StatelessWidget {
  const _BuildLine(this.component);

  final NativeComponent component;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final line = component.configure!.join(' ');
    return Padding(
      key: ValueKey('build.${component.name}'),
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    l10n.settingsAboutConfigureHeading(
                      l10n.settingsAboutLibraryLine(
                        component.name,
                        component.version,
                      ),
                    ),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ),
              IconButton(
                tooltip: l10n.settingsAboutCopyBuildLine,
                icon: const Icon(Icons.copy),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: line));
                  if (!context.mounted) return;
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    SnackBar(content: Text(l10n.settingsAboutBuildLineCopied)),
                  );
                },
              ),
            ],
          ),
          SelectableText(
            line,
            style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
          if (component.patches.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SelectableText(
                l10n.settingsAboutPatches(component.patches.join(', ')),
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}
