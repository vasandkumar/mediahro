import 'package:flutter/material.dart' hide ImageInfo;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/library/format.dart';
import 'package:mediahro/features/photos/info/edit_metadata_dialog.dart';
import 'package:mediahro/features/photos/map/map_providers.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// The details sheet of the viewer (IMG-006): file facts, camera, location,
/// colour profile, rating and keywords, every other tag on request, and the
/// way to edit what the file can carry.
class PhotoInfoSheet extends ConsumerStatefulWidget {
  const PhotoInfoSheet({required this.entry, super.key});

  final PhotoEntry entry;

  @override
  ConsumerState<PhotoInfoSheet> createState() => _PhotoInfoSheetState();
}

class _PhotoInfoSheetState extends ConsumerState<PhotoInfoSheet> {
  Future<void> _edit(PhotoFacts facts) async {
    final saved = await showEditMetadata(
      context,
      ref,
      widget.entry,
      facts.parsed.metadata,
    );
    if (saved && mounted) ref.invalidate(photoFactsProvider(widget.entry));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final e = widget.entry;
    final async = ref.watch(photoFactsProvider(e));
    if (async.hasError) {
      return Padding(
        padding: const EdgeInsets.all(KSpacing.s16),
        child: Text(l10n.photosLoadFailedMessage),
      );
    }
    final facts = async.value;
    if (facts == null) {
      return const Padding(
        padding: EdgeInsets.all(KSpacing.s24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final m = facts.parsed.metadata;
    final info = facts.info;
    final nearest = m.latitude == null || m.longitude == null
        ? null
        : ref
              .watch(
                nearestPlaceProvider((lat: m.latitude!, lon: m.longitude!)),
              )
              .value;
    final mp = info.width * info.height / 1e6;
    final rows = <(String, String)>[
      (l10n.photosInfoName, e.name),
      (l10n.photosInfoSize, formatBytes(e.size, locale: locale)),
      (
        l10n.photosInfoDimensions,
        '${info.width} × ${info.height}'
            '${mp >= 0.1 ? ' · ${l10n.photosInfoMegapixels(NumberFormat('0.0', locale).format(mp))}' : ''}',
      ),
      (l10n.photosInfoFormat, info.format.toUpperCase()),
      if (m.captured != null)
        (
          l10n.photosInfoTaken,
          DateFormat.yMMMEd(locale).add_jms().format(m.captured!),
        )
      else
        (
          l10n.photosInfoTaken,
          DateFormat.yMMMEd(locale).add_jm().format(e.date),
        ),
      if (m.cameraMake != null || m.cameraModel != null)
        (
          l10n.photosInfoCamera,
          [m.cameraMake, m.cameraModel].whereType<String>().join(' '),
        ),
      if (m.lens != null) (l10n.photosInfoLens, m.lens!),
      if (m.latitude != null && m.longitude != null)
        (
          l10n.photosInfoLocation,
          [
            if (nearest != null)
              l10n.photosPlaceName(nearest.name, nearest.country),
            '${m.latitude!.toStringAsFixed(5)}, ${m.longitude!.toStringAsFixed(5)}',
          ].join('\n'),
        ),
      if (m.iccProfileName != null) (l10n.photosInfoColour, m.iccProfileName!),
      if (m.title != null) (l10n.photosInfoTitleField, m.title!),
      if (m.description != null) (l10n.photosInfoDescription, m.description!),
      if (m.rating != null && m.rating! > 0)
        (l10n.photosInfoRating, l10n.photosRatingStars(m.rating!)),
    ];
    final flags = [
      if (info.isLivePhoto || e.livePhoto) l10n.photosInfoLivePhoto,
      if (info.isMotionPhoto) l10n.photosInfoMotionPhoto,
      if (info.isPanorama) l10n.photosInfoPanorama,
      if (info.range != ImageDynamicRange.sdr) l10n.photosInfoHdr,
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (label, value) in rows) _InfoRow(label: label, value: value),
        if (flags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: KSpacing.s8),
            child: Wrap(
              spacing: KSpacing.s8,
              children: [for (final f in flags) Chip(label: Text(f))],
            ),
          ),
        if (m.keywords.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: KSpacing.s8),
            child: Text(
              l10n.photosInfoKeywords,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          Wrap(
            spacing: KSpacing.s8,
            children: [for (final k in m.keywords) Chip(label: Text(k))],
          ),
        ],
        const SizedBox(height: KSpacing.s8),
        if (m.exif.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: KSpacing.s8),
            child: Text(l10n.photosInfoNoMetadata),
          )
        else
          // The sheet paints its own background; the tile needs a Material
          // of its own for ink.
          Material(
            type: MaterialType.transparency,
            child: ExpansionTile(
              title: Text(l10n.photosInfoAllTags),
              children: [
                for (final entry
                    in (m.exif.entries.toList()
                      ..sort((a, b) => a.key.compareTo(b.key))))
                  _InfoRow(label: entry.key, value: entry.value, dense: true),
              ],
            ),
          ),
        const SizedBox(height: KSpacing.s8),
        KButton(
          label: l10n.photosEditMetadata,
          icon: KIcon.edit,
          onPressed: () => _edit(facts),
        ),
        const SizedBox(height: KSpacing.s16),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.dense = false,
  });

  final String label;
  final String value;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: dense ? 2 : KSpacing.s4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: Text(
                label,
                style: (dense ? t.bodySmall : t.bodyMedium)?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: KSpacing.s12),
            Expanded(
              flex: 3,
              child: SelectableText(
                value,
                style: dense ? t.bodySmall : t.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
