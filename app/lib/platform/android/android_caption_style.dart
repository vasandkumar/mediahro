import 'package:mediahro/platform/android/gen/caption_api.pigeon.dart';
import 'package:mediahro/platform/caption_style.dart';

/// [CaptionStyleFacade] on Android (ADR-030, SUB-014): the system caption
/// settings from CaptioningManager (`CaptionStyleModule.kt`). Colours and
/// the font are null unless the user chose them.
final class AndroidCaptionStyle implements CaptionStyleFacade {
  AndroidCaptionStyle({
    CaptionStyleHostApi? api,
    Stream<CaptionStyleMsg> Function()? events,
  }) : _api = api ?? CaptionStyleHostApi(),
       _events = events ?? captionStyleChanges;

  final CaptionStyleHostApi _api;
  final Stream<CaptionStyleMsg> Function() _events;

  @override
  Future<SystemCaptionStyle?> current() async {
    final m = await _api.current();
    return m == null ? null : _style(m);
  }

  @override
  late final Stream<SystemCaptionStyle> changes = _events().map(_style);

  static SystemCaptionStyle _style(CaptionStyleMsg m) => SystemCaptionStyle(
    enabled: m.enabled,
    fontFamily: m.fontFamily,
    scale: m.scale,
    foregroundArgb: m.foregroundArgb,
    backgroundArgb: m.backgroundArgb,
    windowArgb: m.windowArgb,
    edge: CaptionEdge.values[m.edge.index],
    edgeArgb: m.edgeArgb,
  );
}
