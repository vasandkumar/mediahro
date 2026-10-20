import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/features/music/music_providers.dart';
import 'package:mediahro/features/music/player/wake_alarms.dart';
import 'package:mediahro_design/mediahro_design.dart';

void openAlarms(BuildContext context) =>
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const AlarmsScreen()));

/// Wake-up alarms with music (MUS-011): list, switch on/off, edit, delete.
class AlarmsScreen extends ConsumerStatefulWidget {
  const AlarmsScreen({super.key});

  @override
  ConsumerState<AlarmsScreen> createState() => _AlarmsScreenState();
}

class _AlarmsScreenState extends ConsumerState<AlarmsScreen> {
  StreamSubscription<List<WakeAlarm>>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = ref.read(wakeAlarmsProvider)?.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final alarms = ref.watch(wakeAlarmsProvider);
    final list = alarms?.alarms ?? const <WakeAlarm>[];
    return Scaffold(
      appBar: AppBar(title: Text(l10n.musicAlarms)),
      floatingActionButton: alarms == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => unawaited(_edit(context, alarms, null)),
              icon: const Icon(Icons.alarm_add),
              label: Text(l10n.musicAddAlarm),
            ),
      body: alarms == null
          ? KEmptyState(message: l10n.musicAlarmUnsupported)
          : list.isEmpty
          ? KEmptyState(message: l10n.musicAlarmsEmpty)
          : ListView(
              children: [
                for (final a in list)
                  KRow(
                    title: _time(context, a),
                    subtitle: [
                      if (a.label.isNotEmpty) a.label,
                      _repeatText(context, a),
                    ].join(' · '),
                    trailing: Switch(
                      value: a.enabled,
                      onChanged: (v) =>
                          unawaited(alarms.save(a.copyWith(enabled: v))),
                    ),
                    semanticLabel: a.enabled
                        ? l10n.musicAlarmEnabled(_time(context, a))
                        : _time(context, a),
                    onTap: () => unawaited(_edit(context, alarms, a)),
                  ),
              ],
            ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WakeAlarms alarms,
    WakeAlarm? existing,
  ) async {
    final result = await Navigator.of(context).push<WakeAlarm?>(
      MaterialPageRoute(
        builder: (_) => AlarmEditor(
          alarm: existing ?? WakeAlarm(id: alarms.newId(), hour: 7, minute: 0),
          isNew: existing == null,
        ),
      ),
    );
    if (result == null) return;
    if (result.id == '__delete__') {
      if (existing != null) await alarms.delete(existing.id);
    } else {
      await alarms.save(result);
    }
  }
}

String _time(BuildContext context, WakeAlarm a) =>
    MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay(hour: a.hour, minute: a.minute),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );

String _repeatText(BuildContext context, WakeAlarm a) {
  final l10n = AppLocalizations.of(context);
  if (a.weekdays.isEmpty) return l10n.musicAlarmOnce;
  if (a.weekdays.length == 7) return l10n.musicAlarmEveryDay;
  final names = MaterialLocalizations.of(context).narrowWeekdays;
  // narrowWeekdays starts on Sunday; ISO 7 = Sunday.
  return [for (final d in (a.weekdays.toList()..sort())) names[d % 7]]
      .join(' ');
}

/// Edits one alarm; pops the edited alarm, or a `__delete__` marker.
class AlarmEditor extends ConsumerStatefulWidget {
  const AlarmEditor({required this.alarm, required this.isNew, super.key});

  final WakeAlarm alarm;
  final bool isNew;

  @override
  ConsumerState<AlarmEditor> createState() => _AlarmEditorState();
}

class _AlarmEditorState extends ConsumerState<AlarmEditor> {
  late WakeAlarm _a = widget.alarm;
  late final _label = TextEditingController(text: widget.alarm.label);
  List<PlaylistRow> _playlists = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final db = ref.read(libraryDatabaseProvider);
    final p = await db.select(db.playlists).get();
    if (mounted) setState(() => _playlists = p);
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final names = MaterialLocalizations.of(context).narrowWeekdays;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.musicAlarms),
        actions: [
          if (!widget.isNew)
            IconButton(
              tooltip: l10n.musicDelete,
              icon: Icon(KIcon.delete.resolve(theme.family)),
              onPressed: () => Navigator.of(context)
                  .pop(const WakeAlarm(id: '__delete__', hour: 0, minute: 0)),
            ),
          TextButton(
            onPressed: () =>
                Navigator.of(context)
                    .pop(_a.copyWith(label: _label.text.trim())),
            child: Text(l10n.musicDone),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(KSpacing.s16),
        children: [
          Center(
            child: TextButton(
              onPressed: () async {
                final t = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay(hour: _a.hour, minute: _a.minute),
                );
                if (t != null) {
                  setState(
                    () => _a = _a.copyWith(hour: t.hour, minute: t.minute),
                  );
                }
              },
              child: Text(
                _time(context, _a),
                style: theme.textTheme.displayMedium,
              ),
            ),
          ),
          const SizedBox(height: KSpacing.s16),
          Text(l10n.musicAlarmRepeat, style: theme.textTheme.titleSmall),
          const SizedBox(height: KSpacing.s8),
          Wrap(
            spacing: KSpacing.s8,
            children: [
              for (final iso in const [1, 2, 3, 4, 5, 6, 7])
                FilterChip(
                  label: Text(names[iso % 7]),
                  selected: _a.weekdays.contains(iso),
                  onSelected: (v) => setState(
                    () => _a = _a.copyWith(
                      weekdays: v
                          ? {..._a.weekdays, iso}
                          : ({..._a.weekdays}..remove(iso)),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: KSpacing.s16),
          TextField(
            controller: _label,
            decoration: InputDecoration(labelText: l10n.musicAlarmLabel),
          ),
          const SizedBox(height: KSpacing.s16),
          Text(l10n.musicAlarmMusic, style: theme.textTheme.titleSmall),
          DropdownButton<int>(
            isExpanded: true,
            value: _a.playlistId ?? -1,
            items: [
              DropdownMenuItem(
                value: -1,
                child: Text(l10n.musicAlarmCurrentQueue),
              ),
              for (final p in _playlists)
                DropdownMenuItem(value: p.id, child: Text(p.name)),
            ],
            onChanged: (v) => setState(
              () => _a = _a.copyWith(
                playlistId: () => v == null || v < 0 ? null : v,
              ),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.musicAlarmShuffle),
            value: _a.shuffle,
            onChanged: (v) => setState(() => _a = _a.copyWith(shuffle: v)),
          ),
        ],
      ),
    );
  }
}
