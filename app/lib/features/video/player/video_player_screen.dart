import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:go_router/go_router.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/app/shortcuts/shortcut_catalog.dart';
import 'package:mediahro/app/shortcuts/shortcut_scope.dart';
import 'package:mediahro/core/library/progress.dart';
import 'package:mediahro/core/providers.dart';
import 'package:mediahro/engine/engine_pool.dart';
import 'package:mediahro/features/settings/settings_providers.dart';
import 'package:mediahro/features/video/player/info_overlay.dart';
import 'package:mediahro/features/video/player/languages.dart';
import 'package:mediahro/features/video/player/play_request.dart';
import 'package:mediahro/features/video/player/player_gestures.dart';
import 'package:mediahro/features/video/player/player_platform.dart';
import 'package:mediahro/features/video/player/player_sheets.dart';
import 'package:mediahro/features/video/player/sleep_sheet.dart';
import 'package:mediahro/features/video/player/sleep_timer.dart';
import 'package:mediahro/features/video/player/video_memory.dart';
import 'package:mediahro/features/video/player/video_player_controller.dart';
import 'package:mediahro/features/video/player/video_render.dart';
import 'package:mediahro/features/video/player/video_sheet.dart';
import 'package:mediahro/features/video/subtitles/audio_sync.dart';
import 'package:mediahro/features/video/subtitles/editor/subtitle_editor_model.dart';
import 'package:mediahro/features/video/subtitles/editor/subtitle_editor_screen.dart';
import 'package:mediahro/features/video/subtitles/subtitle_sheets.dart';
import 'package:mediahro/features/video/subtitles/subtitle_sources.dart';
import 'package:mediahro/features/video/subtitles/subtitle_speech.dart';
import 'package:mediahro/features/video/subtitles/subtitle_style.dart';
import 'package:mediahro/features/video/subtitles/subtitle_text_source.dart';
import 'package:mediahro/features/video/subtitles/subtitle_translation.dart';
import 'package:mediahro/features/video/video_settings.dart';
import 'package:mediahro/platform/platform_facades.dart';
import 'package:mediahro_design/mediahro_design.dart';
import 'package:mediahro_engine/mediahro_engine.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';
import 'package:mediahro_subtitles/mediahro_subtitles.dart';

T? _optional<T>(T Function() read) {
  try {
    return read();
  } on PlatformCapabilityUnavailable {
    return null;
  } on ProviderException catch (e) {
    if (e.exception is PlatformCapabilityUnavailable) return null;
    rethrow;
  }
}

/// Library progress for indexed items (LIB-010); null without a library.
/// `videoOverrides` points it at `progressRepositoryProvider`.
final videoProgressProvider = Provider<ProgressRepository?>((ref) => null);

/// The video player (docs/06 §3.1): video on black under
/// [KPlayerChrome], the touch gesture layer (VID-060), the seek bar with
/// chapters and A-B markers (VID-061), speed (VID-062), chapters and
/// bookmarks (VID-063), resume and post-playback (VID-064), track chooser
/// (VID-065), delays (VID-066) and the info overlay (VID-072).
class VideoPlayerScreen extends ConsumerStatefulWidget {
  const VideoPlayerScreen({required this.request, super.key});

  final PlayRequest request;

