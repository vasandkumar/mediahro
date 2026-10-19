import 'package:flutter/material.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// Representative instances of every component, shared by the golden matrix
/// and the accessibility sweep. Labels are long on purpose so 200 % text
/// exercises wrapping.
final Map<String, WidgetBuilder> specimens = {
  'button': (_) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      KButton(
        label: 'Open a file',
        icon: KIcon.openFile,
        variant: KButtonVariant.primary,
        onPressed: () {},
      ),
      const SizedBox(height: 8),
      KButton(label: 'Add a network server', onPressed: () {}),
      const SizedBox(height: 8),
      KButton(
        label: 'Not now',
        variant: KButtonVariant.tertiary,
        onPressed: () {},
      ),
      Row(
        children: [
          KIconButton(icon: KIcon.play, label: 'Play', onPressed: () {}),
          KIconButton(
            icon: KIcon.subtitles,
            label: 'Subtitles: English, on',
            selected: true,
            onPressed: () {},
          ),
          const KIconButton(icon: KIcon.cast, label: 'Cast', onPressed: null),
        ],
      ),
    ],
  ),
  'seek_bar': (_) => KSeekBar(
    position: const Duration(minutes: 12, seconds: 5),
    duration: const Duration(hours: 1, minutes: 32),
    buffered: const Duration(minutes: 30),
    chapters: const [Duration(minutes: 20), Duration(minutes: 50)],
    onSeek: (_) {},
  ),
  'sheet': (_) => SizedBox(
    height: 260,
    child: KBarSurface(
      elevated: true,
      child: KSheet(
        title: 'Subtitles',
        child: Column(
          children: [
            KRow(title: 'English', selected: true, onTap: () {}),
            KRow(title: 'Deutsch', onTap: () {}),
          ],
        ),
      ),
    ),
  ),
  'grid': (_) => SizedBox(
    height: 280,
    child: KGrid(
      itemCount: 6,
      minTileWidth: 100,
      footerHeight: 40,
      itemBuilder: (context, i) => KGridTile(
        semanticLabel: 'Album $i',
        artwork: const SizedBox.expand(),
        title: 'Album number $i with a long title',
        subtitle: 'Artist',
        badges: i == 0 ? const ['RAW', 'HDR'] : const [],
        selectionMode: i < 2,
        selected: i == 1,
        onTap: () {},
      ),
    ),
  ),
  'row': (_) => Column(
    children: [
      KRow(
        title: 'Big Buck Bunny',
        subtitle: 'Blender Foundation · 2008',
        leading: const Icon(Icons.movie_outlined),
        trailing: const Text('9:56'),
        onTap: () {},
      ),
      KRow(
        title: 'Sintel',
        subtitle: 'NAS',
        unavailableLabel: 'Unavailable, last seen 2 h ago',
        onTap: () {},
      ),
      KRow(title: 'Selected row', selected: true, dense: true, onTap: () {}),
    ],
  ),
  'chip': (_) => Wrap(
    spacing: 8,
    children: [
      KChip(label: 'All', selected: true, onSelected: (_) {}),
      KChip(label: 'Local', onSelected: (_) {}),
      KChip(
        label: '1.5×',
        semanticLabel: 'Speed 1.5×',
        icon: KIcon.playback,
        onPressed: () {},
      ),
    ],
  ),
  'sidebar': (_) => Wrap(
    children: [
      for (final extended in [false, true])
        SizedBox(
          height: 360,
          child: KSidebar(
            extended: extended,
            selectedIndex: 1,
            onSelected: (_) {},
            items: const [
              KSidebarItem(icon: KIcon.video, label: 'Video'),
              KSidebarItem(icon: KIcon.music, label: 'Music'),
              KSidebarItem(icon: KIcon.photos, label: 'Photos'),
              KSidebarItem(
                icon: KIcon.sources,
                label: 'Sources',
                dividerBefore: true,
              ),
            ],
          ),
        ),
    ],
  ),
  'player_chrome': (_) => SizedBox(
    height: 300,
    child: KPlayerChrome(
      video: const ColoredBox(color: Color(0xFF203040)),
      visible: true,
      title: 'Episode 3: The long night',
      subtitle: 'Series name',
      sourceBadge: 'NAS',
      onBack: () {},
      topActions: [
        KIconButton(
          icon: KIcon.pip,
          label: 'Picture in picture',
          color: Colors.white,
          onPressed: () {},
        ),
      ],
      seekBar: KSeekBar(
        position: const Duration(minutes: 3),
        duration: const Duration(minutes: 45),
        onSeek: (_) {},
        onDark: true,
      ),
      elapsed: const Text('3:00'),
      remaining: const Text('−42:00'),
      transport: [
        KIconButton(
          icon: KIcon.seekBack,
          label: 'Back 10 seconds',
          color: Colors.white,
          onPressed: () {},
        ),
        KIconButton(
          icon: KIcon.pause,
          label: 'Pause',
          color: Colors.white,
          onPressed: () {},
        ),
        KIconButton(
          icon: KIcon.seekForward,
          label: 'Forward 10 seconds',
          color: Colors.white,
          onPressed: () {},
        ),
      ],
      chips: [KChip(label: '1×', onPressed: () {}, onDark: true)],
    ),
  ),
  'mini_player': (_) => KMiniPlayer(
    title: 'Song title that is fairly long',
    subtitle: 'Artist · Album',
    artwork: const ColoredBox(color: Color(0xFFFF7A59)),
    playing: true,
    progress: 0.3,
    onPlayPause: () {},
    playLabel: 'Play',
    pauseLabel: 'Pause',
    onOpen: () {},
    openLabel: 'Open now playing',
    onNext: () {},
    nextLabel: 'Next track',
  ),
  'compare_view': (_) => SizedBox(
    height: 200,
    child: Column(
      children: [
        for (final mode in [KCompareMode.sideBySide, KCompareMode.swipe])
          Expanded(
            child: KCompareView(
              mode: mode,
              children: const [
                ColoredBox(color: Color(0xFF3A5BFF)),
                ColoredBox(color: Color(0xFF22C3A6)),
              ],
            ),
          ),
      ],
    ),
  ),
  'timeline_scrubber': (_) => SizedBox(
    height: 240,
    child: Align(
      alignment: AlignmentDirectional.centerEnd,
      child: KTimelineScrubber(
        label: 'Timeline',
        fraction: 0.4,
        onChanged: (_) {},
        marks: const [
          KTimelineMark(label: '2026', fraction: 0),
          KTimelineMark(label: '2025', fraction: 0.35),
          KTimelineMark(label: '2024', fraction: 0.7),
        ],
      ),
    ),
  ),
  'settings_row': (_) => Column(
    children: [
      const KSettingsHeader(title: 'Appearance'),
      KSettingsRow.toggle(
        title: 'AMOLED black',
        description: 'Use pure black backgrounds in the dark theme.',
        value: true,
        onChanged: (_) {},
        icon: KIcon.appearance,
      ),
      KSettingsRow.value(
        title: 'Theme',
        description: 'Light, dark or follow the system.',
        valueLabel: 'System',
        onTap: () {},
      ),
      KSettingsRow.toggle(
        title: 'Crash reports',
        description: 'Send anonymous crash reports.',
        value: false,
        onChanged: (_) {},
        managed: true,
      ),
      KAdvancedGroup(
        children: [
          KSettingsRow.navigation(
            title: 'Engine options',
            description: 'Low-level playback options.',
            onTap: () {},
          ),
        ],
      ),
    ],
  ),
  'skeleton': (_) => const KSkeletonRows(count: 3),
  'states': (_) => Column(
    children: [
      SizedBox(
        height: 220,
        child: KEmptyState(
          message: 'Add a folder or a server to see your videos here.',
          actions: [KButton(label: 'Add a folder', onPressed: () {})],
        ),
      ),
      SizedBox(
        height: 260,
        child: KErrorState(
          message: "Couldn't open this file. It may be corrupt or on a disconnected drive.",
          action: KButton(
            label: 'Try again',
            variant: KButtonVariant.primary,
            onPressed: () {},
          ),
          secondaryAction: KButton(label: 'Choose another', onPressed: () {}),
        ),
      ),
    ],
  ),
};
