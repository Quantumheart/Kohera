import 'dart:async';

import 'package:just_audio/just_audio.dart';
import 'package:kohera/core/media/audio_session_setup.dart';
import 'package:kohera/core/media/media_player.dart';
import 'package:kohera/core/media/resolved_media.dart';

// ── just_audio implementation (Android) ───────────────────────

class AndroidAudioPlayer implements MediaPlayer {
  AndroidAudioPlayer() {
    _listen();
  }

  final AudioPlayer _player = AudioPlayer();

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

  @override
  Future<void> open(ResolvedMedia media) async {
    await ensureMediaAudioSession();
    await _player.setFilePath(media.filePath!);
  }

  @override
  Future<void> openAsset(String assetPath) async {
    await _player.setAsset(assetPath);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  void setLoopMode(bool loop) {
    unawaited(_player.setLoopMode(loop ? LoopMode.one : LoopMode.off));
  }

  void _listen() {
    _player.playerStateStream.listen((state) {
      _isPlaying = state.playing;
      _playingController.add(state.playing);
    });
    _player.positionStream.listen((p) {
      _position = p;
      _positionController.add(p);
    });
    _player.durationStream.listen((d) {
      if (d != null) {
        _duration = d;
        _durationController.add(d);
      }
    });
    _player.processingStateStream.listen((state) async {
      if (state == ProcessingState.completed) {
        if (_completedController.isClosed) return;
        _completedController.add(true);
        await _player.pause();
        await _player.seek(Duration.zero);
      }
    });
  }

  @override
  Future<void> dispose() async {
    await _playingController.close();
    await _positionController.close();
    await _durationController.close();
    await _completedController.close();
    await _player.dispose();
  }
}
