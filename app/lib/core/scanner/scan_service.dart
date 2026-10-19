import 'dart:async';

import 'package:drift/drift.dart';
import 'package:mediahro/core/db/library_database.dart';
import 'package:mediahro/core/index/index_writer.dart';
import 'package:mediahro/core/scanner/scan_model.dart';
import 'package:mediahro/core/scanner/scan_run.dart';
import 'package:mediahro/core/scanner/walker.dart';
import 'package:mediahro/core/sources/source_access.dart';

/// Outcome of one scan job.
final class ScanOutcome {
  const ScanOutcome(this.sourceId, this.state, this.result, {this.error});

  final int sourceId;
  final ScanJobState state;
  final ApplyResult result;
  final Object? error;
}

/// Change notifications for `watch` sources (StorageFacade.changes on
/// mobile, directory watchers on desktop).
typedef ChangeStream = Stream<void> Function(SourceRow source);

/// Runs scan jobs: one per source at a time, at most [concurrency] sources
/// in parallel, each walk on its own isolate. Records every job in
/// `scan_job`, streams [ScanProgress], and applies per-source schedules
/// (LIB-003: manual / on open / watch).
final class ScanService {
  ScanService({
    required this.db,
    required this.resolver,
    IndexWriter? writer,
    this.concurrency = 2,
    this.useIsolates = true,
    this.watchDebounce = const Duration(seconds: 2),
    this.onIndexed,
    DateTime Function()? clock,
  }) : writer = writer ?? IndexWriter(db, clock: clock),
       _clock = clock ?? DateTime.now;

  final LibraryDatabase db;
  final SourceResolver resolver;
  final IndexWriter writer;
  final int concurrency;
  final bool useIsolates;
  final Duration watchDebounce;

  /// Called with new or changed item ids after each job (probe queue).
  final void Function(List<int> itemIds)? onIndexed;
  final DateTime Function() _clock;

  final _progress = StreamController<ScanProgress>.broadcast();
  final _pending = <int>[];
  final _waiters = <int, List<Completer<ScanOutcome>>>{};
  final _running = <int, _Running>{};
  final _watches = <int, StreamSubscription<void>>{};
  final _debounce = <int, Timer>{};
  bool _pausedAll = false;

  Stream<ScanProgress> get progress => _progress.stream;

  bool isScanning(int sourceId) =>
      _running.containsKey(sourceId) || _pending.contains(sourceId);

  /// Queues a scan of [sourceId]; completes when that job ends. A source
  /// that is already queued or running joins the existing job.
  Future<ScanOutcome> scan(int sourceId) {
    final c = Completer<ScanOutcome>();
    (_waiters[sourceId] ??= []).add(c);
    if (!_running.containsKey(sourceId) && !_pending.contains(sourceId)) {
      _pending.add(sourceId);
      _progress.add(
        ScanProgress(sourceId: sourceId, state: ScanJobState.queued),
      );
      _pump();
    }
    return c.future;
  }

  /// Scans every enabled source whose schedule is `onOpen` (app launch).
  Future<void> onAppOpen() async {
    final rows =
        await (db.select(db.sources)..where(
              (s) =>
                  s.enabled.equals(true) &
                  s.schedule.equalsValue(ScanSchedule.onOpen),
            ))
            .get();
    await Future.wait([for (final s in rows) scan(s.id)]);
  }

  /// Subscribes to changes of every `watch` source; each burst of changes
  /// triggers one incremental scan after [watchDebounce].
  Future<void> startWatching(ChangeStream changes) async {
    final rows =
        await (db.select(db.sources)..where(
              (s) =>
                  s.enabled.equals(true) &
                  s.schedule.equalsValue(ScanSchedule.watch),
            ))
            .get();
    for (final s in rows) {
      await _watches.remove(s.id)?.cancel();
      _watches[s.id] = changes(s).listen((_) {
        _debounce[s.id]?.cancel();
        _debounce[s.id] = Timer(watchDebounce, () => unawaited(scan(s.id)));
      });
    }
  }

  void pause(int sourceId) {
    final r = _running[sourceId];
    if (r == null) return;
    r.pause();
    _progress.add(r.progress.copyWith(state: ScanJobState.paused));
  }

  void resume(int sourceId) {
    final r = _running[sourceId];
    if (r == null) return;
    r.resume();
    _progress.add(r.progress.copyWith(state: ScanJobState.running));
  }

  /// Pauses every running scan and holds queued ones (e.g. during playback
  /// on a phone or under thermal pressure).
  void pauseAll() {
    _pausedAll = true;
    _running.keys.toList().forEach(pause);
  }

  void resumeAll() {
    _pausedAll = false;
    _running.keys.toList().forEach(resume);
    _pump();
  }

  void cancel(int sourceId) {
    if (_pending.remove(sourceId)) {
      _finish(
        sourceId,
        ScanOutcome(sourceId, ScanJobState.cancelled, const ApplyResult()),
      );
      return;
    }
    _running[sourceId]?.cancel();
  }

  Future<void> dispose() async {
    for (final t in _debounce.values) {
      t.cancel();
    }
    for (final s in _watches.values) {
      await s.cancel();
    }
    _running.keys.toList().forEach(cancel);
    await _progress.close();
  }

