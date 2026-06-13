import 'package:flutter/foundation.dart';

// ── CaptchaProvider ─────────────────────────────────────────────────────────

/// CAPTCHA vendor served under the Matrix `m.login.recaptcha` UIA stage.
///
/// The protocol only carries the `public_key` (site key), not the vendor, so
/// the provider is inferred from the key's shape. [unknown] means the key
/// matched neither documented format.
enum CaptchaProvider { turnstile, recaptcha, unknown }

/// Cloudflare Turnstile site keys: a single digit, `x`, then alphanumerics
/// (e.g. `0x4AAAAAAA...`; testing keys use the `1x`/`2x`/`3x` prefixes).
final RegExp _turnstileKeyPattern = RegExp(r'^[0-3]x[A-Za-z0-9]{18,}$');

/// Google reCAPTCHA v2/v3 site keys: `6L` followed by ~38 URL-safe base64
/// characters.
final RegExp _recaptchaKeyPattern = RegExp(r'^6L[A-Za-z0-9_-]{30,}$');

/// Classifies a CAPTCHA site key by shape. Pure and side-effect free; see
/// [resolveCaptchaProvider] for the logging variant used at render time.
CaptchaProvider classifyCaptchaProvider(String siteKey) {
  if (_turnstileKeyPattern.hasMatch(siteKey)) return CaptchaProvider.turnstile;
  if (_recaptchaKeyPattern.hasMatch(siteKey)) return CaptchaProvider.recaptcha;
  return CaptchaProvider.unknown;
}

/// Like [classifyCaptchaProvider] but logs when the key shape is unrecognized,
/// so the reCAPTCHA fallback (see [CaptchaProviderAssets]) is diagnosable.
CaptchaProvider resolveCaptchaProvider(String siteKey) {
  final provider = classifyCaptchaProvider(siteKey);
  if (provider == CaptchaProvider.unknown) {
    debugPrint(
      '[Kohera] Unrecognized CAPTCHA site key shape; defaulting to reCAPTCHA',
    );
  }
  return provider;
}

extension CaptchaProviderAssets on CaptchaProvider {
  /// Widget script. [CaptchaProvider.unknown] falls back to reCAPTCHA.
  String get scriptSrc => switch (this) {
        CaptchaProvider.turnstile =>
          'https://challenges.cloudflare.com/turnstile/v0/api.js',
        _ => 'https://www.google.com/recaptcha/api.js',
      };

  /// Widget container class. [CaptchaProvider.unknown] falls back to reCAPTCHA.
  String get widgetClass => switch (this) {
        CaptchaProvider.turnstile => 'cf-turnstile',
        _ => 'g-recaptcha',
      };
}
