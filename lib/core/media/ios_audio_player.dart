import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:kohera/core/media/media_player.dart';
import 'package:kohera/core/media/resolved_media.dart';
import 'package:ogg_caf_converter/ogg_caf_converter.dart';
import 'package:path_provider/path_provider.dart';

// ── iOS audio: just_audio; Ogg/Opus remuxed to CAF (native playback+seek) ─

class IosAudioPlayer implements MediaPlayer {
  IosAudioPlayer();

  AudioPlayer? _player;
  String? _cafTempPath;
  final List<StreamSubscription<dynamic>> _subs = [];

  final _playingController = StreamController<bool>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _completedController = StreamController<bool>.broadcast();

  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  Stream<bool> get onPlayingChanged => _playingController.stream;
  @override
  Stream<Duration> get onPositionChanged => _positionController.stream;
  @override
  Stream<Duration> get onDurationChanged => _durationController.stream;
  @override
  Stream<bool> get onCompleted => _completedController.stream;

  @override
  bool get isPlaying => _isPlaying;
  @override
  Duration get position => _position;
  @override
  Duration get duration => _duration;
  @override
  bool get canSeek => true;

  bool _isOggOpus(ResolvedMedia media) {
    final mime = media.mimeType?.toLowerCase();
    return mime == 'audio/ogg' || mime == 'audio/opus';
  }

  static final _oggSig = [0x4f, 0x67, 0x67, 0x53]; // 'OggS'

  Future<String?> _toCaf(String oggPath) async {
    final bytes = File(oggPath).readAsBytesSync();
    if (bytes.length < 4) return null;

    // libmpv probed past junk (e.g. ID3 tags); the strict Ogg reader does
    // not. Find the first 'OggS' capture pattern and convert from there.
    final scanLen = bytes.length < 4096 ? bytes.length : 4096;
    final oggStart = _indexOf(bytes.sublist(0, scanLen), _oggSig);
    if (oggStart < 0) {
      debugPrint(
        '[Kohera] iOS Opus file has no OggS marker '
        '(magic="${_magicBytesString(bytes)}"); skipping CAF remux, '
        'playing original directly.',
      );
      return null;
    }

    final dir = await getTemporaryDirectory();
    final ts = DateTime.now().microsecondsSinceEpoch;
    final sourcePath = oggStart == 0
        ? oggPath
        : '${dir.path}/kohera_opus_src_$ts.ogg';
    if (oggStart > 0) {
      debugPrint(
        '[Kohera] iOS Opus file has ${oggStart}B prefix before OggS '
        '(magic="${_magicBytesString(bytes)}"); stripping before CAF remux.',
      );
      File(sourcePath).writeAsBytesSync(bytes.sublist(oggStart));
    }
    final outPath = '${dir.path}/kohera_opus_$ts.caf';
    try {
      await OggCafConverter().convertOggToCaf(input: sourcePath, output: outPath);
      if (oggStart > 0) {
        try {
          File(sourcePath).deleteSync();
        } catch (_) {}
      }
      return outPath;
    } catch (e) {
      debugPrint('[Kohera] Ogg->CAF conversion failed: $e');
      return null;
    }
  }

  int _indexOf(Uint8List haystack, List<int> needle) {
    final n = needle.length;
    for (var i = 0; i + n <= haystack.length; i++) {
      var match = true;
      for (var j = 0; j < n; j++) {
        if (haystack[i + j] != needle[j]) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
  }

  String _magicBytesString(Uint8List bytes) {
    final n = bytes.length < 8 ? bytes.length : 8;
    return bytes.sublist(0, n).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
  }


  @override
  Future<void> open(ResolvedMedia media) async {
    _cancelSubs();
    await _player?.dispose();
    _deleteCafTemp();
    _player = AudioPlayer();
    _listen();
    final path = media.filePath!;
    var playPath = path;
    if (_isOggOpus(media)) {
      final cafPath = await _toCaf(path);
      if (cafPath != null) {
        _cafTempPath = cafPath;
        playPath = cafPath;
      }
    }
    await _player!.setFilePath(playPath);
  }

  @override
  Future<void> openAsset(String assetPath) async {
    _cancelSubs();
    await _player?.dispose();
    _deleteCafTemp();
    _player = AudioPlayer();
    _listen();
    await _player!.setAsset(assetPath);
  }

  void _cancelSubs() {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
  }

  void _listen() {
    final p = _player;
    if (p == null) return;
    _subs.add(p.playerStateStream.listen((state) {
      if (_playingController.isClosed) return;
      _isPlaying = state.playing;
      _playingController.add(state.playing);
    }));
    _subs.add(p.positionStream.listen((pos) {
      if (_positionController.isClosed) return;
      _position = pos;
      _positionController.add(pos);
    }));
    _subs.add(p.durationStream.listen((d) {
      if (_durationController.isClosed || d == null) return;
      _duration = d;
      _durationController.add(d);
    }));
    _subs.add(p.processingStateStream.listen((state) async {
      if (_completedController.isClosed) return;
      if (state == ProcessingState.completed) {
        _completedController.add(true);
        await _player?.pause();
        await _player?.seek(Duration.zero);
      }
    }));
  }

  @override
  Future<void> play() => _player?.play() ?? Future.value();

  @override
  Future<void> pause() => _player?.pause() ?? Future.value();

  @override
  Future<void> stop() => _player?.stop() ?? Future.value();

  @override
  Future<void> seek(Duration position) =>
      _player?.seek(position) ?? Future.value();

  @override
  void setLoopMode(bool loop) {
    unawaited(_player?.setLoopMode(loop ? LoopMode.one : LoopMode.off));
  }

  void _deleteCafTemp() {
    if (_cafTempPath != null) {
      try {
        File(_cafTempPath!).deleteSync();
      } catch (_) {}
      _cafTempPath = null;
    }
  }

  @override
  Future<void> dispose() async {
    _cancelSubs();
    await _player?.dispose();
    await _playingController.close();
    await _positionController.close();
    await _durationController.close();
    await _completedController.close();
    _deleteCafTemp();
  }
}
