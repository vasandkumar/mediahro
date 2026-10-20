import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/photos/photos_providers.dart';
import 'package:mediahro/features/photos/timeline/timeline_model.dart';
import 'package:mediahro/images/image_pipeline.dart';
import 'package:mediahro_design/mediahro_design.dart';

/// Edits date, location, title, description, keywords and rating of one
/// photo (IMG-006). Only what the user changed is written. Returns true when
/// the edit was saved.
Future<bool> showEditMetadata(
  BuildContext context,
  WidgetRef ref,
  PhotoEntry entry,
  ImageMetadata current,
) async {
  final edit = await showDialog<ImageMetadataEdit>(
    context: context,
    builder: (_) =>
        EditMetadataDialog(current: current, fallbackDate: entry.date),
  );
  if (edit == null || !context.mounted) return false;
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final outcome = await ref
        .read(metadataEditServiceProvider)
        .save(entry, edit);
    final sidecar = outcome.sidecar;
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          sidecar == null
              ? l10n.photosEditSaved
              : l10n.photosEditSavedSidecar(sidecar.pathSegments.last),
        ),
      ),
    );
    return true;
  } on Object {
    messenger?.showSnackBar(SnackBar(content: Text(l10n.photosEditFailed)));
    return false;
  }
}

class EditMetadataDialog extends StatefulWidget {
  const EditMetadataDialog({
    required this.current,
    required this.fallbackDate,
    super.key,
  });

  final ImageMetadata current;

  /// Shown as the date when the file has no capture time.
  final DateTime fallbackDate;

  @override
  State<EditMetadataDialog> createState() => _EditMetadataDialogState();
}

class _EditMetadataDialogState extends State<EditMetadataDialog> {
  late final TextEditingController _title = TextEditingController(
    text: widget.current.title ?? '',
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.current.description ?? '',
  );
  late final TextEditingController _keywords = TextEditingController(
    text: widget.current.keywords.join(', '),
  );
  late final TextEditingController _lat = TextEditingController(
    text: widget.current.latitude?.toStringAsFixed(6) ?? '',
  );
  late final TextEditingController _lon = TextEditingController(
    text: widget.current.longitude?.toStringAsFixed(6) ?? '',
  );
  late DateTime _date = widget.current.captured ?? widget.fallbackDate;
  late int _rating = widget.current.rating ?? 0;
  bool _clearLocation = false;
  bool _badCoordinates = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _keywords.dispose();
    _lat.dispose();
    _lon.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      helpText: AppLocalizations.of(context).photosEditPickDate,
    );
    if (d == null) return;
    setState(
      () => _date = DateTime(
        d.year,
        d.month,
        d.day,
        _date.hour,
        _date.minute,
        _date.second,
      ),
    );
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
      helpText: AppLocalizations.of(context).photosEditPickTime,
    );
    if (t == null) return;
    setState(
      () => _date = DateTime(
        _date.year,
        _date.month,
        _date.day,
        t.hour,
        t.minute,
        _date.second,
      ),
    );
  }

  List<String> get _keywordList => [
    for (final k in _keywords.text.split(','))
      if (k.trim().isNotEmpty) k.trim(),
  ];

  void _save() {
    final c = widget.current;
    final latText = _lat.text.trim().replaceAll(',', '.');
    final lonText = _lon.text.trim().replaceAll(',', '.');
    (double, double)? location;
    if (!_clearLocation && (latText.isNotEmpty || lonText.isNotEmpty)) {
      final lat = double.tryParse(latText);
      final lon = double.tryParse(lonText);
      if (lat == null || lon == null || lat.abs() > 90 || lon.abs() > 180) {
        setState(() => _badCoordinates = true);
        return;
      }
      if (lat != c.latitude || lon != c.longitude) location = (lat, lon);
    }
    final keywords = _keywordList;
    final changedDate = c.captured == null
        ? _date != widget.fallbackDate
        : _date != c.captured;
    Navigator.of(context).pop(
      ImageMetadataEdit(
        captured: changedDate ? _date : null,
        location: location,
        clearLocation: _clearLocation && c.latitude != null,
        title: _title.text.trim() == (c.title ?? '')
            ? null
            : _title.text.trim(),
        description: _description.text.trim() == (c.description ?? '')
            ? null
            : _description.text.trim(),
        keywords: _sameList(keywords, c.keywords) ? null : keywords,
        rating: _rating == (c.rating ?? 0) ? null : _rating,
      ),
    );
  }

  static bool _sameList(List<String> a, List<String> b) =>
      a.length == b.length &&
      Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    return AlertDialog(
      title: Text(l10n.photosEditMetadata),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _title,
            decoration: InputDecoration(labelText: l10n.photosInfoTitleField),
            textInputAction: TextInputAction.next,
          ),
          TextField(
            controller: _description,
            decoration: InputDecoration(labelText: l10n.photosInfoDescription),
            minLines: 1,
            maxLines: 4,
          ),
          TextField(
            controller: _keywords,
            decoration: InputDecoration(
              labelText: l10n.photosInfoKeywords,
              helperText: l10n.photosEditKeywordsHint,
            ),
          ),
          const SizedBox(height: KSpacing.s12),
          Semantics(
            header: true,
            child: Text(
              l10n.photosEditDate,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          Row(
            children: [
              Expanded(
                child: KButton(
                  label: DateFormat.yMMMd(locale).format(_date),
                  onPressed: _pickDate,
                ),
              ),
              const SizedBox(width: KSpacing.s8),
              Expanded(
                child: KButton(
                  label: DateFormat.jm(locale).format(_date),
                  onPressed: _pickTime,
                ),
              ),
            ],
          ),
          const SizedBox(height: KSpacing.s12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _lat,
                  enabled: !_clearLocation,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: InputDecoration(
                    labelText: l10n.photosEditLatitude,
                  ),
                ),
              ),
              const SizedBox(width: KSpacing.s8),
              Expanded(
                child: TextField(
                  controller: _lon,
                  enabled: !_clearLocation,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: InputDecoration(
                    labelText: l10n.photosEditLongitude,
                  ),
                ),
              ),
            ],
          ),
          if (_badCoordinates)
            Padding(
              padding: const EdgeInsets.only(top: KSpacing.s4),
              child: Text(
                l10n.photosEditInvalidCoordinates,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (widget.current.latitude != null)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _clearLocation,
              title: Text(l10n.photosEditClearLocation),
              onChanged: (v) => setState(() => _clearLocation = v ?? false),
            ),
          const SizedBox(height: KSpacing.s8),
          Semantics(
            label: l10n.photosInfoRating,
            value: l10n.photosRatingStars(_rating),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    tooltip: l10n.photosRatingStars(i),
                    icon: Icon(
                      i <= _rating ? Icons.star : Icons.star_border,
                      color: i <= _rating ? Colors.amber : null,
                    ),
                    // Tapping the current rating clears it.
                    onPressed: () =>
                        setState(() => _rating = _rating == i ? 0 : i),
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.photosEditCancel),
        ),
        FilledButton(onPressed: _save, child: Text(l10n.photosEditSave)),
      ],
    );
  }
}
