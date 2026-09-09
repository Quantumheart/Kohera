/// How strong a candidate password is, as reported by [assessPassword].
enum PasswordStrength { empty, weak, fair, good, strong }

/// The result of grading a candidate password.
class PasswordAssessment {
  const PasswordAssessment({
    required this.strength,
    required this.score,
    required this.label,
    required this.suggestions,
  });

  final PasswordStrength strength;

  /// Normalised strength between 0.0 and 1.0, for progress indicators.
  final double score;

  /// Short human-readable name for [strength].
  final String label;

  /// Ordered, actionable ways to make the password stronger.
  final List<String> suggestions;

  bool get meetsMinimum => strength.index >= PasswordStrength.fair.index;
}

const int kMinimumPasswordLength = 8;

const Set<String> _commonPasswords = {
  '123456',
  '12345678',
  '123456789',
  'password',
  'password1',
  'password123',
  'qwerty',
  'qwerty123',
  'abc123',
  'letmein',
  'iloveyou',
  'admin',
  'welcome',
  'monkey',
  'dragon',
  'football',
  'baseball',
  'sunshine',
  'princess',
  'matrix',
  'changeme',
};

final RegExp _lowercase = RegExp('[a-z]');
final RegExp _uppercase = RegExp('[A-Z]');
final RegExp _digit = RegExp('[0-9]');
final RegExp _symbol = RegExp('[^A-Za-z0-9]');
final RegExp _repeated = RegExp(r'(.)\1{2,}');

/// Grades [password] and explains how to improve it.
///
/// Deliberately dependency-free and deterministic so the same verdict can be
/// asserted in tests and rendered in the registration form.
PasswordAssessment assessPassword(String password) {
  if (password.isEmpty) {
    return const PasswordAssessment(
      strength: PasswordStrength.empty,
      score: 0,
      label: 'Empty',
      suggestions: ['Use at least $kMinimumPasswordLength characters'],
    );
  }

  final suggestions = <String>[];

  if (password.length < kMinimumPasswordLength) {
    suggestions.add('Use at least $kMinimumPasswordLength characters');
  } else if (password.length < 12) {
    suggestions.add('Longer passwords are much harder to guess');
  }

  final hasLower = _lowercase.hasMatch(password);
  final hasUpper = _uppercase.hasMatch(password);
  final hasDigit = _digit.hasMatch(password);
  final hasSymbol = _symbol.hasMatch(password);

  if (!hasLower || !hasUpper) suggestions.add('Mix upper and lower case');
  if (!hasDigit) suggestions.add('Add a number');
  if (!hasSymbol) suggestions.add('Add a symbol');

  final isCommon = _commonPasswords.contains(password.toLowerCase());
  if (isCommon) suggestions.add('Avoid common passwords');

  final hasRun = _repeated.hasMatch(password);
  if (hasRun) suggestions.add('Avoid repeated characters');

  var points = 0;
  if (password.length >= kMinimumPasswordLength) points += 1;
  if (password.length >= 12) points += 1;
  if (password.length >= 16) points += 1;

  final classes = [hasLower, hasUpper, hasDigit, hasSymbol]
      .where((present) => present)
      .length;
  if (classes >= 2) points += 1;
  if (classes >= 3) points += 1;
  if (classes == 4) points += 1;

  if (hasRun) points -= 1;
  if (isCommon) points = 0;
  if (password.length < kMinimumPasswordLength) points = points.clamp(0, 1);

  final strength = switch (points.clamp(0, 6)) {
    <= 1 => PasswordStrength.weak,
    2 || 3 => PasswordStrength.fair,
    4 || 5 => PasswordStrength.good,
    _ => PasswordStrength.strong,
  };

  return PasswordAssessment(
    strength: strength,
    score: switch (strength) {
      PasswordStrength.empty => 0,
      PasswordStrength.weak => 0.25,
      PasswordStrength.fair => 0.5,
      PasswordStrength.good => 0.75,
      PasswordStrength.strong => 1,
    },
    label: switch (strength) {
      PasswordStrength.empty => 'Empty',
      PasswordStrength.weak => 'Weak',
      PasswordStrength.fair => 'Fair',
      PasswordStrength.good => 'Good',
      PasswordStrength.strong => 'Strong',
    },
    suggestions: List.unmodifiable(suggestions),
  );
}
