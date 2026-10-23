/// Supports language, optional script and optional region only.
///
/// Language is lowercased, script uses title case, and alphabetic regions are
/// uppercased. Underscores are accepted as separators. A [FormatException] is
/// thrown for empty, reordered, variant, extension, or otherwise unsupported
/// segments.
String normalizeLocale(String input) {
  final parts = input.trim().replaceAll('_', '-').split('-');
  if (!RegExp(r'^[A-Za-z]{2,3}$').hasMatch(parts.first)) {
    throw FormatException('Invalid locale language', input);
  }
  final result = <String>[parts.first.toLowerCase()];
  var index = 1;
  if (index < parts.length && RegExp(r'^[A-Za-z]{4}$').hasMatch(parts[index])) {
    final script = parts[index++].toLowerCase();
    result.add(script[0].toUpperCase() + script.substring(1));
  }
  if (index < parts.length &&
      RegExp(r'^([A-Za-z]{2}|[0-9]{3})$').hasMatch(parts[index])) {
    result.add(parts[index++].toUpperCase());
  }
  if (index != parts.length) {
    throw FormatException('Unsupported locale segment or order', input);
  }
  return result.join('-');
}

/// Selects the closest supported locale or [defaultLocale].
///
/// The normalized exact locale is tried first, followed by progressively less
/// specific forms. For example, `zh-Hant-TW` tries `zh-Hant` and then `zh`.
/// A malformed [requested] locale throws [FormatException].
String resolveLocale(
  String requested,
  List<String> supported,
  String defaultLocale,
) {
  var candidate = normalizeLocale(requested);
  while (true) {
    if (supported.contains(candidate)) return candidate;
    final separator = candidate.lastIndexOf('-');
    if (separator < 0) return defaultLocale;
    candidate = candidate.substring(0, separator);
  }
}
