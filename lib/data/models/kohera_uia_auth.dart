/// SDK-free User-Interactive Auth (UIA) payload for registration stages.
library;

class KoheraUiaAuth {
  const KoheraUiaAuth({required this.type, this.session, this.params = const {}});

  /// The UIA stage type, e.g. `m.login.dummy`.
  final String type;

  /// The UIA session id shared across stages.
  final String? session;

  /// Stage-specific fields, e.g. `response` for `m.login.recaptcha`.
  final Map<String, Object?> params;
}

// ── UIA stage types ────────────────────────────────────────

const kUiaDummy = 'm.login.dummy';
const kUiaTerms = 'm.login.terms';
const kUiaRecaptcha = 'm.login.recaptcha';
const kUiaEmailIdentity = 'm.login.email.identity';
const kUiaMsisdn = 'm.login.msisdn';
const kUiaRegistrationToken = 'm.login.registration_token';
