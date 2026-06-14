import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/utils/safe_url_launcher.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  group('isAllowedUrl', () {
    test('allows web, mail, and matrix schemes', () {
      expect(isAllowedUrl(Uri.parse('https://example.com')), isTrue);
      expect(isAllowedUrl(Uri.parse('http://example.com')), isTrue);
      expect(isAllowedUrl(Uri.parse('HTTPS://example.com')), isTrue);
      expect(isAllowedUrl(Uri.parse('mailto:user@example.com')), isTrue);
      expect(isAllowedUrl(Uri.parse('matrix:r/room:server')), isTrue);
    });

    test('rejects dangerous and unknown schemes', () {
      expect(isAllowedUrl(Uri.parse('file:///etc/passwd')), isFalse);
      expect(isAllowedUrl(Uri.parse('javascript:alert(1)')), isFalse);
      expect(isAllowedUrl(Uri.parse('data:text/html,<script>')), isFalse);
      expect(isAllowedUrl(Uri.parse('tel:+15551234')), isFalse);
      expect(isAllowedUrl(Uri.parse('intent://evil#Intent;end')), isFalse);
      expect(isAllowedUrl(Uri.parse('custom-app://do-something')), isFalse);
    });
  });

  group('safeLaunchUrl', () {
    test('launches an allowed URL via the injected launcher', () async {
      Uri? launched;
      final result = await safeLaunchUrl(
        'https://example.com/page',
        launcher: (uri, {mode = LaunchMode.platformDefault}) async {
          launched = uri;
          return true;
        },
      );

      expect(result, isTrue);
      expect(launched, Uri.parse('https://example.com/page'));
    });

    test('blocks a file: URL and never calls the launcher', () async {
      var called = false;
      final result = await safeLaunchUrl(
        'file:///etc/passwd',
        launcher: (uri, {mode = LaunchMode.platformDefault}) async {
          called = true;
          return true;
        },
      );

      expect(result, isFalse);
      expect(called, isFalse);
    });

    test('blocks a javascript: URL and never calls the launcher', () async {
      var called = false;
      final result = await safeLaunchUrl(
        'javascript:alert(document.cookie)',
        launcher: (uri, {mode = LaunchMode.platformDefault}) async {
          called = true;
          return true;
        },
      );

      expect(result, isFalse);
      expect(called, isFalse);
    });

    test('returns false for null input', () async {
      expect(await safeLaunchUrl(null), isFalse);
    });
  });
}
