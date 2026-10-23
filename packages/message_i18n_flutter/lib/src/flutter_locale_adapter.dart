import 'package:flutter/widgets.dart';
import 'package:message_i18n/message_i18n.dart';

/// Converts a supported message locale to a Flutter [Locale].
///
/// Language, optional script, and optional region are preserved. Unsupported
/// segments throw [FormatException] through the core locale normalizer.
Locale messageLocale(String locale) {
  final parts = normalizeLocale(locale).split('-');
  final script = parts.length > 1 && parts[1].length == 4 ? parts[1] : null;
  final regionIndex = script == null ? 1 : 2;
  return Locale.fromSubtags(
    languageCode: parts.first,
    scriptCode: script,
    countryCode: parts.length > regionIndex ? parts[regionIndex] : null,
  );
}

/// Converts [locales] to an unmodifiable Flutter locale list in input order.
List<Locale> messageLocales(Iterable<String> locales) =>
    List.unmodifiable(locales.map(messageLocale));