  void _pump() {
    while (!_pausedAll &&
        _running.length < concurrency &&
        _pending.isNotEmpty) {
      final id = _pending.removeAt(0);
      final r = _Running(
        ScanProgress(sourceId: id, state: ScanJobState.running),
      );
      _running[id] = r;
      unawaited(_run(id, r));
    }
  }

  Future<void> _run(int sourceId, _Running r) async {
    final jobId = await db
        .into(db.scanJobs)
        .insert(
          ScanJobsCompanion.insert(
            sourceId: sourceId,
            state: const Value(ScanJobState.running),
            startedAt: Value(_clock()),
          ),
        );
    _progress.add(r.progress);
    ScanOutcome outcome;
    try {
      final source = await (db.select(
        db.sources,
      )..where((s) => s.id.equals(sourceId))).getSingle();
      final access = await resolver.resolve(source);
      final known = await writer.known(sourceId);
      final options = ScanOptions(
        includeKinds: {
          if (source.includeVideo) ItemKind.video,
          if (source.includeMusic) ItemKind.audio,
          if (source.includePhotos) ItemKind.image,
          ItemKind.playlist,
          ItemKind.subtitle,
          ItemKind.archive,
        },
      );
      final ScanDiff diff;
      void report(int files, int dirs) {
        r.progress = r.progress.copyWith(
          filesSeen: files,
          directoriesSeen: dirs,
        );
        if (!r.paused) _progress.add(r.progress);
      }

      if (useIsolates) {
        final run = await ScanRun.start(
          root: access.root,
          fileSystem: access.fileSystem,
          known: known,
          options: options,
        );
        r.attach(run);
        final sub = run.progress.listen((p) => report(p.$1, p.$2));
        try {
          diff = await run.result;
        } finally {
          await sub.cancel();
        }
      } else {
        diff = await ScanRun.runHere(
          root: access.root,
          fileSystem: access.fileSystem(),
          known: known,
          options: options,
          token: r.token,
          onProgress: report,
        );
      }
      final applied = await writer.apply(sourceId, diff);
      final now = _clock();
      await (db.update(db.sources)..where((s) => s.id.equals(sourceId))).write(
        SourcesCompanion(lastScanAt: Value(now), lastSeenAt: Value(now)),
      );
      await _closeJob(jobId, ScanJobState.done, diff, applied);
      outcome = ScanOutcome(sourceId, ScanJobState.done, applied);
      final changedIds = await _changedIds(sourceId, diff);
      if (changedIds.isNotEmpty) onIndexed?.call(changedIds);
    } on ScanCancelled {
      await _closeJob(jobId, ScanJobState.cancelled, null, null);
      outcome = ScanOutcome(
        sourceId,
        ScanJobState.cancelled,
        const ApplyResult(),
      );
    } on Object catch (e) {
      await _closeJob(jobId, ScanJobState.failed, null, null, error: '$e');
      outcome = ScanOutcome(
        sourceId,
        ScanJobState.failed,
        const ApplyResult(),
        error: e,
      );
    }
    _running.remove(sourceId);
    _finish(sourceId, outcome);
    _pump();
  }

  Future<List<int>> _changedIds(int sourceId, ScanDiff diff) async {
    final ids = <int>[for (final c in diff.changed) c.$1];
    if (diff.added.isNotEmpty) {
      final rows =
          await (db.selectOnly(db.items)
                ..addColumns([db.items.id])
                ..where(
                  db.items.sourceId.equals(sourceId) &
                      db.items.probed.equals(false) &
                      db.items.missing.equals(false),
                ))
              .get();
      ids.addAll(rows.map((r) => r.read(db.items.id)!));
    }
    return ids.toSet().toList();
  }

  Future<void> _closeJob(
    int jobId,
    ScanJobState state,
    ScanDiff? diff,
    ApplyResult? applied, {
    String? error,
  }) => (db.update(db.scanJobs)..where((j) => j.id.equals(jobId))).write(
    ScanJobsCompanion(
      state: Value(state),
      finishedAt: Value(_clock()),
      filesSeen: Value(diff?.filesSeen ?? 0),
      added: Value(applied?.added ?? 0),
      updated: Value((applied?.updated ?? 0) + (applied?.moved ?? 0)),
      removed: Value(applied?.removed ?? 0),
      error: Value(error),
    ),
  );

  void _finish(int sourceId, ScanOutcome outcome) {
    if (!_progress.isClosed) {
      _progress.add(
        ScanProgress(
          sourceId: sourceId,
          state: outcome.state,
          error: outcome.error?.toString(),
        ),
      );
    }
    for (final c
        in _waiters.remove(sourceId) ?? const <Completer<ScanOutcome>>[]) {
      c.complete(outcome);
    }
  }
}

final class _Running {
  _Running(this.progress);

  ScanProgress progress;
  final token = PauseToken();
  ScanRun? _run;
  bool paused = false;
  bool _cancelled = false;

  void attach(ScanRun run) {
    _run = run;
    if (paused) run.pause();
    if (_cancelled) run.cancel();
  }

  void pause() {
    paused = true;
    token.pause();
    _run?.pause();
  }

  void resume() {
    paused = false;
    token.resume();
    _run?.resume();
  }

  void cancel() {
    _cancelled = true;
    token.cancel();
    _run?.cancel();
  }
}
