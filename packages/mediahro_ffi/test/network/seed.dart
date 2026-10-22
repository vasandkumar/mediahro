// Seeds the network test environment's shared data directory:
//
//   dart run test/network/seed.dart test/network/data
//
// media/ is exported by every server; dfs/ holds an MS-DFS link for Samba;
// ssh/ holds a throwaway key pair for SFTP key authentication.
import 'dart:io';
import 'dart:typed_data';

import '../native_contract_test.dart' show zipStored;

/// Deterministic content so tests can verify any byte range.
int seedByte(int i) => (i * 131 + 7) & 0xff;

Future<void> main(List<String> args) async {
  final root = Directory(args.isEmpty ? 'test/network/data' : args.first);
  final media = Directory('${root.path}/media');
  await media.create(recursive: true);
  Future<void> put(String rel, List<int> bytes) async {
    final f = File('${media.path}/$rel');
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes);
  }

  await put(
    'Films/Movie One (2024).mkv',
    Uint8List.fromList(List.generate(3 << 20, seedByte)),
  );
  await put(
    'Films/Movie One (2024).en.srt',
    '1\n00:00:01,000 --> 00:00:02,000\nHi\n'.codeUnits,
  );
  await put(
    'Music/Artist/01 Song.mp3',
    Uint8List.fromList(List.generate(200000, seedByte)),
  );
  // A real, tiny media file for MiniDLNA (NET-005), which indexes only what
  // its parser opens: 16-bit mono PCM WAV. Bytes from 44 on follow
  // seedByte, so range reads stay verifiable.
  await put('Music/Artist/02 Tone.wav', wavSeeded(64000));
  await put(
    'Comics/issue 1.cbz',
    zipStored({
      'page 01.jpg': List.generate(4000, seedByte),
      'page 02.jpg': List.generate(3000, seedByte),
    }),
  );
  await put('Spaces & Ünïcode/file name.txt', 'unicode path'.codeUnits);
  // NET-001 "large files": a sparse 5 GiB file; the tail byte is known.
  final big = File('${media.path}/Large/sparse-5g.bin');
  await big.parent.create(recursive: true);
  if (big.existsSync()) big.deleteSync();
  big.createSync();
  if (Platform.isWindows) {
    // NTFS keeps a file sparse only when it is flagged before it grows;
    // otherwise seeking past the end writes out 5 GiB of zeros. Opening
    // with FileMode.write would recreate it and drop the flag, so the
    // length is set by fsutil and the last byte appended.
    for (final args in [
      ['sparse', 'setflag', big.path],
      ['file', 'seteof', big.path, '${(5 << 30) - 1}'],
    ]) {
      final r = Process.runSync('fsutil', args);
      if (r.exitCode != 0) {
        throw StateError('fsutil ${args.take(2).join(' ')}: ${r.stdout}');
      }
    }
    final raf = await big.open(mode: FileMode.append);
    await raf.writeByte(0x5A);
    await raf.close();
  } else {
    final raf = await big.open(mode: FileMode.write);
    await raf.setPosition((5 << 30) - 1);
    await raf.writeByte(0x5A);
    await raf.close();
  }

  final dfs = Directory('${root.path}/dfs');
  await dfs.create(recursive: true);
  if (!Platform.isWindows) {
    final link = Link('${dfs.path}/linked');
    if (link.existsSync()) link.deleteSync();
    await link.create(r'msdfs:127.0.0.1\public');
  }

  final ssh = Directory('${root.path}/ssh');
  await ssh.create(recursive: true);
  final key = File('${ssh.path}/id_ed25519');
  if (!key.existsSync()) {
    final r = await Process.run('ssh-keygen', [
      '-q',
      '-t',
      'ed25519',
      '-N',
      '',
      '-f',
      key.path,
    ]);
    if (r.exitCode != 0) throw StateError('ssh-keygen failed: ${r.stderr}');
  }
  await File('${ssh.path}/authorized_keys')
      .writeAsString(await File('${key.path}.pub').readAsString());
  if (!Platform.isWindows) {
    await Process.run('chmod', ['-R', 'a+rwX', media.path]);
    await Process.run('chmod', ['644', '${ssh.path}/authorized_keys']);
  }
  stdout.writeln('seeded ${root.path}');
}

/// RIFF/WAVE header (PCM, 1 channel, 8 kHz, 16-bit) over [dataBytes] of
/// [seedByte] content; the whole file is seedByte from offset 44.
Uint8List wavSeeded(int dataBytes) {
  final out = Uint8List(44 + dataBytes);
  for (var i = 44; i < out.length; i++) {
    out[i] = seedByte(i);
  }
  final h = ByteData.sublistView(out, 0, 44);
  void tag(int at, String t) {
    for (var k = 0; k < 4; k++) {
      h.setUint8(at + k, t.codeUnitAt(k));
    }
  }

  tag(0, 'RIFF');
  h.setUint32(4, 36 + dataBytes, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  h
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little) // PCM
    ..setUint16(22, 1, Endian.little) // mono
    ..setUint32(24, 8000, Endian.little)
    ..setUint32(28, 16000, Endian.little) // byte rate
    ..setUint16(32, 2, Endian.little) // block align
    ..setUint16(34, 16, Endian.little); // bits per sample
  tag(36, 'data');
  h.setUint32(40, dataBytes, Endian.little);
  return out;
}