  @override
  ConsumerState<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends ConsumerState<VideoPlayerScreen> {
  /// The previous player's `engine.stop()`. The engine is shared, and a stop
  /// that lands after the next video has started wipes it (it bumps the
  /// engine's generation, so the new open quietly gives up): the next player
  /// waits for this before it opens anything (VID-067 reopen after Back).
  static Future<void> _previousStop = Future<void>.value();

  VideoPlayerController? _c;
  PlayerPlatform? _platform;
  SleepTimer? _sleep;
  SubtitleStyle? _style;
  VideoFilterChain? _chain;
  SubtitleTextSource? _text;
  SubtitleSpeaker? _speaker;
  bool _chrome = true;
  bool _locked = false;
  bool _info = false;
  StreamSubscription<PowerStatus>? _power;
  bool _cooling = false;
  bool _remaining = false;
  bool _deleteShown = false;
  Duration? _scrub;
  Timer? _hide;
  bool _phone = true;

  @override
  void initState() {
    super.initState();
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
    unawaited(_startGuarded());
  }

  /// Why the player could not start, shown instead of a black screen.
  EngineError? _failure;

  Future<void> _startGuarded() async {
    try {
      await _start();
    } on Object catch (e, st) {
      developer.log(
        'player start failed',
        error: e,
        stackTrace: st,
        name: 'mediahro.player',
      );
      if (!mounted) return;
      setState(
        () => _failure = EngineError(
          code: e is EngineException ? e.error.code : EngineErrorCode.unknown,
          detail: '$e',
        ),
      );
    }
  }

  Future<void> _start() async {
    final memory = await ref.read(videoMemoryProvider.future);
    if (!mounted) return;
    // A stop that hangs must not keep the next video from opening.
    await _previousStop.timeout(const Duration(seconds: 3), onTimeout: () {});
    if (!mounted) return;
    final engine = ref.read(playbackEngineProvider(EngineRole.video));
    final c = VideoPlayerController(
      engine: engine,
      memory: memory,
      settings: ref.read(settingsStoreProvider),
      progress: ref.read(videoProgressProvider),
      onClose: _close,
      sidecars: ref.read(sidecarLoaderProvider),
      systemCaptionsOn: () =>
          ref.read(captionPrefsProvider)?.captionsOn ?? false,
      systemLanguages: [
        for (final l in PlatformDispatcher.instance.locales) l.languageCode,
      ],
    )..addListener(_onChange);
    final music = playbackEngineProvider(EngineRole.music);
    final platform = PlayerPlatform(
      controller: c,
      settings: ref.read(settingsStoreProvider),
      display: _optional(() => ref.read(displayProvider)),
      pip: _optional(() => ref.read(pipProvider)),
      session: _optional(() => ref.read(mediaSessionProvider)),
      otherAudio: ref.exists(music) ? ref.read(music) : null,
      sessionOwner: _VideoSessionOwner(
        ProviderScope.containerOf(context, listen: false),
      ),
      isPhone: () => _phone,
    );
    platform.inPip.addListener(_onPip);
    final sleep = SleepTimer(c)..addListener(_onPip);
    final text = SubtitleTextSource(c);
    _text = text;
    if (_optional(() => ref.read(speechSynthesisProvider)) case final speech?) {
      _speaker = SubtitleSpeaker(
        source: text,
        speech: speech,
        settings: ref.read(settingsStoreProvider),
      );
    }
    setState(() {
      _c = c;
      _platform = platform;
      _sleep = sleep;
    });
    _scheduleHide();
    await platform.start();
    await c.open(widget.request);
    unawaited(_offerSubtitleAccess(c));
    unawaited(_restoreShader(c));
    _watchPower(c);
  }

  /// A device-media video with no subtitle found beside it: once, offer to
  /// allow access to its folder (Android shows no `.srt` through the
  /// MediaStore, and all-files access is not asked for). Never again after
  /// the offer, whatever the answer (SUB-012).
  Future<void> _offerSubtitleAccess(VideoPlayerController c) async {
    await c.sidecarsLoaded;
    final video = await c.request?.locate?.call();
    if (!mounted || video == null || video.scheme != 'mediastore') return;
    final loader = ref.read(sidecarLoaderProvider);
    final found = c.subtitleFiles.isNotEmpty;
    final granted = await loader.alternatesFor?.call(video) ?? const <Uri>[];
    if (!mounted || found || granted.isNotEmpty) return;
    final store = ref.read(settingsStoreProvider);
    final storage = _optional(() => ref.read(storageProvider));
    if (storage == null || store.get(VideoSettings.subtitleAccessAsked)) {
      return;
    }
    store.set(VideoSettings.subtitleAccessAsked, true);
    final l = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.videoSubtitleAccessPrompt),
        duration: const Duration(seconds: 12),
        action: SnackBarAction(
          label: l.videoSubtitleAccessAllow,
          onPressed: () => unawaited(_grantSubtitleAccess(storage, c)),
        ),
      ),
    );
  }

  Future<void> _grantSubtitleAccess(
    StorageFacade storage,
    VideoPlayerController c,
  ) async {
    try {
      final grant = await storage.pickFolder();
      if (grant != null && mounted) await c.reloadSidecars();
    } on Object catch (e, st) {
      developer.log(
        'subtitle folder access failed',
        error: e,
        stackTrace: st,
        name: 'mediahro.subtitles',
      );
    }
  }

  /// Pauses shaders and smooth motion while the device is hot or saving
  /// battery (VID-038, VID-039, ADR-033).
  void _watchPower(VideoPlayerController c) {
    final power = _optional(() => ref.read(powerStatusProvider));
    if (power == null) return;
    void apply(PowerStatus s) {
      if (!mounted) return;
      unawaited(
        c.setThrottled(
          throttled:
              s.thermal.index >= ThermalLevel.serious.index || s.batterySaver,
        ),
      );
    }

    _power = power.changes.listen(apply);
    unawaited(power.current().then(apply, onError: (Object _) {}));
  }

  void _close() {
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/video');
    }
  }

  /// The Picture sheet (VID-037…039).
  Future<void> _showPicture(bool mobile) {
    final store = ref.read(settingsStoreProvider);
    return showVideoSheet(
      context,
      _c!,
      store: store,
      shaders: ref.read(shaderLibraryProvider),
      mobile: mobile,
      chooseShaderFolder: switch (_optional(() => ref.read(storageProvider))) {
        final storage? => () async {
          final grant = await storage.pickFolder();
          // mpv reads shaders by path: folders with a file path only.
          if (grant != null && grant.uri.scheme == 'file') {
            store.set(RenderSettings.shaderFolder, grant.uri.toString());
          } else if (grant != null && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  AppLocalizations.of(context).videoShaderFolderUnsupported,
                ),
              ),
            );
          }
        },
        null => null,
      },
    );
  }

  /// Puts back the user's shader preset (VID-038) for a new player.
  Future<void> _restoreShader(VideoPlayerController c) async {
    final store = ref.read(settingsStoreProvider);
    final id = store.get(RenderSettings.shaderPreset);
    if (id == 'none') return;
    final list = await ref.read(shaderLibraryProvider)(
      store.get(RenderSettings.shaderFolder),
    );
    final choice = list.where((x) => x.id == id).firstOrNull;
    if (choice != null) await c.setShader(choice.preset);
  }

  /// "Sync to the audio" (SUB-050): decode the audio faster than playback,
  /// find where speech and subtitles line up, preview the correction as
  /// the file's delay and speed, with Undo.
  Future<void> _syncSubtitles() async {
    final c = _c;
    final text = _text;
    final pcm = ref.read(pcmSourceProvider);
    final request = c?.request;
    if (c == null || text == null || pcm == null || request == null) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    void say(String m) => messenger.showSnackBar(SnackBar(content: Text(m)));
    final doc = await text.load();
    if (doc == null) {
      say(l.videoTranslateOnlyFiles);
      return;
    }
    final AudioSyncRun run;
    try {
      run = await AudioSyncRun.start(
        pcm: pcm,
        source: await request.mediaSource(),
        doc: doc,
        duration: c.state.duration,
      );
    } on Object {
      say(l.videoSyncFailed);
      return;
    }
    if (!mounted) {
      await run.cancel();
      return;
    }
    BuildContext? dialog;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          dialog = context;
          return AlertDialog(
            title: Text(l.videoSyncRunning),
            content: ListenableBuilder(
              listenable: run,
              builder: (context, _) =>
                  LinearProgressIndicator(value: run.progress),
            ),
            actions: [
              TextButton(
                onPressed: () => unawaited(run.cancel()),
                child: Text(l.videoCancel),
              ),
            ],
          );
        },
      ),
    );
    SyncResult? result;
    try {
      result = await run.result;
    } on SyncCancelled {
      result = null;
    } on Object {
      say(l.videoSyncFailed);
    }
    if (dialog case final d? when d.mounted) Navigator.of(d).pop();
    if (result == null || !mounted) return;
    if (!result.confident) {
      final apply = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l.videoSyncUnsureTitle),
          content: Text(l.videoSyncUnsureBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l.videoCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l.videoSyncApplyAnyway),
            ),
          ],
        ),
      );
      if (apply != true) return;
    }
    final preview = await SyncPreview.apply(c, result);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 10),
        content: Text(
          l.videoSyncApplied(l.videoDelayValue(result.offset.inMilliseconds)),
        ),
        action: SnackBarAction(
          label: l.videoEditorUndo,
          onPressed: () => unawaited(preview.undo(c)),
        ),
      ),
    );
  }

  /// "Translate subtitles" (SUB-053): the selected subtitle file into
  /// another language, on the device, as a new track.
  Future<void> _translateSubtitles() async {
    final c = _c;
    final text = _text;
    final facade = _optional(() => ref.read(translationProvider));
    if (c == null || text == null || facade == null) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    void say(String m) => messenger.showSnackBar(SnackBar(content: Text(m)));
    final doc = await text.load();
    if (doc == null) {
      say(l.videoTranslateOnlyFiles);
      return;
    }
    final translator = SubtitleTranslator(facade);
    var from = primaryLanguage(text.language);
    if (!mounted) return;
    from ??= await _chooseLanguage(
      l.videoTranslateFrom,
      await translator.sources(),
    );
    if (from == null || !mounted) return;
    final targets = await translator.targetsFor(from);
    if (!mounted) return;
    if (targets.isEmpty) {
      say(l.videoTranslateNoPairs(languageName(from)));
      return;
    }
    final device = primaryLanguage(
      PlatformDispatcher.instance.locale.languageCode,
    );
    targets.sort(
      (a, b) => a == device ? -1 : (b == device ? 1 : a.compareTo(b)),
    );
    final to = await _chooseLanguage(l.videoTranslateTo, targets);
    if (to == null || !mounted) return;
    if (await translator.needsDownload(from, to)) {
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l.videoTranslateDownloadTitle),
          content: Text(
            l.videoTranslateDownloadBody(languageName(from), languageName(to)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l.videoCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l.videoTranslateDownload),
            ),
          ],
        ),
      );
      if (ok != true) return;
      await translator.download(from, to);
    }
    say(l.videoTranslating(languageName(to)));
    final SubtitleDocument translated;
    try {
      translated = await translator.translate(doc, from: from, to: to);
    } on Object {
      say(l.videoTranslateFailed);
      return;
    }
    final name = l.videoTranslatedTitle(languageName(to));
    final file = await ref
        .read(sidecarLoaderProvider)
        .store(
          'translated.$to.srt',
          encodeSubtitleText(const SrtParser().write(translated)),
        );
    if (file == null) return;
    await c.addSubtitleFile(file.uri, title: name, language: to, select: true);
  }

  Future<String?> _chooseLanguage(String title, List<String> codes) =>
      showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(title),
          children: [
            for (final code in codes)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(code),
                child: Text(languageName(code)),
              ),
          ],
        ),
      );

  /// "Edit subtitles" (SUB-030): one of the subtitle files of this video
  /// (or a picked one) in the editor, with the video's clock.
  Future<void> _editSubtitles() async {
    final c = _c;
    if (c == null) return;
    final l = AppLocalizations.of(context);
    final loader = ref.read(sidecarLoaderProvider);
    final candidates = <(String, Uri, Uri?)>[
      for (final f in c.subtitleFiles.values)
        (f.$3 ?? f.$1.pathSegments.last, f.$1, f.$2),
    ];
    // mpv loads a local video's sidecars itself; find them for editing.
    final video = await c.request?.locate?.call();
    if (video != null && video.scheme == 'file') {
      for (final f in await loader.find(video)) {
        if (!candidates.any((x) => x.$3 == f.source)) {
          candidates.add((f.title, f.file, f.source));
        }
      }
    }
    if (!mounted) return;
    var pick = candidates.length == 1 ? candidates.single : null;
    if (candidates.length > 1) {
      pick = await showDialog<(String, Uri, Uri?)>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(l.videoEditorChooseFile),
          children: [
            for (final f in candidates)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(f),
                child: Text(f.$1),
              ),
          ],
        ),
      );
    } else if (candidates.isEmpty) {
      final picked = await ref.read(subtitleFilePickerProvider)?.call();
      if (picked != null) {
        final file = await loader.store(picked.name, picked.bytes);
        if (file != null) pick = (picked.name, file.uri, null);
      }
    }
    if (pick == null || !mounted) return;
    final chosen = pick;
    final SubtitleEditorModel model;
    try {
      model = await SubtitleEditorModel.open(
        chosen.$1,
        await File.fromUri(chosen.$2).readAsBytes(),
        charset: c.subtitleCodepage,
      );
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.videoEditorCantOpen)));
      }
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SubtitleEditorScreen(
          model: model,
          save: (name, bytes) => _saveSubtitles(chosen.$3, name, bytes),
          position: () => c.state.position,
          seek: (at) => unawaited(c.seekTo(at)),
        ),
      ),
    );
    model.dispose();
  }

  /// Saves an edited subtitle file next to its source when that folder can
  /// be written (local, SAF, writable shares), else in the app's subtitle
  /// folder, and shows it in the player at once. Returns where it went.
  Future<String?> _saveSubtitles(
    Uri? source,
    String name,
    Uint8List bytes,
  ) async {
    String? where;
    if (source != null) {
      final target = source.resolve(Uri.encodeComponent(name));
      try {
        final fs = ref.read(mountsProvider).forUri(target);
        if (fs is MutableFileSystem) {
          final w = await fs.create(target);
          await w.write(bytes);
          await w.close();
          where = target.scheme == 'file'
              ? target.toFilePath()
              : Uri.decodeFull(target.toString());
        }
      } on VirtualFileException {
        where = null;
      }
    }
    if (where == null) {
      try {
        final dir = Directory(
          '${ref.read(appDataDirectoryProvider).path}/subtitles',
        );
        await dir.create(recursive: true);
        final f = File('${dir.path}/$name');
        await f.writeAsBytes(bytes, flush: true);
        where = f.path;
      } on FileSystemException {
        return null;
      }
    }
    final copy = await ref.read(sidecarLoaderProvider).store(name, bytes);
    if (copy != null) {
      await _c?.addSubtitleFile(
        copy.uri,
        title: name,
        language: languageOfName(name),
        select: true,
      );
    }
    return where;
  }

  /// "Add a subtitle file" (SUB-012): pick, cache, add, show.
  Future<void> _addSubtitleFile() async {
    final pick = ref.read(subtitleFilePickerProvider);
    final c = _c;
    if (pick == null || c == null) return;
    final PickedSubtitle? picked;
    try {
      picked = await pick();
    } on Object catch (e, st) {
      // A pick that fails after the file was chosen used to end in silence.
      developer.log(
        'adding a subtitle file failed',
        error: e,
        stackTrace: st,
        name: 'mediahro.subtitles',
      );
      if (!mounted) return;
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is NotASubtitleFile
                ? l.videoSubtitleNotRecognised
                : l.videoSubtitleAddFailed,
          ),
        ),
      );
      return;
    }
    if (picked == null) return;
    final file = await ref
        .read(sidecarLoaderProvider)
        .store(picked.name, picked.bytes);
    if (file == null) return;
    await c.addSubtitleFile(
      file.uri,
      title: picked.name,
      language: languageOfName(picked.name),
      select: true,
    );
  }

  void _onPip() {
    if (mounted) setState(() {});
  }

  void _onChange() {
    final c = _c!;
    final s = c.state;
    final playing = s.status == PlaybackStatus.playing;
    if (c.deletePending && !_deleteShown) {
      _deleteShown = true;
      unawaited(_confirmDelete());
    }
    if (!playing && !_chrome) setState(() => _chrome = true);
    if (c.steppedDown && !_cooling && mounted) {
      _cooling = true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).videoCooling)),
      );
    } else if (!c.throttled) {
      _cooling = false;
    }
    if (mounted) setState(() {});
  }

  Future<void> _confirmDelete() async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.videoDeleteTitle),
        content: Text(l.videoDeleteBody(_c!.request?.title ?? '')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.videoCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.videoDeleteConfirm),
          ),
        ],
      ),
    );
    _deleteShown = false;
    if (ok ?? false) {
      await _c?.confirmDelete();
    } else {
      _c?.cancelDelete();
    }
  }

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      final c = _c;
      if (!mounted || c == null || !c.isPlaying || _scrub != null) return;
      if (!KPlayerChrome.shouldAutoHide(context)) return;
      setState(() => _chrome = false);
    });
  }

  void _toggleChrome() {
    setState(() => _chrome = !_chrome);
    if (_chrome) _scheduleHide();
  }

  /// Any control use keeps the chrome up for another 3 s.
  void _poke() {
    if (!_chrome) setState(() => _chrome = true);
    _scheduleHide();
  }

  @override
  void dispose() {
    _hide?.cancel();
    unawaited(_power?.cancel());
    _sleep
      ?..removeListener(_onPip)
      ..dispose();
    _speaker?.dispose();
    _text?.dispose();
    final c = _c;
    final platform = _platform;
    if (platform != null) {
      platform.inPip.removeListener(_onPip);
      // Its synchronous part detaches from the controller before that is
      // disposed below.
      unawaited(platform.dispose());
    }
    if (c != null) {
      c
        ..removeListener(_onChange)
        ..dispose();
      _previousStop = c.engine.stop().then<void>(
        (_) {},
        onError: (Object _) {},
      );
    }
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  // ------------------------------------------------------------- shortcuts

  Map<String, VoidCallback> _handlers(VideoPlayerController c) {
    void run(Future<void> Function() f) {
      _poke();
      unawaited(f());
    }

    Duration s(int n) => Duration(seconds: n);
    const subStep = Duration(milliseconds: 50);
    const audioStep = Duration(milliseconds: 10);
    return {
      'player.playPause': () => run(c.togglePlay),
      'player.seekBack5': () => run(() => c.seekBy(-s(5))),
      'player.seekForward5': () => run(() => c.seekBy(s(5))),
      'player.seekBack1': () => run(() => c.seekBy(-s(1))),
      'player.seekForward1': () => run(() => c.seekBy(s(1))),
      'player.seekBack60': () => run(() => c.seekBy(-s(60))),
      'player.seekForward60': () => run(() => c.seekBy(s(60))),
      'player.seekBack10': () => run(() => c.seekBy(-s(10))),
      'player.seekForward10': () => run(() => c.seekBy(s(10))),
      for (var i = 1; i <= 9; i++)
        'player.jump${i}0': () => run(() => c.jumpToPercent(i * 10)),
      'player.frameBack': () => run(() => c.frameStep(backwards: true)),
      'player.frameForward': () => run(c.frameStep),
      'player.abLoopSet': () => run(c.markLoopPoint),
      'player.abLoopClear': () => run(c.clearLoop),
      'player.speedDown': () => run(() => c.nudgeRate(up: false)),
      'player.speedUp': () => run(() => c.nudgeRate(up: true)),
      'player.speedReset': () => run(c.resetRate),
      'player.volumeUp': () => run(() => c.setVolume(c.volume + 0.05)),
      'player.volumeDown': () => run(() => c.setVolume(c.volume - 0.05)),
      'player.mute': () => run(c.toggleMute),
      'player.audioCycle': () => run(c.cycleAudio),
      'player.subtitleCycle': () => run(c.cycleSubtitle),
      'player.subtitleToggle': () => run(
        () => c.state.subtitleTrackId == null
            ? c.cycleSubtitle()
            : c.selectSubtitle(null),
      ),
      'player.subtitleDelayMinus': () =>
          run(() => c.setSubtitleDelay(c.subtitleDelay - subStep)),
      'player.subtitleDelayPlus': () =>
          run(() => c.setSubtitleDelay(c.subtitleDelay + subStep)),
      'player.audioDelayMinus': () =>
          run(() => c.setAudioDelay(c.audioDelay - audioStep)),
      'player.audioDelayPlus': () =>
          run(() => c.setAudioDelay(c.audioDelay + audioStep)),
      'player.info': () => setState(() => _info = !_info),
      'player.pip': () => unawaited(_platform?.enterPip()),
      'player.exitFullscreen': _close,
    };
  }

  // ---------------------------------------------------------------- build

  GestureConfig _gestures(WidgetRef ref) {
    final g = ref.watch(settingsProvider);
    return GestureConfig(
      seek: g.get(VideoSettings.gestureSeek),
      brightness: g.get(VideoSettings.gestureBrightness),
      volume: g.get(VideoSettings.gestureVolume),
      doubleTap: g.get(VideoSettings.gestureDoubleTap),
      longPress: g.get(VideoSettings.gestureLongPress),
      pinch: g.get(VideoSettings.gesturePinch),
      subtitleDelay: g.get(VideoSettings.gestureSubtitleDelay),
      doubleTapStep: Duration(seconds: g.get(VideoSettings.doubleTapSeconds)),
      longPressRate: g.get(VideoSettings.longPressSpeed),
      sensitivity: g.get(VideoSettings.gestureSensitivity),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = _c;
    if (c == null) {
      final failure = _failure;
      return ColoredBox(
        color: Colors.black,
        child: failure == null
            ? const SizedBox.expand()
            : Center(
                child: _ErrorCard(error: failure, onBack: _close),
              ),
      );
    }
    _phone = MediaQuery.sizeOf(context).shortestSide < 600;
    final s = c.state;
    final dur = s.duration ?? Duration.zero;
    final shown = _scrub ?? s.position;
    String t(Duration d) => formatMediaDuration(d, reference: dur);
    final playing = s.status == PlaybackStatus.playing;
    final touch = switch (Theme.of(context).platform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };

    final video = _VideoSurface(
      textureId: c.engine.textureId,
      size: PlayerPlatform.videoSize(s),
      fit: c.view.fit,
    );

    final platform = _platform!;
    // In picture-in-picture only the video shows (VID-067).
    if (platform.inPip.value) {
      return ColoredBox(color: Colors.black, child: video);
    }

    // Subtitle style from the settings over the system caption style
    // (SUB-014); sent again whenever it changes.
    final settingsNow = ref.watch(settingsProvider);
    final captions = ref.watch(captionPrefsProvider);
    // Picture settings and this video's view (VID-037, VID-039); sent
    // again whenever they change.
    final chain = filterChainFor(settingsNow, c.view);
    if (chain != _chain) {
      _chain = chain;
      unawaited(c.applyVideoFilters());
    }
    final style = subtitleStyleFor(settingsNow, system: captions);
    if (style != _style) {
      _style = style;
      unawaited(c.applySubtitleStyle(style));
    }
    final secondText = s.secondarySubtitleText;
    final secondOnTop = settingsNow.get(SubtitleSettings.secondaryOnTop);

    final error = s.error ?? _failure;
    final overlay = Stack(
      fit: StackFit.expand,
      children: [
        if (secondText != null && secondText.isNotEmpty)
          Positioned(
            left: KSpacing.s24,
            right: KSpacing.s24,
            top: secondOnTop ? KSpacing.s24 : null,
            // Above the first subtitles near the bottom.
            bottom: secondOnTop ? null : 120,
            child: SafeArea(
              child: IgnorePointer(
                child: SecondarySubtitleText(
                  text: secondText,
                  scale: secondaryScale(settingsNow, system: captions),
                ),
              ),
            ),
          ),
        if (_info)
          Positioned(
            top: 72,
            left: KSpacing.s16,
            child: SafeArea(child: VideoInfoOverlay(state: s)),
          ),
        if (s.status == PlaybackStatus.buffering ||
            s.status == PlaybackStatus.opening)
          const Center(child: CircularProgressIndicator(color: Colors.white)),
        if (error != null)
          Center(
            child: _ErrorCard(error: error, onBack: _close),
          ),
        if (c.resumedFrom case final from? when error == null)
          Positioned(
            left: KSpacing.s16,
            bottom: 140,
            child: SafeArea(
              child: _Banner(
                text: l.videoResumedAt(t(from)),
                action: l.videoStartOver,
                onAction: () => unawaited(c.startOver()),
                onDismiss: c.dismissResumed,
              ),
            ),
          ),
        if (c.nextUp case final next?)
          Positioned(
            right: KSpacing.s16,
            bottom: 140,
            child: SafeArea(
              child: _Banner(
                text: l.videoNextUp(next.request.title, next.remaining),
                action: l.videoPlayNow,
                onAction: () => unawaited(c.playNextNow()),
                onDismiss: c.cancelNextUp,
              ),
            ),
          ),
        if (_locked && _chrome)
          Center(
            child: KIconButton(
              icon: KIcon.lock,
              label: l.videoUnlock,
              color: Colors.white,
              size: 32,
              onPressed: () => setState(() => _locked = false),
            ),
          ),
      ],
    );

    final seekBar = Stack(
      clipBehavior: Clip.none,
      children: [
        KSeekBar(
          position: shown,
          duration: dur,
          buffered: s.bufferedUntil,
          chapters: [for (final ch in c.chapters) ch.start],
          onDark: true,
          onScrubStart: () => setState(() => _scrub = s.position),
          onScrubUpdate: (d) => setState(() => _scrub = d),
          onScrubEnd: () {
            setState(() => _scrub = null);
            _scheduleHide();
          },
          onSeek: (d) {
            _poke();
            unawaited(c.seekTo(d));
          },
          previewBuilder: (context, at) =>
              _SeekPreview(label: t(at), chapter: _chapterAt(c, at)),
        ),
        if (dur > Duration.zero)
          Positioned.fill(
            child: IgnorePointer(
              child: _LoopMarkers(a: c.abA, b: c.abB, duration: dur),
            ),
          ),
      ],
    );

    final chrome = KPlayerChrome(
      video: video,
      visible: _chrome && !_locked,
      title: c.request?.title ?? widget.request.title,
      subtitle: c.request?.subtitle,
      sourceBadge: c.request?.sourceBadge,
      onBack: _close,
      overlay: overlay,
      topActions: [
        KIconButton(
          icon: KIcon.appearance,
          label: l.videoPictureTitle,
          color: Colors.white,
          onPressed: () => unawaited(_showPicture(touch)),
        ),
        KIconButton(
          icon: KIcon.info,
          label: l.videoInfoToggle,
          selected: _info,
          color: Colors.white,
          onPressed: () => setState(() => _info = !_info),
        ),
        if (platform.pipSupported)
          KIconButton(
            icon: KIcon.pip,
            label: l.videoPip,
            color: Colors.white,
            onPressed: () => unawaited(platform.enterPip()),
          ),
        KIconButton(
          icon: KIcon.more,
          label: l.videoMoreTitle,
          color: Colors.white,
          onPressed: () =>
              unawaited(showMoreSheet(context, c, platform, _sleep!)),
        ),
      ],
      seekBar: seekBar,
      elapsed: Text(t(shown)),
      remaining: GestureDetector(
        onTap: () => setState(() => _remaining = !_remaining),
        child: Semantics(
          button: true,
          label: _remaining ? l.videoShowDuration : l.videoShowRemaining,
          child: Text(
            _remaining
                ? l.videoRemaining(
                    t(
                      dur - shown < Duration.zero ? Duration.zero : dur - shown,
                    ),
                  )
                : t(dur),
          ),
        ),
      ),
      transport: [
        KIconButton(
          icon: KIcon.seekBack,
          label: l.videoSeekBack(10),
          color: Colors.white,
          onPressed: () {
            _poke();
            unawaited(c.seekBy(const Duration(seconds: -10)));
          },
        ),
        KIconButton(
          icon: playing ? KIcon.pause : KIcon.play,
          label: playing ? l.videoPause : l.videoPlay,
          color: Colors.white,
          size: 40,
          onPressed: () {
            _poke();
            unawaited(c.togglePlay());
          },
        ),
        KIconButton(
          icon: KIcon.seekForward,
          label: l.videoSeekForward(10),
          color: Colors.white,
          onPressed: () {
            _poke();
            unawaited(c.seekBy(const Duration(seconds: 10)));
          },
        ),
      ],
      chips: [
        if (_sleep case final sleep? when sleep.active)
          KChip(
            label: sleepLabel(l, sleep, dur),
            icon: KIcon.playback,
            semanticLabel: l.videoSleepChip(sleepLabel(l, sleep, dur)),
            onDark: true,
            onPressed: () => unawaited(showSleepSheet(context, sleep)),
          ),
        KChip(
          label: l.videoSpeedValue(s.rate),
          semanticLabel: l.videoSpeedChip(l.videoSpeedValue(s.rate)),
          onDark: true,
          onPressed: () => unawaited(showSpeedSheet(context, c)),
        ),
        KChip(
          label: l.videoSubtitlesTitle,
          icon: KIcon.subtitles,
          selected: s.subtitleTrackId != null,
          semanticLabel: s.subtitleTrackId == null
              ? l.videoSubtitlesChipOff
              : l.videoSubtitlesChipOn,
          onDark: true,
          onPressed: () => unawaited(
            showSubtitleSheet(
              context,
              c,
              onAddFile: ref.read(subtitleFilePickerProvider) == null
                  ? null
                  : _addSubtitleFile,
              onEdit: _editSubtitles,
              speaker: _speaker,
              textSource: _text,
              onSync: ref.read(pcmSourceProvider) == null
                  ? null
                  : _syncSubtitles,
              onTranslate:
                  _optional(() => ref.read(translationProvider)) == null
                  ? null
                  : _translateSubtitles,
            ),
          ),
        ),
        KChip(
          label: l.videoAudioTitle,
          icon: KIcon.audioTrack,
          onDark: true,
          onPressed: () => unawaited(showAudioSheet(context, c)),
        ),
      ],
      trailingActions: [
        if (touch)
          KIconButton(
            icon: KIcon.lock,
            label: l.videoLock,
            color: Colors.white,
            onPressed: () => setState(() {
              _locked = true;
              _chrome = false;
            }),
          ),
      ],
    );

    final surface = touch
        ? PlayerGestureLayer(
            controller: c,
            config: _gestures(ref),
            locked: _locked,
            onToggleChrome: _toggleChrome,
            onFill: (v) => unawaited(
              c.setView(c.view.copyWith(fit: v ? VideoFit.fill : VideoFit.fit)),
            ),
            setBrightness: switch (platform.display) {
              final d? => d.setWindowBrightness,
              null => null,
            },
            child: chrome,
          )
        // Desktop: a click on the video plays or pauses; buttons keep their
        // own clicks, and moving the mouse shows the chrome.
        : GestureDetector(
            onTap: () => unawaited(c.togglePlay()),
            child: MouseRegion(onHover: (_) => _poke(), child: chrome),
          );

    return Scaffold(
      backgroundColor: Colors.black,
      body: ShortcutScopeWidget(
        scope: ShortcutScope.player,
        handlers: _handlers(c),
        child: Focus(autofocus: true, child: surface),
      ),
    );
  }

  static String? _chapterAt(VideoPlayerController c, Duration at) {
    final cs = c.chapters;
    for (var i = cs.length - 1; i >= 0; i--) {
      if (at >= cs[i].start) return cs[i].title;
    }
    return null;
  }
}

/// The video player's hold on the shared media session (ADR-029). Reads
/// through the container, which outlives this screen's dispose.
final class _VideoSessionOwner implements SessionOwnership {
  _VideoSessionOwner(this._container);

  final ProviderContainer _container;

  @override
  bool get ownedByVideo =>
      _container.read(mediaSessionOwnerProvider) == MediaSessionKind.video;

  @override
  void claim() => _container
      .read(mediaSessionOwnerProvider.notifier)
      .claim(MediaSessionKind.video);

  @override
  void release() => _container
      .read(mediaSessionOwnerProvider.notifier)
      .release(MediaSessionKind.video);
}

class _VideoSurface extends StatelessWidget {
  const _VideoSurface({
    required this.textureId,
    required this.size,
    required this.fit,
  });

  final int? textureId;
  final (int, int)? size;
  final VideoFit fit;

  @override
  Widget build(BuildContext context) {
    final id = textureId;
    if (id == null) return const ColoredBox(color: Colors.black);
    final (w, h) = size ?? (16, 9);
    return ColoredBox(
      color: Colors.black,
      child: ClipRect(
        child: FittedBox(
          fit: switch (fit) {
            VideoFit.fit => BoxFit.contain,
            VideoFit.fill => BoxFit.cover,
            VideoFit.stretch => BoxFit.fill,
          },
          child: SizedBox(
            width: w.toDouble(),
            height: h.toDouble(),
            child: Texture(textureId: id, filterQuality: FilterQuality.medium),
          ),
        ),
      ),
    );
  }
}

class _SeekPreview extends StatelessWidget {
  const _SeekPreview({required this.label, this.chapter});

  final String label;
  final String? chapter;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge!
        .copyWith(color: Colors.white);
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(KRadius.sm),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: KSpacing.s8,
            vertical: KSpacing.s4,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (chapter != null)
                Text(
                  chapter!,
                  style: style.copyWith(color: Colors.white70),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              Text(label, style: style),
            ],
          ),
        ),
      ),
    );
  }
}

