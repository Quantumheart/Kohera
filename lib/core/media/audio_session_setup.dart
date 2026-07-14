import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

// ── Audio session setup (playback category) ────────────────────
// iOS defaults to the ambient audio session category, which is muted by the
// hardware silent switch. Voice messages should be audible even on silent, so
// configure the spoken-audio (playback) category before any playback.

bool _configured = false;

Future<void> ensureMediaAudioSession() async {
  if (_configured) return;
  _configured = true;
  try {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
  } catch (e) {
    debugPrint('[Kohera] audio session config failed: $e');
  }
}
