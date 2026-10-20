import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/settings/settings_store.dart';
import 'package:mediahro/features/video/player/video_memory.dart';
import 'package:mediahro/features/video/player/video_player_controller.dart';
import 'package:mediahro/features/video/player/video_render.dart';
import 'package:mediahro_design/mediahro_design.dart';
import 'package:mediahro_engine/mediahro_engine.dart';

String _aspectLabel(AppLocalizations l, double? a) => switch (a) {
  null => l.videoAspectAuto,
  1 => '1:1',
  2.35 => '2.35:1',
  1.85 => '1.85:1',
  final v when (v - 16 / 9).abs() < 1e-6 => '16:9',
  final v when (v - 4 / 3).abs() < 1e-6 => '4:3',
  final v when (v - 21 / 9).abs() < 1e-6 => '21:9',
  final v => v.toStringAsFixed(2),
};

/// The Video sheet (docs/06 §3.1): aspect, zoom, rotation and flips for
/// this video; quality, colour, tone mapping, smooth motion and shaders
/// for every video (VID-031, VID-037, VID-038, VID-039).
Future<void> showVideoSheet(
  BuildContext context,
  VideoPlayerController c, {
  required SettingsStore store,
  required Future<List<ShaderChoice>> Function(String folder) shaders,
  required bool mobile,
  Future<void> Function()? chooseShaderFolder,
}) {
  final l = AppLocalizations.of(context);
  final listed = <String, Future<List<ShaderChoice>>>{};
  return KSheet.show<void>(
    context,
    title: l.videoPictureTitle,
    builder: (sheetContext) => ListenableBuilder(
      listenable: Listenable.merge([c, store]),
      builder: (context, _) {
        final s = store.snapshot;
        final view = c.view;
        Widget header(String text) => Padding(
          padding: const EdgeInsets.only(
            top: KSpacing.s12,
            bottom: KSpacing.s4,
          ),
          child: Semantics(
            header: true,
            child: Text(text, style: Theme.of(context).textTheme.titleSmall),
          ),
        );
        Widget slider(SettingKey<double> key, String label) => Row(
          children: [
            SizedBox(width: 120, child: Text(label)),
            Expanded(
              child: Slider(
                value: s.get(key),
                min: -100,
                max: 100,
                divisions: 40,
                label: s.get(key).round().toString(),
                onChanged: (v) => store.set(key, v),
              ),
            ),
          ],
        );
        Widget pan(
          String label,
          double value,
          VideoView Function(double) next,
        ) => Row(
          children: [
            SizedBox(width: 120, child: Text(label)),
            Expanded(
              child: Slider(
                value: value.clamp(-0.5, 0.5),
                min: -0.5,
                max: 0.5,
                divisions: 20,
                label: (value * 100).round().toString(),
                onChanged: (v) => unawaited(c.setView(next(v))),
              ),
            ),
          ],
        );
        Widget cooling() => c.throttled
            ? Padding(
                padding: const EdgeInsets.only(bottom: KSpacing.s4),
                child: Text(
                  l.videoCooling,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            : const SizedBox.shrink();
        return Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header(l.videoPictureThisVideo),
              Wrap(
                spacing: KSpacing.s8,
                runSpacing: KSpacing.s4,
                children: [
                  for (final a in aspectChoices)
                    ChoiceChip(
                      label: Text(_aspectLabel(l, a)),
                      selected: view.aspect == a,
                      onSelected: (_) =>
                          unawaited(c.setView(view.copyWith(aspect: () => a))),
                    ),
                ],
              ),
              Wrap(
                spacing: KSpacing.s8,
                runSpacing: KSpacing.s4,
                children: [
                  for (final f in VideoFit.values)
                    ChoiceChip(
                      label: Text(switch (f) {
                        VideoFit.fit => l.videoZoomFit,
                        VideoFit.fill => l.videoZoomFill,
                        VideoFit.stretch => l.videoStretch,
                      }),
                      selected: view.fit == f,
                      onSelected: (_) =>
                          unawaited(c.setView(view.copyWith(fit: f))),
                    ),
                ],
              ),
              Row(
                children: [
                  SizedBox(width: 120, child: Text(l.videoZoom)),
                  Expanded(
                    child: Slider(
                      value: view.zoom.clamp(-1, 2),
                      min: -1,
                      max: 2,
                      divisions: 30,
                      label: l.videoZoomValue(
                        (100 * math.pow(2, view.zoom)).round(),
                      ),
                      onChanged: (v) =>
                          unawaited(c.setView(view.copyWith(zoom: v))),
                    ),
                  ),
                ],
              ),
              // Moving the picture only matters once part of it is cut off.
              if (view.zoom > 0 || view.fit == VideoFit.fill) ...[
                pan(
                  l.videoPanHorizontal,
                  view.panX,
                  (v) => view.copyWith(panX: v),
                ),
                pan(
                  l.videoPanVertical,
                  view.panY,
                  (v) => view.copyWith(panY: v),
                ),
              ],
              Wrap(
                spacing: KSpacing.s8,
                runSpacing: KSpacing.s4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.rotate_right_rounded),
                    label: Text(l.videoRotate(view.rotate)),
                    onPressed: () => unawaited(
                      c.setView(
                        view.copyWith(rotate: (view.rotate + 90) % 360),
                      ),
                    ),
                  ),
                  FilterChip(
                    label: Text(l.videoFlipHorizontal),
                    selected: view.flipH,
                    onSelected: (v) =>
                        unawaited(c.setView(view.copyWith(flipH: v))),
                  ),
                  FilterChip(
                    label: Text(l.videoFlipVertical),
                    selected: view.flipV,
                    onSelected: (v) =>
                        unawaited(c.setView(view.copyWith(flipV: v))),
                  ),
                  if (!view.isDefault)
                    TextButton(
                      onPressed: () => unawaited(c.setView(const VideoView())),
                      child: Text(l.videoPictureReset),
                    ),
                ],
              ),
              header(l.videoPictureQuality),
              DropdownButtonFormField<Scaler>(
                initialValue: s.get(RenderSettings.scaler),
                decoration: InputDecoration(labelText: l.videoScaler),
                items: [
                  for (final v in Scaler.values)
                    DropdownMenuItem(
                      value: v,
                      child: Text(l.videoScalerName(v.name)),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) store.set(RenderSettings.scaler, v);
                },
              ),
              DropdownButtonFormField<Deinterlace>(
                initialValue: s.get(RenderSettings.deinterlace),
                decoration: InputDecoration(labelText: l.videoDeinterlace),
                items: [
                  for (final v in Deinterlace.values)
                    DropdownMenuItem(
                      value: v,
                      child: Text(l.videoDeinterlaceName(v.name)),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) store.set(RenderSettings.deinterlace, v);
                },
              ),
              SwitchListTile(
                title: Text(l.videoDeband),
                subtitle: Text(l.videoDebandDetail),
                value: s.get(RenderSettings.deband),
                onChanged: (v) => store.set(RenderSettings.deband, v),
              ),
              Row(
                children: [
                  SizedBox(width: 120, child: Text(l.videoSharpen)),
                  Expanded(
                    child: Slider(
                      value: s.get(RenderSettings.sharpen),
                      divisions: 10,
                      label: (s.get(RenderSettings.sharpen) * 100)
                          .round()
                          .toString(),
                      onChanged: (v) => store.set(RenderSettings.sharpen, v),
                    ),
                  ),
                ],
              ),
              header(l.videoPictureColour),
              slider(RenderSettings.brightness, l.videoBrightness),
              slider(RenderSettings.contrast, l.videoContrast),
              slider(RenderSettings.saturation, l.videoSaturation),
              slider(RenderSettings.gamma, l.videoGamma),
              slider(RenderSettings.hue, l.videoHue),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: () {
                    for (final k in RenderSettings.colourKeys) {
                      store.set<double>(k, 0);
                    }
                  },
                  child: Text(l.videoPictureReset),
                ),
              ),
              header(l.videoToneMapping),
              DropdownButtonFormField<ToneMapping>(
                initialValue: s.get(RenderSettings.toneMapping),
                decoration: InputDecoration(
                  labelText: l.videoToneMappingDetail,
                ),
                items: [
                  for (final v in ToneMapping.values)
                    DropdownMenuItem(
                      value: v,
                      child: Text(l.videoToneMappingName(v.name)),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) store.set(RenderSettings.toneMapping, v);
                },
              ),
              header(l.videoPictureMotion),
              cooling(),
              SwitchListTile(
                title: Text(l.videoInterpolation),
                subtitle: Text(
                  mobile
                      ? l.videoInterpolationMobile
                      : l.videoInterpolationDetail,
                ),
                value: s.get(RenderSettings.interpolation),
                onChanged: (v) async {
                  if (v && mobile) {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(l.videoInterpolation),
                        content: Text(l.videoInterpolationBattery),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: Text(l.videoCancel),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: Text(l.videoTurnOn),
                          ),
                        ],
                      ),
                    );
                    if (ok != true) return;
                  }
                  store.set(RenderSettings.interpolation, v);
                },
              ),
              header(l.videoShaders),
              cooling(),
              FutureBuilder<List<ShaderChoice>>(
                future: listed.putIfAbsent(
                  s.get(RenderSettings.shaderFolder),
                  () => shaders(s.get(RenderSettings.shaderFolder)),
                ),
                builder: (context, snap) {
                  final list = snap.data ?? const <ShaderChoice>[];
                  final current = s.get(RenderSettings.shaderPreset);
                  void pick(ShaderChoice? choice) {
                    store.set(
                      RenderSettings.shaderPreset,
                      choice?.id ?? 'none',
                    );
                    unawaited(c.setShader(choice?.preset ?? ShaderPreset.none));
                  }

                  return RadioGroup<String>(
                    groupValue: current,
                    onChanged: (id) =>
                        pick(list.where((x) => x.id == id).firstOrNull),
                    child: Column(
                      children: [
                        RadioListTile<String>(
                          value: 'none',
                          title: Text(l.videoShaderNone),
                        ),
                        for (final choice in list)
                          RadioListTile<String>(
                            value: choice.id,
                            title: Text(choice.name),
                          ),
                        if (list.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(KSpacing.s8),
                            child: Text(
                              l.videoShadersEmpty,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        if (chooseShaderFolder != null)
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: TextButton.icon(
                              icon: const Icon(Icons.folder_open_outlined),
                              label: Text(l.videoShaderFolder),
                              onPressed: () => unawaited(chooseShaderFolder()),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    ),
  );
}
