import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;

import '../model/message_catalog.dart';
import '../runtime/locale_normalizer.dart';

class ExchangeDocument {
  ExchangeDocument(
    Map<String, Map<String, String>> messages, {
    Iterable<String> locales = const [],
  }) : messages = Map.unmodifiable({
         for (final e in messages.entries)
           e.key: Map<String, String>.unmodifiable(e.value),
       }),
       locales = List.unmodifiable({
         ...locales,
         ...messages.values.expand((m) => m.keys),
       });
  final Map<String, Map<String, String>> messages;
  final List<String> locales;
}

ExchangeDocument selectTranslations(
  MessageCatalog catalog,
  List<String> locales,
) => ExchangeDocument({
  for (final key in catalog.messages.keys.toList()..sort())
    key: {
      for (final locale in locales)
        locale: catalog.messages[key]!.translations[locale]!,
    },
}, locales: locales);

String encodeJson(ExchangeDocument document) =>
    '${const JsonEncoder.withIndent('  ').convert({for (final key in document.messages.keys.toList()..sort()) key: document.messages[key]})}\n';

ExchangeDocument decodeJson(String source) {
  final Object? raw = jsonDecode(source);
  if (raw is! Map<String, dynamic>) {
    throw const FormatException('JSON must be a key-to-locale object');
  }
  final data = <String, Map<String, String>>{};
  for (final entry in raw.entries) {
    _validateKey(entry.key);
    final Object? translations = entry.value;
    if (translations is! Map<String, dynamic>) {
      throw const FormatException(
        'Translations must be locale-to-string objects',
      );
    }
    final values = <String, String>{};
    for (final translation in translations.entries) {
      final locale = normalizeLocale(translation.key);
      final Object? value = translation.value;
      if (value is! String) {
        throw const FormatException('Translation value must be a string');
      }
      if (values.containsKey(locale)) {
        throw const FormatException('Duplicate normalized locale');
      }
      values[locale] = value;
    }
    data[entry.key] = values;
  }
  return ExchangeDocument(data);
}

void _validateKey(String key) {
  if (key.isEmpty || key.trim() != key) {
    throw const FormatException('Key is empty or has surrounding whitespace');
  }
}

List<int> encodeXlsx(ExchangeDocument document) {
  final excel = Excel.createExcel();
  final sheet = excel['translations'];
  excel.setDefaultSheet('translations');
  for (final name in excel.tables.keys.toList()) {
    if (name != 'translations') excel.delete(name);
  }
  sheet.appendRow([
    TextCellValue('key'),
    ...document.locales.map(TextCellValue.new),
  ]);
  for (final key in document.messages.keys.toList()..sort()) {
    sheet.appendRow([
      TextCellValue(key),
      ...document.locales.map(
        (locale) => document.messages[key]!.containsKey(locale)
            ? TextCellValue(document.messages[key]![locale]!)
            : null,
      ),
    ]);
  }
  return excel.encode()!;
}

ExchangeDocument decodeXlsx(List<int> bytes) {
  final excel = Excel.decodeBytes(bytes);
  final sheet = excel.tables['translations'];
  if (sheet == null || sheet.rows.isEmpty) {
    throw const FormatException('Missing translations sheet or header');
  }
  String? text(Data? cell) {
    final value = cell?.value;
    if (value == null) return null;
    if (value is! TextCellValue) {
      throw const FormatException(
        'Only text cells are accepted; formulas are not evaluated',
      );
    }
    return value.value.toString();
  }

  final header = sheet.rows.first.map(text).toList();
  if (header.first != 'key') {
    throw const FormatException('First column must be key (case sensitive)');
  }
  final locales = <String>[];
  for (final raw in header.skip(1)) {
    if (raw == null || raw.isEmpty) {
      throw const FormatException('Empty locale header');
    }
    final locale = normalizeLocale(raw);
    if (locales.contains(locale)) {
      throw const FormatException('Duplicate locale header');
    }
    locales.add(locale);
  }
  final data = <String, Map<String, String>>{};
  for (final row in sheet.rows.skip(1)) {
    final values = row.map(text).toList();
    if (values.every((v) => v == null || v.isEmpty)) continue;
    final key = values.isEmpty ? '' : values.first ?? '';
    _validateKey(key);
    if (data.containsKey(key)) throw const FormatException('Duplicate key row');
    if (values.skip(header.length).any((v) => v != null && v.isNotEmpty)) {
      throw const FormatException('Data outside declared columns');
    }
    data[key] = {
      for (var i = 0; i < locales.length; i++)
        locales[i]: i + 1 < values.length ? values[i + 1] ?? '' : '',
    };
  }
  return ExchangeDocument(data, locales: locales);
}

ExchangeDocument readExchange(File file) {
  try {
    return switch (p.extension(file.path).toLowerCase()) {
      '.json' => decodeJson(file.readAsStringSync()),
      '.xlsx' => decodeXlsx(file.readAsBytesSync()),
      _ => throw const FormatException('Expected .json or .xlsx input'),
    };
  } catch (exception) {
    // Do not expose package stack traces, raw source or sensitive absolute paths.
    final reason = exception is FormatException
        ? exception.message
        : 'expected a valid key/locale/text document';
    throw FormatException('Cannot parse ${p.basename(file.path)}: $reason');
  }
}
