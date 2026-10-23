import '../model/message_catalog.dart';
import '../runtime/locale_normalizer.dart';
import '../runtime/message_formatter.dart';

final _messageKey = RegExp(r'^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$');

final class ValidationCode {
  ValidationCode._();
  static const invalidLocale = 'invalid_locale';
  static const emptyLocales = 'empty_locales';
  static const duplicateLocale = 'duplicate_locale';
  static const missingDefault = 'missing_default';
  static const invalidKey = 'invalid_key';
  static const unsupportedLocale = 'unsupported_locale';
  static const emptyTranslation = 'empty_translation';
  static const missingTranslation = 'missing_translation';
  static const unsupportedPlaceholder = 'unsupported_placeholder';
  static const placeholderMismatch = 'placeholder_mismatch';
}

class ValidationIssue implements Comparable<ValidationIssue> {
  const ValidationIssue(
    this.code,
    this.message, {
    this.key = '',
    this.locale = '',
    this.severity = 'error',
  });
  final String code;
  final String message;
  final String key;
  final String locale;
  final String severity;
  @override
  int compareTo(ValidationIssue other) {
    for (final pair in [
      (severity, other.severity),
      (key, other.key),
      (locale, other.locale),
      (code, other.code),
    ]) {
      final result = pair.$1.compareTo(pair.$2);
      if (result != 0) return result;
    }
    return 0;
  }

  @override
  String toString() => '$severity $code key=$key locale=$locale: $message';
}

List<ValidationIssue> validateCatalog(MessageCatalog catalog) {
  final issues = <ValidationIssue>[];
  String? normalized(String value, {String key = ''}) {
    try {
      return normalizeLocale(value);
    } on FormatException {
      issues.add(
        ValidationIssue(
          ValidationCode.invalidLocale,
          'Unsupported locale syntax',
          key: key,
          locale: value,
        ),
      );
      return null;
    }
  }

  final locales = <String>{};
  if (catalog.supportedLocales.isEmpty) {
    issues.add(
      const ValidationIssue(
        ValidationCode.emptyLocales,
        'At least one supported locale is required',
      ),
    );
  }
  for (final raw in catalog.supportedLocales) {
    final locale = normalized(raw);
    if (locale != null && !locales.add(locale)) {
      issues.add(
        ValidationIssue(
          ValidationCode.duplicateLocale,
          'Duplicate normalized locale',
          locale: locale,
        ),
      );
    }
  }
  final defaultLocale = normalized(catalog.defaultLocale);
  if (defaultLocale != null && !locales.contains(defaultLocale)) {
    issues.add(
      ValidationIssue(
        ValidationCode.missingDefault,
        'Default must be supported',
        locale: defaultLocale,
      ),
    );
  }
  for (final entry in catalog.messages.entries) {
    final key = entry.key;
    if (!_messageKey.hasMatch(key)) {
      issues.add(
        ValidationIssue(
          ValidationCode.invalidKey,
          r'Key must match ^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$',
          key: key,
        ),
      );
    }
    final seen = <String>{};
    Set<String>? expected;
    // Sort to make the placeholder baseline independent of map insertion order.
    for (final raw in entry.value.translations.keys.toList()..sort()) {
      final locale = normalized(raw, key: key);
      if (locale == null) continue;
      if (!seen.add(locale)) {
        issues.add(
          ValidationIssue(
            ValidationCode.duplicateLocale,
            'Duplicate translation locale',
            key: key,
            locale: locale,
          ),
        );
      }
      if (!locales.contains(locale)) {
        issues.add(
          ValidationIssue(
            ValidationCode.unsupportedLocale,
            'Translation locale is not supported',
            key: key,
            locale: locale,
          ),
        );
      }
      final value = entry.value.translations[raw]!;
      if (value.trim().isEmpty) {
        issues.add(
          ValidationIssue(
            ValidationCode.emptyTranslation,
            'Translation must not be empty',
            key: key,
            locale: locale,
          ),
        );
      }
      try {
        final names = placeholderNames(value);
        if (expected != null &&
            (expected.difference(names).isNotEmpty ||
                names.difference(expected).isNotEmpty)) {
          issues.add(
            ValidationIssue(
              ValidationCode.placeholderMismatch,
              'Placeholder names must match',
              key: key,
              locale: locale,
            ),
          );
        }
        expected ??= names;
      } on FormatException {
        issues.add(
          ValidationIssue(
            ValidationCode.unsupportedPlaceholder,
            'Only named placeholders are supported',
            key: key,
            locale: locale,
          ),
        );
      }
    }
    for (final missing in locales.difference(seen)) {
      issues.add(
        ValidationIssue(
          ValidationCode.missingTranslation,
          'Required translation is missing',
          key: key,
          locale: missing,
        ),
      );
    }
  }
  return issues..sort();
}

MessageCatalog normalizeCatalog(MessageCatalog catalog) => MessageCatalog(
  defaultLocale: normalizeLocale(catalog.defaultLocale),
  supportedLocales: catalog.supportedLocales.map(normalizeLocale).toList(),
  messages: {
    for (final e in catalog.messages.entries)
      e.key: LocalizedMessage({
        for (final t in e.value.translations.entries)
          normalizeLocale(t.key): t.value,
      }),
  },
);
