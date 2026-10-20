import 'dart:math' as math;
import 'dart:typed_data';

import 'package:mediahro_engine/mediahro_engine.dart';

/// Speech turns (start, end in seconds) over [seconds]: irregular like
/// dialogue, so only the right offset lines up.
List<(double, double)> speechTurns(int seconds, {int seed = 7}) {
  final r = math.Random(seed);
  final out = <(double, double)>[];
  var t = 2.0;
  while (t < seconds - 5) {
    final len = 0.8 + r.nextDouble() * 3.5;
    out.add((t, t + len));
    t += len + 0.4 + r.nextDouble() * 4;
  }
  return out;
}

/// A fake `PcmSource`: one-second chunks of tone bursts over faint noise
/// at [rate], for [turns].
Stream<(Duration, Float32List)> Function(MediaSource) fakePcm(
  List<(double, double)> turns, {
  required int seconds,
  int rate = 16000,
}) => (_) async* {
  final r = math.Random(3);
  for (var s = 0; s < seconds; s++) {
    final chunk = Float32List(rate);
    for (var i = 0; i < rate; i++) {
      final t = s + i / rate;
      var v = (r.nextDouble() - 0.5) * 0.002;
      for (final (a, b) in turns) {
        if (t >= a && t < b) {
          v += 0.3 * math.sin(2 * math.pi * 300 * t);
          break;
        }
      }
      chunk[i] = v;
    }
    yield (Duration(seconds: s), chunk);
  }
};

/// SRT for [turns], every line [shift] seconds late.
String turnsSrt(List<(double, double)> turns, {double shift = 0}) {
  String t(double sec) {
    final ms = ((sec + shift) * 1000).round();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(ms ~/ 3600000)}:${two(ms ~/ 60000 % 60)}:'
        '${two(ms ~/ 1000 % 60)},${(ms % 1000).toString().padLeft(3, '0')}';
  }

  final out = StringBuffer();
  for (final (i, (a, b)) in turns.indexed) {
    out
      ..writeln(i + 1)
      ..writeln('${t(a)} --> ${t(b)}')
      ..writeln('line ${i + 1}')
      ..writeln();
  }
  return out.toString();
}
