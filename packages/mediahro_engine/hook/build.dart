import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

/// Compiles the engine shim (stream protocol bridge, VID-006) for the target
/// platform and bundles it as a code asset next to the app (Dart native
/// assets: Android jniLibs, Apple frameworks, Windows DLL).
void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    await CBuilder.library(
      name: 'mediahro_engine_shim',
      assetName: 'src/mpv/native_shim.dart',
      sources: ['src/shim/mediahro_engine_shim.c'],
    ).run(
      input: input,
      output: output,
      logger: Logger('')
        ..level = Level.WARNING
        // The hook's stdout is captured by the build; keep it quiet.
        ..onRecord.listen((_) {}),
    );
  });
}
