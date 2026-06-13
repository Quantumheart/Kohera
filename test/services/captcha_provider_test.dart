import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/auth/services/captcha_provider.dart';

void main() {
  group('classifyCaptchaProvider', () {
    test('classifies production Turnstile keys', () {
      expect(
        classifyCaptchaProvider('0x4AAAAAAABkMYinukE8nzYS'),
        CaptchaProvider.turnstile,
      );
    });

    test('classifies Turnstile testing keys (1x/2x/3x prefixes)', () {
      expect(
        classifyCaptchaProvider('1x00000000000000000000AA'),
        CaptchaProvider.turnstile,
      );
      expect(
        classifyCaptchaProvider('2x00000000000000000000AB'),
        CaptchaProvider.turnstile,
      );
      expect(
        classifyCaptchaProvider('3x00000000000000000000FF'),
        CaptchaProvider.turnstile,
      );
    });

    test('classifies reCAPTCHA v2/v3 keys', () {
      expect(
        classifyCaptchaProvider('6LeIxAcTAAAAAGG-vFI1TnRWxMZNFuojJ4WifJWe'),
        CaptchaProvider.recaptcha,
      );
    });

    test('returns unknown for unrecognized key shapes', () {
      expect(classifyCaptchaProvider('testkey'), CaptchaProvider.unknown);
      expect(classifyCaptchaProvider(''), CaptchaProvider.unknown);
      expect(classifyCaptchaProvider('0xshort'), CaptchaProvider.unknown);
      expect(classifyCaptchaProvider('9xAAAAAAAAAAAAAAAAAAAA'), CaptchaProvider.unknown);
    });
  });

  group('CaptchaProviderAssets', () {
    test('Turnstile maps to Cloudflare script and widget class', () {
      expect(
        CaptchaProvider.turnstile.scriptSrc,
        contains('challenges.cloudflare.com/turnstile'),
      );
      expect(CaptchaProvider.turnstile.widgetClass, 'cf-turnstile');
    });

    test('reCAPTCHA maps to Google script and widget class', () {
      expect(
        CaptchaProvider.recaptcha.scriptSrc,
        contains('google.com/recaptcha'),
      );
      expect(CaptchaProvider.recaptcha.widgetClass, 'g-recaptcha');
    });

    test('unknown falls back to reCAPTCHA assets', () {
      expect(
        CaptchaProvider.unknown.scriptSrc,
        contains('google.com/recaptcha'),
      );
      expect(CaptchaProvider.unknown.widgetClass, 'g-recaptcha');
    });
  });
}
