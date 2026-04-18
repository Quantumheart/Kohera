import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/auth/services/deep_link_service.dart';

class _FakeSource implements DeepLinkSource {
  Uri? initial;
  final _controller = StreamController<Uri>.broadcast();

  void emit(Uri uri) => _controller.add(uri);

  @override
  Future<Uri?> getInitialLink() async => initial;

  @override
  Stream<Uri> get uriLinkStream => _controller.stream;

  bool get hasListener => _controller.hasListener;

  Future<void> close() => _controller.close();
}

void main() {
  late _FakeSource source;
  late DateTime fakeNow;

  DateTime nowFn() => fakeNow;

  setUp(() {
    source = _FakeSource();
    fakeNow = DateTime(2026, 1, 1, 12);
  });

  group('DeepLinkService', () {
    test('non-kohera scheme ignored', () async {
      final service = DeepLinkService(source: source, now: nowFn);
      await service.start();
      source.emit(Uri.parse('https://example.com/register?token=x'));
      await Future<void>.delayed(Duration.zero);
      expect(service.pending, isNull);
    });

    test('kohera://register with server + token yields intent', () async {
      final service = DeepLinkService(source: source, now: nowFn);
      await service.start();
      source.emit(
        Uri.parse('kohera://register?server=matrix.org&token=abc'),
      );
      await Future<void>.delayed(Duration.zero);
      final intent = service.pending;
      expect(intent, isA<RegisterInviteIntent>());
      final invite = intent! as RegisterInviteIntent;
      expect(invite.server, 'matrix.org');
      expect(invite.token, 'abc');
    });

    test('missing server ignored', () async {
      final service = DeepLinkService(source: source, now: nowFn);
      await service.start();
      source.emit(Uri.parse('kohera://register?token=abc'));
      await Future<void>.delayed(Duration.zero);
      expect(service.pending, isNull);
    });

    test('missing token ignored', () async {
      final service = DeepLinkService(source: source, now: nowFn);
      await service.start();
      source.emit(Uri.parse('kohera://register?server=matrix.org'));
      await Future<void>.delayed(Duration.zero);
      expect(service.pending, isNull);
    });

    test('whitespace-only server/token trimmed to empty and ignored',
        () async {
      final service = DeepLinkService(source: source, now: nowFn);
      await service.start();
      source.emit(
        Uri.parse('kohera://register?server=%20%20&token=%20'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(service.pending, isNull);
    });

    test('unknown host ignored', () async {
      final service = DeepLinkService(source: source, now: nowFn);
      await service.start();
      source.emit(Uri.parse('kohera://foo?server=x&token=y'));
      await Future<void>.delayed(Duration.zero);
      expect(service.pending, isNull);
    });

    test('dedup: same URI within 30s ignored', () async {
      final service = DeepLinkService(source: source, now: nowFn);
      await service.start();

      source.emit(
        Uri.parse('kohera://register?server=matrix.org&token=abc'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(service.pending, isA<RegisterInviteIntent>());
      service.consume();

      fakeNow = fakeNow.add(const Duration(seconds: 10));
      source.emit(
        Uri.parse('kohera://register?server=matrix.org&token=abc'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(service.pending, isNull, reason: 'second within window ignored');
    });

    test('dedup: same URI accepted after window', () async {
      final service = DeepLinkService(source: source, now: nowFn);
      await service.start();

      source.emit(
        Uri.parse('kohera://register?server=matrix.org&token=abc'),
      );
      await Future<void>.delayed(Duration.zero);
      service.consume();

      fakeNow = fakeNow.add(const Duration(seconds: 31));
      source.emit(
        Uri.parse('kohera://register?server=matrix.org&token=abc'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(service.pending, isA<RegisterInviteIntent>());
    });

    test('initial link (cold start) is processed', () async {
      source.initial =
          Uri.parse('kohera://register?server=matrix.org&token=abc');
      final service = DeepLinkService(source: source, now: nowFn);
      await service.start();
      expect(service.pending, isA<RegisterInviteIntent>());
    });

    test('consume clears pending', () async {
      final service = DeepLinkService(source: source, now: nowFn);
      await service.start();
      source.emit(
        Uri.parse('kohera://register?server=matrix.org&token=abc'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(service.pending, isNotNull);
      service.consume();
      expect(service.pending, isNull);
    });

    test('start is idempotent', () async {
      final service = DeepLinkService(source: source, now: nowFn);
      await service.start();
      await service.start();
      expect(source.hasListener, isTrue);
    });

    test('dispose cancels subscription', () async {
      final service = DeepLinkService(source: source, now: nowFn);
      await service.start();
      expect(source.hasListener, isTrue);
      service.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(source.hasListener, isFalse);
    });
  });
}
