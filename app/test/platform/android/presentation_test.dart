import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahro/platform/android/android_display.dart';
import 'package:mediahro/platform/android/gen/presentation_api.pigeon.dart';
import 'package:mediahro/platform/android/presentation_codec.dart';
import 'package:mediahro/platform/android/presentation_main.dart';
import 'package:mediahro/platform/display.dart';

/// 1x1 PNG.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0,
  0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

final class _FakePresentation extends PresentationHostApi {
  final calls = <String>[];
  Map<String, Object?>? lastFrame;
  int? opens = 7;

  @override
  Future<int?> open(String displayId) async {
    calls.add('open:$displayId');
    return opens;
  }

  @override
  Future<void> close(int id) async => calls.add('close:$id');

  @override
  Future<void> present(int id, Map<String, Object?> frame) async {
    calls.add('present:$id');
    lastFrame = frame;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('frame codec', () {
    test('IMG-012 a full frame survives the standard message codec', () {
      final frame = PresentationFrame(
        image: _png,
        fit: BoxFit.cover,
        transition: PresentationTransition.crossfade,
        transitionDuration: const Duration(milliseconds: 600),
        motion: const PresentationMotion(
          from: Rect.fromLTRB(0, 0, 1, 1),
          to: Rect.fromLTRB(0.1, 0.2, 0.7, 0.8),
          duration: Duration(seconds: 6),
        ),
        caption: 'Lisbon, 2024',
      );
      // What goes over the platform channel and what the engine on the other
      // screen reads.
      const codec = StandardMessageCodec();
      final wire =
          codec.decodeMessage(
                codec.encodeMessage(PresentationFrameCodec.toMap(frame)),
              )!
              as Map<Object?, Object?>;
      expect(PresentationFrameCodec.fromMap(wire), frame);
    });

    test('IMG-012 a clear frame, defaults and a missing motion', () {
      const codec = StandardMessageCodec();
      final wire =
          codec.decodeMessage(
                codec.encodeMessage(
                  PresentationFrameCodec.toMap(PresentationFrame.clear),
                ),
              )!
              as Map<Object?, Object?>;
      final back = PresentationFrameCodec.fromMap(wire);
      expect(back, PresentationFrame.clear);
      expect(back.image, isNull);
      expect(back.motion, isNull);
      expect(back.fit, BoxFit.contain);
      expect(back.transition, PresentationTransition.none);
    });

    test('IMG-012 every fit and transition name round trips', () {
      for (final fit in BoxFit.values) {
        for (final t in PresentationTransition.values) {
          final f = PresentationFrame(fit: fit, transition: t);
          expect(
            PresentationFrameCodec.fromMap(PresentationFrameCodec.toMap(f)),
            f,
          );
        }
      }
    });

    test('IMG-012 unknown names and loose number types are tolerated', () {
      final f = PresentationFrameCodec.fromMap({
        'fit': 'no-such-fit',
        'transition': 'spin',
        'transitionMs': 250.0,
        'image': <int>[1, 2, 3],
        'motion': {
          'from': [0, 0, 1, 1],
          'to': [0.25, 0.25, 0.75, 0.75],
          'durationMs': 4000.0,
        },
      });
      expect(f.fit, BoxFit.contain);
      expect(f.transition, PresentationTransition.none);
      expect(f.transitionDuration, const Duration(milliseconds: 250));
      expect(f.image, Uint8List.fromList([1, 2, 3]));
      expect(f.motion!.to, const Rect.fromLTRB(0.25, 0.25, 0.75, 0.75));
      expect(f.motion!.duration, const Duration(seconds: 4));
    });

    test('IMG-012 frames compare by content', () {
      final a = PresentationFrame(image: Uint8List.fromList([1, 2]));
      final b = PresentationFrame(image: Uint8List.fromList([1, 2]));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(PresentationFrame(image: Uint8List.fromList([1, 3]))));
    });
  });

