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
  File? _tempFile;

  @override
  Future<void> open(KoheraMediaSource source) async {
    _deleteTempFile();
    final sourceResult = await _toAudioSource(source);
    _tempFile = sourceResult.tempFile;
    await _audio.setAudioSource(sourceResult.audioSource);
    await _audio.setLoopMode(_loop ? LoopMode.one : LoopMode.off);
    unawaited(_audio.play());
  }

  @override
  Future<void> play() async {
    if (_audio.processingState == ProcessingState.completed) {
      await _audio.seek(Duration.zero);
    }
    await _audio.play();
  }

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
  Future<void> dispose() async {
    await _audio.dispose();
    _deleteTempFile();
  }

  void _deleteTempFile() {
    final temp = _tempFile;
    _tempFile = null;
    if (temp != null) unawaited(_deleteQuietly(temp));
  }

  Future<void> _deleteQuietly(File f) async {
    try {
      await f.delete();
    } catch (_) {}
  }

  Future<({AudioSource audioSource, File? tempFile})> _toAudioSource(
      KoheraMediaSource source) async {
    switch (source) {
      case KoheraFileSource(:final path):
        return (audioSource: AudioSource.file(path), tempFile: null);
      case KoheraBytesSource(:final bytes):
        final file = await _bytesToTempFile(bytes);
        return (audioSource: AudioSource.file(file.path), tempFile: file);
      case KoheraAssetSource(:final assetPath):
        return (audioSource: AudioSource.asset(assetPath), tempFile: null);
    }
  }

  Future<File> _bytesToTempFile(Uint8List bytes) async {
    final dir = await Directory.systemTemp.createTemp('kohera_audio_');
    final file = File('${dir.path}/media');
    await file.writeAsBytes(bytes);
    return file;
  }
}
