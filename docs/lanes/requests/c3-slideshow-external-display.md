# ADR request (C3): present the slideshow on an external display

IMG-012 lists "external display". Today `DisplayFacade` can list displays (`DisplayInfo.isExternal`) but has no way to put content on one, so the slideshow runs on the phone's own screen (system mirroring already shows it on a TV).

## Proposal

Add to `DisplayFacade` (frozen interface, so this is the request):

```dart
/// Opens a presentation on [displayId] (an external display from [displays]) that
/// the app draws into with its own Flutter view, and returns its handle; null when
/// the platform cannot (A: Presentation, I: UIScene on UIScreen, M/W: a second window).
Future<PresentationHandle?> openPresentation(String displayId);
Future<void> closePresentation(PresentationHandle handle);
```

Dart side (C3): the slideshow draws its picture layer a second time into the presentation's view and keeps the controls on the phone. Android: `android.app.Presentation` hosting a `FlutterView` (or a second `FlutterEngine` fed the same textures), C4a. Apple and Windows: C4b and C4c.

Until this exists the help page says only mirroring works.
