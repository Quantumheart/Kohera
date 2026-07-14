import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:kohera/core/media/audio_session_setup.dart';
import 'package:kohera/core/media/media_player.dart';
import 'package:kohera/core/media/resolved_media.dart';
import 'package:ogg_opus_player/ogg_opus_player.dart';

// ── iOS audio: just_audio (MP3/AAC) + ogg_opus_player (Ogg/Opus) ─
// AVPlayer parses Opus-in-CAF but produces no audible output, so Opus voice
// messages use the native ogg_opus_player decoder instead. Seek is unsupported
// for Opus on iOS (ogg_opus_player has no seek API); audio_bubble disables the
// waveform drag via canSeek=false for that case.

class IosAudioPlayer implements MediaPlayer {
  IosAudioPlayer();

  AudioPlayer? _audioPlayer;
  OggOpusPlayer? _opusPlayer;
  Timer? _opusPositionTimer;
  final List<StreamSubscription<dynamic>> _subs = [];

  final _playingController = StreamController<bool>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _completedController = StreamController<bool>.broadcast();

  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _loop = false;
  bool _isOpus = false;

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
  bool get canSeek => !_isOpus;

  bool _isOggOpus(ResolvedMedia media) {
    final mime = media.mimeType?.toLowerCase();
    return mime == 'audio/ogg' || mime == 'audio/opus';
  }

  void _cancelSubs() {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
  }

  @override
  Future<void> open(ResolvedMedia media) async {
    await ensureMediaAudioSession();
    _cancelSubs();
    await _disposeCurrent();
    _isOpus = _isOggOpus(media);
    debugPrint(
      '[Kohera] iOS audio open (route=${_isOpus ? 'ogg_opus_player' : 'just_audio'}).',
    );
    if (_isOpus) {
      _opusPlayer = OggOpusPlayer(media.filePath!);
      _opusPlayer!.state.addListener(_onOpusStateChanged);
    } else {
      _audioPlayer = AudioPlayer();
      try {
        await _audioPlayer!.setFilePath(media.filePath!);
      } catch (e) {
        debugPrint('[Kohera] iOS audio setFilePath failed: $e');
        rethrow;
      }
      _listenJustAudio();
    }
  }

  @override
  Future<void> openAsset(String assetPath) async {
    await ensureMediaAudioSession();
    _cancelSubs();
    await _disposeCurrent();
    _isOpus = false;
    _audioPlayer = AudioPlayer();
    await _audioPlayer!.setAsset(assetPath);
    _listenJustAudio();
  }

  void _listenJustAudio() {
    final p = _audioPlayer;
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
        await _audioPlayer?.pause();
        await _audioPlayer?.seek(Duration.zero);
      }
    }));
  }

  void _onOpusStateChanged() {
    final player = _opusPlayer;
    if (player == null) return;
    final state = player.state.value;
    switch (state) {
      case PlayerState.playing:
        _isPlaying = true;
        if (!_playingController.isClosed) _playingController.add(true);
        _startOpusPositionPolling();
      case PlayerState.paused:
        _isPlaying = false;
        if (!_playingController.isClosed) _playingController.add(false);
        _stopOpusPositionPolling();
      case PlayerState.ended:
        _isPlaying = false;
        if (!_playingController.isClosed) _playingController.add(false);
        _stopOpusPositionPolling();
        if (_loop) {
          player.play();
        } else if (!_completedController.isClosed) {
          _completedController.add(true);
        }
      case PlayerState.error:
      case PlayerState.idle:
        _isPlaying = false;
        if (!_playingController.isClosed) _playingController.add(false);
        _stopOpusPositionPolling();
    }
  }

  void _startOpusPositionPolling() {
    _stopOpusPositionPolling();
    _opusPositionTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) {
        final player = _opusPlayer;
        if (player == null || _positionController.isClosed) return;
        final pos = Duration(milliseconds: (player.currentPosition * 1000).round());
        _position = pos;
        _positionController.add(pos);
      },
    );
  }

  void _stopOpusPositionPolling() {
    _opusPositionTimer?.cancel();
    _opusPositionTimer = null;
  }

  @override
  Future<void> play() async {
    if (_isOpus) {
      _opusPlayer?.play();
    } else {
      await _audioPlayer?.play();
    }
  }

  @override
  Future<void> pause() async {
    if (_isOpus) {
      _opusPlayer?.pause();
    } else {
      await _audioPlayer?.pause();
    }
  }

  @override
  Future<void> stop() async {
    if (_isOpus) {
      _opusPlayer?.pause();
    } else {
      await _audioPlayer?.stop();
    }
  }

  @override
  Future<void> seek(Duration position) async {
    if (!_isOpus) {
      await _audioPlayer?.seek(position);
    }
  }

  @override
  void setLoopMode(bool loop) {
    _loop = loop;
    if (!_isOpus) {
      unawaited(_audioPlayer?.setLoopMode(loop ? LoopMode.one : LoopMode.off));
    }
  }

  Future<void> _disposeCurrent() async {
    _stopOpusPositionPolling();
    if (_opusPlayer != null) {
      _opusPlayer!.state.removeListener(_onOpusStateChanged);
      _opusPlayer!.dispose();
      _opusPlayer = null;
    }
    if (_audioPlayer != null) {
      await _audioPlayer!.dispose();
      _audioPlayer = null;
    }
  }

  @override
  Future<void> dispose() async {
    _cancelSubs();
    await _disposeCurrent();
    await _playingController.close();
    await _positionController.close();
    await _durationController.close();
    await _completedController.close();
  }
}