/// A and B markers over the seek bar (VID-061).
class _LoopMarkers extends StatelessWidget {
  const _LoopMarkers({
    required this.a,
    required this.b,
    required this.duration,
  });

  final Duration? a;
  final Duration? b;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    if (a == null) return const SizedBox.shrink();
    final accent = Theme.of(context).colorScheme.primary;
    return LayoutBuilder(
      builder: (context, c) {
        double x(Duration d) =>
            c.maxWidth *
            (d.inMilliseconds / duration.inMilliseconds).clamp(0, 1);
        return Stack(
          children: [
            if (b != null)
              Positioned(
                left: x(a!),
                width: (x(b!) - x(a!)).clamp(0, c.maxWidth),
                top: c.maxHeight / 2 - 2,
                height: 4,
                child: ColoredBox(color: accent.withValues(alpha: 0.6)),
              ),
            for (final m in [a!, ?b])
              Positioned(
                left: x(m) - 1.5,
                top: c.maxHeight / 2 - 9,
                width: 3,
                height: 18,
                child: ColoredBox(color: accent),
              ),
          ],
        );
      },
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.text,
    required this.action,
    required this.onAction,
    required this.onDismiss,
  });

  final String text;
  final String action;
  final VoidCallback onAction;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(KRadius.md),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: KSpacing.s12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text, style: const TextStyle(color: Colors.white)),
              TextButton(onPressed: onAction, child: Text(action)),
              KIconButton(
                icon: KIcon.close,
                label: l.videoDismiss,
                color: Colors.white,
                onPressed: onDismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Engine errors as user copy (docs/06 §8), detail behind "Copy details".
class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.error, required this.onBack});

  final EngineError error;
  final VoidCallback onBack;

  static String message(AppLocalizations l, EngineErrorCode code) =>
      switch (code) {
        EngineErrorCode.unsupportedFormat => l.videoErrorUnsupported,
        EngineErrorCode.decodeFailed => l.videoErrorDecode,
        EngineErrorCode.sourceUnavailable => l.videoErrorSource,
        EngineErrorCode.networkTimeout => l.videoErrorNetwork,
        EngineErrorCode.libraryMissing => l.videoErrorEngineMissing,
        EngineErrorCode.engineCrashed ||
        EngineErrorCode.invalidArgument ||
        EngineErrorCode.notSupported ||
        EngineErrorCode.unknown => l.videoErrorGeneric,
      };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(KSpacing.s24),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(KRadius.md),
        ),
        child: Padding(
          padding: const EdgeInsets.all(KSpacing.s16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message(l, error.code),
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: KSpacing.s12),
              Wrap(
                spacing: KSpacing.s8,
                children: [
                  if (error.detail != null)
                    KButton(
                      label: l.videoCopyDetails,
                      icon: KIcon.copy,
                      onPressed: () => unawaited(
                        Clipboard.setData(ClipboardData(text: error.detail!)),
                      ),
                    ),
                  KButton(
                    label: l.videoChooseAnother,
                    variant: KButtonVariant.primary,
                    onPressed: onBack,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
