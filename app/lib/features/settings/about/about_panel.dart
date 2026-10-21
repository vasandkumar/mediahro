import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/capabilities.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/app/providers.dart';
import 'package:mediahro/features/settings/about/about_info.dart';
import 'package:mediahro/features/settings/about/native_notices.dart';
import 'package:mediahro/features/settings/about/source_page.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// About (CORE-013): the version and build, the playback libraries, the
/// open-source licences, the source offer the LGPL asks for, and the
/// published policies. Reads only what is bundled in the app; it makes no
/// network connection, and links are shown to copy, never opened.
class AboutPanel extends ConsumerWidget {
  const AboutPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final caps = ref.watch(capabilitiesProvider);
    final notices = ref.watch(nativeNoticesProvider).value;
    final engine = notices?.component('mpv');
    final codecs = notices?.component('ffmpeg');

    final flavour = switch (caps.flavor) {
      Flavor.store => l10n.settingsAboutFlavourStore,
      Flavor.direct => l10n.settingsAboutFlavourDirect,
      Flavor.foss => l10n.settingsAboutFlavourFoss,
      Flavor.enterprise => l10n.settingsAboutFlavourEnterprise,
    };
    final platform = switch (caps.platform) {
      AppPlatform.android => l10n.settingsAboutPlatformAndroid,
      AppPlatform.ios => l10n.settingsAboutPlatformIos,
      AppPlatform.macos => l10n.settingsAboutPlatformMacos,
      AppPlatform.windows => l10n.settingsAboutPlatformWindows,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  AboutInfo.appName,
                  style: theme.textTheme.headlineSmall,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.settingsAboutVersion(AboutInfo.version, AboutInfo.build),
                style: theme.textTheme.bodyLarge,
              ),
              Text(
                l10n.settingsAboutBuild(flavour, platform),
                style: theme.textTheme.bodyMedium,
              ),
              if (AboutInfo.unofficial) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.settingsAboutUnofficial,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (engine != null || codecs != null) ...[
          _Heading(l10n.settingsAboutEngineHeading),
          if (engine != null)
            KSettingsRow.value(
              title: l10n.settingsAboutEngineVideo,
              description: l10n.settingsAboutEngineVideoDescription,
              valueLabel: l10n.settingsAboutLibraryLine(
                engine.name,
                engine.version,
              ),
              onTap: null,
            ),
          if (codecs != null)
            KSettingsRow.value(
              title: l10n.settingsAboutEngineCodecs,
              description: l10n.settingsAboutEngineCodecsDescription,
              valueLabel: l10n.settingsAboutLibraryLine(
                'FFmpeg',
                codecs.version,
              ),
              onTap: null,
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              l10n.settingsAboutOsDecoders,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
        KSettingsRow.navigation(
          title: l10n.settingsAboutLicences,
          description: l10n.settingsAboutLicencesDescription,
          onTap: () => _showLicences(context, notices, caps.platform),
        ),
        if (notices != null)
          KSettingsRow.navigation(
            title: l10n.settingsAboutSource,
            description: l10n.settingsAboutSourceDescription,
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) =>
                    SourcePage(notices: notices, platform: caps.platform),
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              l10n.settingsAboutNoDetails,
              style: theme.textTheme.bodySmall,
            ),
          ),
        _Heading(l10n.settingsAboutPoliciesHeading),
        _LinkRow(l10n.settingsAboutPrivacy, AboutLinks.privacy),
        _LinkRow(l10n.settingsAboutTerms, AboutLinks.terms),
        _LinkRow(l10n.settingsAboutTrademark, AboutLinks.trademark),
        _LinkRow(l10n.settingsAboutSourceLink, AboutLinks.source),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Text(
            l10n.settingsAboutLinkHint,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  /// Flutter's licence page, with the native libraries added to the Dart and
  /// Flutter packages' licences.
  void _showLicences(
    BuildContext context,
    NativeNotices? notices,
    AppPlatform platform,
  ) {
    if (notices != null) registerNativeLicences(notices, platform);
    showLicensePage(
      context: context,
      applicationName: AboutInfo.appName,
      applicationVersion: '${AboutInfo.version} (${AboutInfo.build})',
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Semantics(
      header: true,
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    ),
  );
}

/// A web address with a copy button; never opened by the app.
class _LinkRow extends StatelessWidget {
  const _LinkRow(this.title, this.url);

  final String title;
  final String url;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      minVerticalPadding: 8,
      title: Text(title),
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
