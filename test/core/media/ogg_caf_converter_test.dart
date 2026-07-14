import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ogg_caf_converter/ogg_caf_converter.dart';

// ── Validates the Ogg/Opus → CAF remux that restores iOS seek/duration ─

void main() {
  final input = File('test/fixtures/sample_opus.ogg');

  test('fixture is a valid Ogg/Opus file', () {
    expect(input.existsSync(), isTrue);
    final bytes = input.readAsBytesSync();
    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'OggS');
  });

  test('convertOggToCaf produces a CAF with a packet table (duration known)',
      () async {
    final out = await _tempPath();
    await OggCafConverter().convertOggToCaf(input: input.path, output: out);

    final caf = File(out);
    expect(caf.existsSync(), isTrue);
    final bytes = caf.readAsBytesSync();

    // CAF files begin with 'caff'.
    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'caff');

    // The packet table chunk ('pakt') carries numberValidFrames, which is
    // what gives AVAudioPlayer a duration and enables seeking.
    expect(_hasChunk(bytes, 'pakt'), isTrue);
    expect(_hasChunk(bytes, 'desc'), isTrue);

    final frames = _packetTableValidFrames(bytes);
    expect(frames, greaterThan(0));

    await caf.delete();
  });

  test('convertOggToCafInMemory returns CAF bytes', () async {
    final bytes = await OggCafConverter().convertOggToCafInMemory(
      input: input.path,
    );
    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'caff');
    expect(_hasChunk(bytes, 'pakt'), isTrue);
  });
}

Future<String> _tempPath() async {
  final dir = await Directory.systemTemp.createTemp('kohera_caf_test_');
  return '${dir.path}/out.caf';
}

bool _hasChunk(Uint8List bytes, String type) {
  for (var offset = 8; offset + 4 <= bytes.length;) {
    final t = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    if (t == type) return true;
    final size = ByteData.sublistView(bytes, offset + 4, offset + 12)
        .getUint64(0);
    offset += 12 + size;
  }
  return false;
}

int _packetTableValidFrames(Uint8List bytes) {
  for (var offset = 8; offset + 12 <= bytes.length;) {
    final t = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final size = ByteData.sublistView(bytes, offset + 4, offset + 12)
        .getUint64(0);
    if (t == 'pakt') {
      final body = offset + 12;
      return ByteData.sublistView(bytes, body + 8, body + 16).getUint64(0);
    }
    offset += 12 + size;
  }
  return 0;
}
