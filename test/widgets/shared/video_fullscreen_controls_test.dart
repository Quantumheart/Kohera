import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/media/kohera_media_source.dart';
import 'package:kohera/core/media/kohera_video_controller.dart';
import 'package:kohera/shared/widgets/media_viewer_shell.dart';
import 'package:kohera/shared/widgets/video_fullscreen_controls.dart';

class _FakeVideoController implements KoheraVideoController {
  final StreamController<bool> _playing = StreamController<bool>.broadcast();
  final StreamController<Duration> _position =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _duration =
      StreamController<Duration>.broadcast();
  final StreamController<bool> _completed = StreamController<bool>.broadcast();

  int pauseCount = 0;
  int playCount = 0;
  List<Duration> seeks = [];

  void emitDuration(Duration d) => _duration.add(d);
  void emitPosition(Duration p) => _position.add(p);
  void emitPlaying(bool p) {
    _playing.add(p);
  }

  @override
  Future<void> play() async => playCount++;

  @override
  Future<void> pause() async => pauseCount++;

  @override
  Future<void> seek(Duration position) async => seeks.add(position);

  @override
  Stream<bool> get playing => _playing.stream;

  @override
  Stream<Duration> get position => _position.stream;

  @override
  Stream<Duration> get duration => _duration.stream;

  @override
  Stream<bool> get completed => _completed.stream;

  @override
  Widget buildView({Widget? controlsOverlay}) => const SizedBox.shrink();

  @override
  Future<void> open(KoheraMediaSource source) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> setLoop(bool loop) async {}

  @override
  Future<void> dispose() async {
    await _playing.close();
    await _position.close();
    await _duration.close();
    await _completed.close();
  }
}

Widget _wrap(Widget child) => MaterialApp(
      theme: ThemeData(splashFactory: InkRipple.splashFactory),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 300, height: 200, child: child),
        ),
      ),
    );

void main() {
  group('VideoFullscreenControls', () {
    testWidgets('shows play button when paused and calls play', (tester) async {
      final controller = _FakeVideoController();
      await tester.pumpWidget(
        _wrap(VideoFullscreenControls(controller: controller)),
      );
      await tester.pump();
      controller.emitDuration(const Duration(seconds: 10));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(controller.playCount, 0);

      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pump();

      expect(controller.playCount, 1);
    });

    testWidgets('shows pause button when playing and calls pause',
        (tester) async {
      final controller = _FakeVideoController();
      await tester.pumpWidget(
        _wrap(VideoFullscreenControls(controller: controller)),
      );
      await tester.pump();
      controller.emitDuration(const Duration(seconds: 10));
      controller.emitPlaying(true);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.pause_rounded));
      await tester.pump();

      expect(controller.pauseCount, 1);
    });

    testWidgets('seeking does not toggle playback', (tester) async {
      final controller = _FakeVideoController();
      await tester.pumpWidget(
        _wrap(VideoFullscreenControls(controller: controller)),
      );
      await tester.pump();
      controller.emitDuration(const Duration(seconds: 10));
      await tester.pumpAndSettle();

      final slider = find.byType(Slider);
      expect(slider, findsOneWidget);

      await tester.tap(slider);
      await tester.pump();

      expect(controller.seeks, isNotEmpty);
      expect(controller.playCount, 0);
      expect(controller.pauseCount, 0);
    });

    testWidgets('toggles playback on tap', (tester) async {
      final controller = _FakeVideoController();
      await tester.pumpWidget(
        _wrap(VideoFullscreenControls(controller: controller)),
      );
      await tester.pump();
      controller.emitDuration(const Duration(seconds: 10));
      await tester.pumpAndSettle();

      expect(find.byType(Slider), findsOneWidget);
      expect(controller.playCount, 0);
      expect(controller.pauseCount, 0);

      final rect = tester.getRect(find.byType(VideoFullscreenControls));
      await tester.tapAt(rect.topLeft + const Offset(10, 10));
      await tester.pump();

      expect(controller.playCount, 1);
      expect(controller.pauseCount, 0);

      controller.emitPlaying(true);
      await tester.pumpAndSettle();

      await tester.tapAt(rect.topLeft + const Offset(10, 10));
      await tester.pump();

      expect(controller.pauseCount, 1);
    });

    testWidgets('seeded playing state pauses on first tap', (tester) async {
      final controller = _FakeVideoController();
      await tester.pumpWidget(
        _wrap(VideoFullscreenControls(
          controller: controller,
          initialIsPlaying: true,
          initialDuration: const Duration(seconds: 10),
        )),
      );
      await tester.pump();

      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
      expect(controller.pauseCount, 0);
      expect(controller.playCount, 0);

      await tester.tap(find.byIcon(Icons.pause_rounded));
      await tester.pump();

      expect(controller.pauseCount, 1);
      expect(controller.playCount, 0);
    });

    testWidgets('shows position and duration labels', (tester) async {
      final controller = _FakeVideoController();
      await tester.pumpWidget(
        _wrap(VideoFullscreenControls(
          controller: controller,
          initialIsPlaying: true,
          initialPosition: const Duration(seconds: 3),
          initialDuration: const Duration(seconds: 10),
        )),
      );
      await tester.pump();

      expect(find.text('00:03'), findsOneWidget);
      expect(find.text('00:10'), findsOneWidget);
    });

    testWidgets('tap reveals the shared bar visibility', (tester) async {
      final controller = _FakeVideoController();
      final bar = MediaViewerBarVisibility(false);
      await tester.pumpWidget(
        _wrap(VideoFullscreenControls(
          controller: controller,
          barVisibility: bar,
          initialDuration: const Duration(seconds: 10),
        )),
      );
      await tester.pump();

      expect(bar.value, isFalse);

      final rect = tester.getRect(find.byType(VideoFullscreenControls));
      await tester.tapAt(rect.topLeft + const Offset(10, 10));
      await tester.pump();

      expect(bar.value, isTrue);
    });
  });
}
