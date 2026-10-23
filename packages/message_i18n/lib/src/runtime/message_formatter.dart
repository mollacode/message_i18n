final _placeholder = RegExp(r'\{([A-Za-z_][A-Za-z0-9_]*)\}');

/// Returns the unique named placeholders found in [value].
///
/// Supported placeholders use the form `{name}`. A [FormatException] is thrown
/// when unmatched or unsupported braces remain after parsing.
Set<String> placeholderNames(String value) {
  final remaining = value.replaceAll(_placeholder, '');
  if (remaining.contains('{') || remaining.contains('}')) {
    throw const FormatException('Unsupported placeholder syntax');
  }
  return _placeholder.allMatches(value).map((m) => m[1]!).toSet();
}

/// Replaces supported placeholders with matching values from [arguments].
///
/// A placeholder without a matching argument is preserved verbatim. Extra
/// arguments have no effect. Call [placeholderNames] first when syntax must be
/// validated or missing and extra arguments must be diagnosed.
String formatMessage(String value, Map<String, String> arguments) =>
    value.replaceAllMapped(
      _placeholder,
      (match) => arguments[match[1]] ?? match[0]!,
    );

/// Describes a non-fatal runtime lookup or formatting problem.
class MessageDiagnostic {
  /// Creates a diagnostic for [key] in the active [locale].
  const MessageDiagnostic({
    required this.code,
    required this.key,
    required this.locale,
  });

  /// Stable machine-readable diagnostic code.
  final String code;

  /// Message key involved in the diagnostic.
  final String key;

  /// Resolved locale active when the diagnostic occurred.
  final String locale;
}

/// Receives non-fatal diagnostics emitted by a message resolver.
typedef MessageDiagnosticCallback = void Function(MessageDiagnostic diagnostic);
