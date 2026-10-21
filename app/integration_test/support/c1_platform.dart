import 'dart:async';

import 'package:mediahro/features/video/player/player_platform.dart';
import 'package:mediahro/platform/platform_facades.dart';

/// Recording fakes of C4's facades for lane C1's tests. On a device the real
/// facades are wired by `platformOverrides()`; these keep the tests about
/// what the player asks for.
final class FakeDisplay implements DisplayFacade {
  final List<bool> keepOn = [];
  final List<double?> brightness = [];
  final List<OrientationLock> locks = [];
  final List<(String, double)> frameRates = [];
  List<DisplayInfo> list = const [
    DisplayInfo(
      id: '0',
      name: 'Built-in',
      refreshRate: 60,
      supportedRefreshRates: [48, 50, 60, 90, 120],
    ),
  ];
  final _changes = StreamController<List<DisplayInfo>>.broadcast();

  @override
  Future<List<DisplayInfo>> displays() async => list;

  @override
  Stream<List<DisplayInfo>> get changes => _changes.stream;

  void emit(List<DisplayInfo> next) {
    list = next;
    _changes.add(next);
  }

  @override
  Future<bool> matchFrameRate(String displayId, double fps) async {
    frameRates.add((displayId, fps));
    return true;
  }

  @override
  Future<void> restoreDisplayMode(String displayId) async =>
      frameRates.add((displayId, 0));

  @override
  Future<void> keepScreenOn({required bool on}) async => keepOn.add(on);

  @override
  Future<void> setWindowBrightness(double? value) async =>
      brightness.add(value);

  @override
  Future<void> setOrientationLock(OrientationLock lock) async =>
      locks.add(lock);

  @override
  Future<PresentationHandle?> openPresentation(String displayId) async => null;

  @override
  Future<void> closePresentation(PresentationHandle handle) async {}
}

final class FakePip implements PipFacade {
  FakePip({this.supported = true});

  final bool supported;
  final List<double> entered = [];
  final List<bool> autoEnter = [];
  final List<double> aspectRatios = [];
  int exits = 0;
  final _active = StreamController<bool>.broadcast();

  void setActive({required bool active}) => _active.add(active);

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<bool> enter({required double aspectRatio}) async {
    entered.add(aspectRatio);
    _active.add(true);
    return true;
  }

  @override
  Future<void> exit() async {
    exits++;
    _active.add(false);
  }

  @override
  Future<void> setAutoEnter({required bool enabled}) async =>
      autoEnter.add(enabled);

  @override
  Future<void> setAspectRatio(double aspectRatio) async =>
      aspectRatios.add(aspectRatio);

  @override
  Stream<bool> get isActive => _active.stream;
}

final class FakeMediaSession implements MediaSessionFacade {
  final List<MediaSessionKind> activated = [];
  final List<NowPlaying> nowPlaying = [];
  final List<SessionPlaybackStatus> statuses = [];
  int deactivations = 0;
  final _commands = StreamController<RemoteCommand>.broadcast();

  void send(RemoteCommand c) => _commands.add(c);

  @override
  Future<void> activate(MediaSessionKind kind) async => activated.add(kind);

  @override
  Future<void> setNowPlaying(NowPlaying item) async => nowPlaying.add(item);

  @override
  Future<void> setPlaybackStatus(SessionPlaybackStatus status) async =>
      statuses.add(status);

  @override
  Stream<RemoteCommand> get commands => _commands.stream;

  @override
  Future<void> deactivate() async => deactivations++;
}

/// Flutter-side rotation requests, used where no display facade exists.
final class FakeOrientation implements OrientationRequests {
  final List<OrientationLock> locks = [];

  @override
  Future<void> lock(OrientationLock lock) async => locks.add(lock);
}

final class FakeSpeech implements SpeechSynthesisFacade {
  final List<(String, String?, double)> spoken = [];
  int stops = 0;

  @override
  Future<List<SpeechVoice>> voices() async => const [
    SpeechVoice(id: 'en', name: 'English', languageTag: 'en-US'),
  ];

  @override
  Future<void> speak(
    String text, {
    String? languageTag,
    String? voiceId,
    double rate = 1,
  }) async => spoken.add((text, languageTag, rate));

  @override
  Future<void> stop() async => stops++;
}

/// Translates by prefixing the target language: "de: Hello".
base class FakeTranslation implements TranslationFacade {
  FakeTranslation({this.ready = false});

  bool ready;
  final List<(String, String)> prepared = [];
  final List<int> batches = [];

  @override
  Future<List<TranslationPair>> supportedPairs() async => const [
    TranslationPair('en', 'de'),
    TranslationPair('en', 'fr'),
    TranslationPair('de', 'en'),
  ];

  @override
  Future<bool> isReady(String from, String to) async => ready;

  @override
  Future<void> prepare(String from, String to) async {
    prepared.add((from, to));
    ready = true;
  }

  @override
  Future<List<String>> translate(
    List<String> lines, {
    required String from,
    required String to,
  }) async {
    batches.add(lines.length);
    return [for (final l in lines) '$to: $l'];
  }
}

/// A folder picker (StorageFacade.pickFolder) for the shader-folder
/// chooser (VID-038); the player uses nothing else of the facade.
final class FakeFolderPicker implements StorageFacade {
  FakeFolderPicker(this.grant);

  final FolderGrant? grant;
  int picks = 0;

  @override
  Future<FolderGrant?> pickFolder() async {
    picks++;
    return grant;
  }

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class FakePowerStatus implements PowerStatusFacade {
  final _changes = StreamController<PowerStatus>.broadcast();
  PowerStatus now = const PowerStatus(
    thermal: ThermalLevel.nominal,
    batterySaver: false,
  );

  void set(PowerStatus s) {
    now = s;
    _changes.add(s);
  }

  @override
  Future<PowerStatus> current() async => now;

  @override
  Stream<PowerStatus> get changes => _changes.stream;
}
