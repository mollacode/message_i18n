import 'dart:convert';
import 'dart:io';
import 'package:message_i18n/message_i18n.dart';
import 'package:message_i18n/src/tool/exchange.dart';
import 'package:message_i18n/src/tool/generation.dart';
import 'package:message_i18n/src/tool/merge.dart';
import 'package:test/test.dart';

void main() {
  const catalog = MessageCatalog(
    defaultLocale: 'ko',
    supportedLocales: ['ko', 'en', 'ja'],
    messages: {
      'escaping': LocalizedMessage({
        'ko': 'quote " slash \\ dollar \$ line\nCR\rtab\t {name}',
        'en': 'quote " slash \\ dollar \$ line\nCR\rtab\t {name}',
        'ja': 'quote " slash \\ dollar \$ line\nCR\rtab\t {name}',
      }),
      'common.save': LocalizedMessage({'ko': '저장', 'en': 'Save', 'ja': '保存'}),
      'welcome': LocalizedMessage({
        'ko': '안녕 {name}\n🌍',
        'en': 'Hi {name}\n🌍',
        'ja': 'こんにちは {name}\n🌍',
      }),
    },
  );
  test(
    'explicit golden fixtures cover locale/loader/manifest/exchange/candidate/key report',
    () {
      final outputs = <String, String>{
        for (final e in emitCatalog(catalog).entries) '${e.key}.txt': e.value,
        'single.json': encodeJson(selectTranslations(catalog, ['ko'])),
        'multi.json': encodeJson(selectTranslations(catalog, ['en', 'ko'])),
      };
      final exchange = selectTranslations(catalog, ['en', 'ko']);
      final workbook = decodeXlsx(encodeXlsx(exchange));
      outputs['xlsx-logical.json'] =
          '${const JsonEncoder.withIndent('  ').convert({
            'sheet': 'translations',
            'headers': ['key', ...workbook.locales],
            'messages': workbook.messages,
          })}\n';
      final merged = mergeDocuments(catalog, [
        decodeJson('{"added":{"en":"New"},"welcome":{"ko":"안녕 {name}"}}'),
      ]);
      outputs['merged_catalog.dart.txt'] = emitCandidate(merged.candidate);
      outputs['key-comparison.json'] =
          '${const JsonEncoder.withIndent('  ').convert(merged.comparison.toJson())}\n';
      for (final entry in outputs.entries) {
        final file = File('test/golden/${entry.key}');
        if (Platform.environment['UPDATE_GOLDENS'] == 'true') {
          file.parent.createSync(recursive: true);
          file.writeAsStringSync(entry.value);
        }
        expect(
          file.existsSync(),
          isTrue,
          reason: 'Missing golden: ${file.path}',
        );
        expect(entry.value, file.readAsStringSync(), reason: file.path);
      }
    },
  );
}
