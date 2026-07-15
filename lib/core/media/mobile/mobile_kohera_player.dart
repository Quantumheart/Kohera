import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';
import 'package:kohera/core/media/kohera_media_source.dart';
import 'package:kohera/core/media/kohera_player.dart';

// ── just_audio player backend (iOS/Android audio + ringtones) ─

class MobileKoheraPlayer implements KoheraPlayer {
  MobileKoheraPlayer() : _audio = AudioPlayer();

  final AudioPlayer _audio;
  bool _loop = false;

  @override
  Future<void> open(KoheraMediaSource source) async {
    await _audio.setAudioSource(await _toAudioSource(source));
    await _audio.setLoopMode(_loop ? LoopMode.one : LoopMode.off);
    await _audio.play();
  }

  @override
  Future<void> play() => _audio.play();

  @override
  Future<void> pause() => _audio.pause();

  @override
  Future<void> stop() => _audio.stop();

  @override
  Future<void> seek(Duration position) => _audio.seek(position);

  @override
  Future<void> setLoop(bool loop) {
    _loop = loop;
    return _audio.setLoopMode(loop ? LoopMode.one : LoopMode.off);
  }

  @override
  Stream<bool> get playing => _audio.playerStateStream
      .map((s) => s.processingState != ProcessingState.completed && s.playing);

  @override
  Stream<Duration> get position => _audio.positionStream;

  @override
  Stream<Duration> get duration =>
      _audio.durationStream.where((d) => d != null).cast<Duration>();

  @override
  Stream<bool> get completed => _audio.processingStateStream
      .where((s) => s == ProcessingState.completed)
      .map((_) => true);

  @override
  Future<void> dispose() => _audio.dispose();

  Future<AudioSource> _toAudioSource(KoheraMediaSource source) async =>
      switch (source) {
        KoheraFileSource(:final path) => AudioSource.file(path),
        KoheraBytesSource(:final bytes) =>
          AudioSource.file(await _bytesToTempPath(bytes)),
        KoheraAssetSource(:final assetPath) => AudioSource.asset(assetPath),
      };

  Future<String> _bytesToTempPath(Uint8List bytes) async {
    final dir = await Directory.systemTemp.createTemp('kohera_audio_');
    final file = File('${dir.path}/media');
    await file.writeAsBytes(bytes);
    return file.path;
  }
}
