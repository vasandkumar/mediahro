import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';

/// How the photo grids look: density (1–6 columns on phones) and square or
/// proportional rows (docs/06 §3.3). Shared by the timeline, albums and
/// folders so the choice follows the user around.
@immutable
final class PhotoLayoutSettings {
  const PhotoLayoutSettings({this.columns = 4, this.justified = false});

  final int columns;
  final bool justified;

  PhotoLayoutSettings copyWith({int? columns, bool? justified}) =>
      PhotoLayoutSettings(
        columns: (columns ?? this.columns).clamp(1, 6),
        justified: justified ?? this.justified,
      );

  @override
  bool operator ==(Object other) =>
      other is PhotoLayoutSettings &&
      other.columns == columns &&
      other.justified == justified;

  @override
  int get hashCode => Object.hash(columns, justified);
}

class PhotoLayoutNotifier extends Notifier<PhotoLayoutSettings> {
  @override
  PhotoLayoutSettings build() => const PhotoLayoutSettings();

  void setColumns(int n) => state = state.copyWith(columns: n);

  void toggleJustified() => state = state.copyWith(justified: !state.justified);
}

final NotifierProvider<PhotoLayoutNotifier, PhotoLayoutSettings>
photoLayoutProvider =
    NotifierProvider<PhotoLayoutNotifier, PhotoLayoutSettings>(
      PhotoLayoutNotifier.new,
    );

/// The two app-bar buttons that change the layout.
class PhotoLayoutActions extends ConsumerWidget {
  const PhotoLayoutActions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final s = ref.watch(photoLayoutProvider);
    final n = ref.read(photoLayoutProvider.notifier);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: s.justified
              ? l10n.photosLayoutSquare
              : l10n.photosLayoutAspect,
          icon: Icon(
            s.justified ? Icons.grid_view_outlined : Icons.view_quilt_outlined,
          ),
          onPressed: n.toggleJustified,
        ),
        PopupMenuButton<int>(
          tooltip: l10n.photosDensityLabel,
          icon: const Icon(Icons.density_medium_outlined),
          initialValue: s.columns,
          onSelected: n.setColumns,
          itemBuilder: (_) => [
            for (var c = 1; c <= 6; c++)
              CheckedPopupMenuItem(
                value: c,
                checked: c == s.columns,
                child: Text(NumberFormat.decimalPattern(locale).format(c)),
              ),
          ],
        ),
      ],
    );
  }
}
