import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/app/providers.dart';
import 'package:mediahro/core/net/network_policy.dart';
import 'package:mediahro/features/settings/core_settings.dart';
import 'package:mediahro/features/settings/privacy/privacy_source.dart';
import 'package:mediahro/features/settings/settings_providers.dart';
import 'package:mediahro/features/settings/settings_registry.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// Privacy dashboard (CORE-015, PRIV-001, PRIV-004): every endpoint the app
/// may contact on its own, each with its toggle and last-used time; the
/// three telemetry toggles (off by default) explained first; and the hosts
/// of sources and servers the user added.
class PrivacyDashboard extends ConsumerWidget {
  const PrivacyDashboard({this.highlight, super.key});

  final String? highlight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final store = ref.watch(settingsStoreProvider);
    final caps = ref.watch(capabilitiesProvider);
    final usage = ref.watch(privacyUsageProvider);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final term = SettingsRegistry.fold(highlight ?? '').trim();

    String lastUsed(DateTime? t) => t == null
        ? l10n.settingsPrivacyNeverUsed
        : l10n.settingsPrivacyLastUsed(
            DateFormat.yMMMd(locale).add_jm().format(t.toLocal()),
          );

    bool matches(String text) =>
        term.isEmpty || SettingsRegistry.fold(text).contains(term);

    Widget endpointRow(NetworkEndpoint e) {
      final key = endpointToggle(e);
      final name = privacyServiceName(e, l10n);
      return KSettingsRow.toggle(
        key: ValueKey('privacy.${e.id}'),
        title: name,
        description: [
          privacyPurpose(e.purpose, l10n),
          e.hosts.join(', '),
          lastUsed(usage.lastUsed(e)),
        ].join(' · '),
        value: settings.get(key) && !usage.isForcedOff(e),
        managed: settings.isManaged(key) || usage.isForcedOff(e),
        highlight: highlight,
        onChanged: (v) => store.set(key, v),
      );
    }

    final telemetry = [
      for (final e in Endpoints.all)
        if (telemetryEndpointIds.contains(e.id)) e,
    ];
    final services = [
      for (final e in Endpoints.all)
        if (!telemetryEndpointIds.contains(e.id) &&
            matches(
              '${privacyServiceName(e, l10n)} '
              '${privacyPurpose(e.purpose, l10n)} ${e.hosts.join(' ')}',
            ))
          e,
    ];

    return ListenableBuilder(
      listenable: usage,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(KSpacing.s16),
            child: Text(
              l10n.settingsPrivacyIntro,
              style: theme.textTheme.bodyLarge,
            ),
          ),
          KSettingsHeader(title: l10n.settingsPrivacyTelemetryHeader),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: KSpacing.s16),
            child: Text(
              l10n.settingsPrivacyTelemetryExplainer,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final e in telemetry) endpointRow(e),
          if (caps.selfUpdater)
            KSettingsRow.toggle(
              title: l10n.settingsPrivacyUpdateCheck,
              description: l10n.settingsPrivacyUpdateCheckDescription,
              value: settings.get(CoreSettings.updateCheck),
              managed: settings.isManaged(CoreSettings.updateCheck),
              highlight: highlight,
              onChanged: (v) => store.set(CoreSettings.updateCheck, v),
            )
          else
            KSettingsRow.value(
              title: l10n.settingsPrivacyUpdateCheck,
              description: l10n.settingsPrivacyUpdateCheckStore,
              valueLabel: l10n.settingsOff,
              onTap: null,
            ),
          KSettingsHeader(title: l10n.settingsPrivacyServicesHeader),
          for (final e in services) endpointRow(e),
          KSettingsHeader(title: l10n.settingsPrivacyUserHostsHeader),
          if (usage.lanDiscovery case final bool lan)
            KSettingsRow.toggle(
              key: const ValueKey('privacy.lanDiscovery'),
              title: l10n.settingsPrivacyLanDiscovery,
              description: l10n.settingsPrivacyLanDiscoveryDescription,
              value: lan,
              highlight: highlight,
              onChanged: (v) => usage.setLanDiscovery(enabled: v),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: KSpacing.s16),
            child: Text(
              l10n.settingsPrivacyUserHostsExplainer,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (usage.userConfiguredHosts().isEmpty)
            Padding(
              padding: const EdgeInsets.all(KSpacing.s16),
              child: Text(l10n.settingsPrivacyNoUserHosts),
            )
          else
            for (final h in usage.userConfiguredHosts())
              KRow(
                title: h.host,
                subtitle: lastUsed(h.lastUsed),
                leading: Icon(KIcon.server.resolve(theme.family)),
              ),
          const SizedBox(height: KSpacing.s24),
        ],
      ),
    );
  }
}

String privacyPurpose(EndpointPurpose p, AppLocalizations l10n) => switch (p) {
  EndpointPurpose.configuration => l10n.settingsPrivacyPurposeConfiguration,
  EndpointPurpose.crashReports => l10n.settingsPrivacyPurposeCrashReports,
  EndpointPurpose.analytics => l10n.settingsPrivacyPurposeAnalytics,
  EndpointPurpose.subtitles => l10n.settingsPrivacyPurposeSubtitles,
  EndpointPurpose.metadata => l10n.settingsPrivacyPurposeMetadata,
  EndpointPurpose.lyrics => l10n.settingsPrivacyPurposeLyrics,
  EndpointPurpose.artwork => l10n.settingsPrivacyPurposeArtwork,
  EndpointPurpose.fingerprinting => l10n.settingsPrivacyPurposeFingerprinting,
  EndpointPurpose.scrobbling => l10n.settingsPrivacyPurposeScrobbling,
  EndpointPurpose.maps => l10n.settingsPrivacyPurposeMaps,
  EndpointPurpose.skipMarkers => l10n.settingsPrivacyPurposeSkipMarkers,
  EndpointPurpose.userConfigured => l10n.settingsPrivacyPurposeUserConfigured,
};

/// Display name of an endpoint. Third-party names are proper nouns kept in
/// the ARB file so translators can transliterate them where customary;
/// endpoints added later fall back to their id.
String privacyServiceName(NetworkEndpoint e, AppLocalizations l10n) =>
    switch (e.id) {
      'config' => l10n.settingsPrivacyServiceConfig,
      'crash' => l10n.settingsPrivacyServiceCrash,
      'analytics' => l10n.settingsPrivacyServiceAnalytics,
      'opensubtitles' => l10n.settingsPrivacyServiceOpenSubtitles,
      'podnapisi' => l10n.settingsPrivacyServicePodnapisi,
      'subdl' => l10n.settingsPrivacyServiceSubdl,
      'tmdb' => l10n.settingsPrivacyServiceTmdb,
      'tvdb' => l10n.settingsPrivacyServiceTvdb,
      'lrclib' => l10n.settingsPrivacyServiceLrclib,
      'musicbrainz' => l10n.settingsPrivacyServiceMusicBrainz,
      'acoustid' => l10n.settingsPrivacyServiceAcoustId,
      'listenbrainz' => l10n.settingsPrivacyServiceListenBrainz,
      'lastfm' => l10n.settingsPrivacyServiceLastFm,
      'librefm' => l10n.settingsPrivacyServiceLibreFm,
      'maptiles' => l10n.settingsPrivacyServiceMapTiles,
      'introdb' => l10n.settingsPrivacyServiceIntroDb,
      'trakt' => l10n.settingsPrivacyServiceTrakt,
      _ => e.id,
    };