  group('AndroidDisplay presentations', () {
    test('ADR-044 open, present and close go to the native module', () async {
      final api = _FakePresentation();
      final display = AndroidDisplay(presentation: api);
      final handle = await display.openPresentation('2');
      expect(handle, const PresentationHandle(id: 7, displayId: '2'));
      await display.present(
        handle!,
        PresentationFrame(image: _png, caption: 'x'),
      );
      expect(api.lastFrame!['caption'], 'x');
      expect(api.lastFrame!['image'], _png);
      await display.closePresentation(handle);
      expect(api.calls, ['open:2', 'present:7', 'close:7']);
    });

    test(
      'ADR-044 the built-in screen or a gone display gives no handle',
      () async {
        final api = _FakePresentation()..opens = null;
        expect(
          await AndroidDisplay(presentation: api).openPresentation('0'),
          isNull,
        );
      },
    );
  });

  group('the external display page', () {
    late List<MethodCall> control;

    setUp(() {
      control = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(presentationControl, (call) async {
            control.add(call);
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(presentationControl, null);
    });

    Future<void> send(WidgetTester tester, PresentationFrame frame) async {
      const codec = StandardMessageCodec();
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'mediahro/presentation',
        codec.encodeMessage(PresentationFrameCodec.toMap(frame)),
        (_) {},
      );
      await tester.pump();
    }

    testWidgets(
      'IMG-012 the page says it is ready, starts black and shows a frame',
      (tester) async {
        await tester.pumpWidget(const PresentationPage());
        expect(control.map((c) => c.method), ['ready']);
        expect(find.byType(Image), findsNothing);
        await send(tester, PresentationFrame(image: _png, caption: 'Hello'));
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.byType(Image), findsOneWidget);
        expect(find.text('Hello'), findsOneWidget);
        await send(tester, PresentationFrame.clear);
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.byType(Image), findsNothing);
        expect(find.text('Hello'), findsNothing);
      },
    );

    testWidgets('IMG-012 a crossfade keeps the old frame until it is done', (
      tester,
    ) async {
      await tester.pumpWidget(const PresentationPage());
      await send(tester, PresentationFrame(image: _png));
      await tester.pump(const Duration(milliseconds: 10));
      await send(
        tester,
        PresentationFrame(
          image: Uint8List.fromList([..._png]),
          transition: PresentationTransition.crossfade,
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(Image), findsNWidgets(2));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('IMG-012 a frame with motion runs to its end region', (
      tester,
    ) async {
      await tester.pumpWidget(const PresentationPage());
      await send(
        tester,
        PresentationFrame(
          image: _png,
          motion: const PresentationMotion(
            from: Rect.fromLTRB(0, 0, 1, 1),
            to: Rect.fromLTRB(0.25, 0.25, 0.75, 0.75),
            duration: Duration(seconds: 2),
          ),
        ),
      );
      expect(find.byType(KenBurns), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      final t = tester.widget<Transform>(
        find
            .descendant(
              of: find.byType(KenBurns),
              matching: find.byType(Transform),
            )
            .first,
      );
      // The end region is half the image: zoomed 2x.
      expect(t.transform.getMaxScaleOnAxis(), closeTo(2, 1e-6));
    });
  });

  group('Ken Burns', () {
    test('IMG-012 the whole image is the identity, a half region is 2x on its centre', () {
      const size = Size(1000, 500);
      final whole = KenBurns.transformFor(
        const Rect.fromLTRB(0, 0, 1, 1),
        size,
      );
      expect(whole.getMaxScaleOnAxis(), closeTo(1, 1e-9));
      final p = MatrixUtils.transformPoint(whole, const Offset(300, 200));
      expect(p.dx, closeTo(300, 1e-9));
      expect(p.dy, closeTo(200, 1e-9));
      // The region 0.25..0.75 centred on the box: the centre stays, scale 2.
      final half = KenBurns.transformFor(
        const Rect.fromLTRB(0.25, 0.25, 0.75, 0.75),
        size,
      );
      expect(half.getMaxScaleOnAxis(), closeTo(2, 1e-9));
      final c = MatrixUtils.transformPoint(half, const Offset(500, 250));
      expect(c.dx, closeTo(500, 1e-9));
      expect(c.dy, closeTo(250, 1e-9));
      // A region in the top-left corner moves that corner to the box centre.
      final corner = KenBurns.transformFor(
        const Rect.fromLTRB(0, 0, 0.5, 0.5),
        size,
      );
      final o = MatrixUtils.transformPoint(corner, const Offset(250, 125));
      expect(o.dx, closeTo(500, 1e-9));
      expect(o.dy, closeTo(250, 1e-9));
    });
  });
}
