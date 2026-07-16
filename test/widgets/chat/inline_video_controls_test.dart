import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/media/kohera_media_source.dart';
import 'package:kohera/core/media/kohera_video_controller.dart';
import 'package:kohera/core/utils/format_duration.dart';
import 'package:kohera/features/chat/widgets/inline_video_controls.dart';

class _FakeVideoController implements KoheraVideoController {
  final StreamController<bool> _playing = StreamController<bool>.broadcast();
  final StreamController<Duration> _position =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _duration =
      StreamController<Duration>.broadcast();
  final StreamController<bool> _completed = StreamController<bool>.broadcast();

  int playCount = 0;
  int pauseCount = 0;
  List<Duration> seeks = [];

  @override
  Future<void> open(KoheraMediaSource source) async {}

  @override
  Future<void> play() async => playCount++;

  @override
  Future<void> pause() async => pauseCount++;

  @override
  Future<void> stop() async {}

  @override
  Future<void> seek(Duration position) async => seeks.add(position);

  @override
  Future<void> setLoop(bool loop) async {}

  @override
  Stream<bool> get playing => _playing.stream;

  @override
  Stream<Duration> get position => _position.stream;

  @override
  Stream<Duration> get duration => _duration.stream;

  @override
  Stream<bool> get completed => _completed.stream;

  @override
  Widget buildView({Widget? controlsOverlay}) =>
      controlsOverlay ?? const SizedBox.shrink();

  @override
  Future<void> dispose() async {
    await _playing.close();
    await _position.close();
    await _duration.close();
    await _completed.close();
  }
}

Widget _harness({
  required _FakeVideoController controller,
  required VoidCallback onOpenFullscreen,
  bool isPlaying = false,
  Duration position = Duration.zero,
  Duration duration = const Duration(seconds: 30),
}) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 300,
          height: 200,
          child: InlineVideoControls(
            controller: controller,
            isPlaying: isPlaying,
            position: position,
            duration: duration,
            onOpenFullscreen: onOpenFullscreen,
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('InlineVideoControls', () {
    testWidgets('shows scrub bar and time labels', (tester) async {
      final fake = _FakeVideoController();
      await tester.pumpWidget(_harness(
        controller: fake,
        onOpenFullscreen: () {},
      ));
      await tester.pump();

      expect(find.byKey(const ValueKey('videoScrubBar')), findsOneWidget);
      expect(find.text(formatDuration(Duration.zero)), findsOneWidget);
      expect(find.text(formatDuration(const Duration(seconds: 30))),
          findsOneWidget);
    });

    testWidgets('play button calls play through the controller',
        (tester) async {
      final fake = _FakeVideoController();
      await tester.pumpWidget(_harness(
        controller: fake,
        onOpenFullscreen: () {},
      ));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('videoInlinePlayButton')));
      await tester.pump();

      expect(fake.playCount, 1);
    });

    testWidgets('scrubbing seeks and pauses then resumes', (tester) async {
      final fake = _FakeVideoController();
      await tester.pumpWidget(_harness(
        controller: fake,
        onOpenFullscreen: () {},
        isPlaying: true,
        position: const Duration(seconds: 5),
      ));
      await tester.pump();

      await tester.drag(
        find.byKey(const ValueKey('videoScrubBar')),
        const Offset(40, 0),
      );
      await tester.pump();

      expect(fake.seeks, isNotEmpty);
      expect(fake.pauseCount, greaterThanOrEqualTo(1));
      expect(fake.playCount, greaterThanOrEqualTo(1));
    });

    testWidgets('fullscreen button invokes callback', (tester) async {
      final fake = _FakeVideoController();
      var opened = false;
      await tester.pumpWidget(_harness(
        controller: fake,
        onOpenFullscreen: () => opened = true,
      ));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.fullscreen_rounded));
      await tester.pump();

      expect(opened, isTrue);
    });
  });
}
