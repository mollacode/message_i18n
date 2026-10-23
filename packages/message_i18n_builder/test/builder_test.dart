import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:message_i18n_builder/builder.dart';
import 'package:test/test.dart';

const valid = '''
import 'package:message_i18n/message_i18n.dart';
@MessageI18nCatalog()
const catalog = MessageCatalog(defaultLocale: 'en', supportedLocales: ['en', 'ko'],
  messages: {'save': LocalizedMessage({'en': 'Save', 'ko': '저장'})});
''';

Future<TestBuilderResult> generate(
  String source, {
  Map<String, String> extra = const {},
}) async {
  final reader = TestReaderWriter(rootPackage: 'consumer');
  await reader.testing.loadIsolateSources();
  return testBuilder(
    messageI18nBuilder(BuilderOptions.empty),
    {'consumer|lib/catalog.dart': source, ...extra},
    readerWriter: reader,
    rootPackage: 'consumer',
    flattenOutput: true,
  );
}

void main() {
  final failures = <String, String>{
    'duplicate key': valid.replaceFirst(
      "'save': LocalizedMessage",
      "'save': LocalizedMessage({'en': 'other', 'ko': '다름'}), 'save': LocalizedMessage",
    ),
    'local variable target':
        "import 'package:message_i18n/message_i18n.dart'; void f() { @MessageI18nCatalog() const local = 1; }",
    'null catalog':
        "import 'package:message_i18n/message_i18n.dart'; @MessageI18nCatalog() const catalog = null;",
    'invalid collection': valid.replaceFirst("['en', 'ko']", "[42, 'ko']"),
    'non-const': valid.replaceFirst('const catalog', 'final catalog'),
    'wrong type':
        "import 'package:message_i18n/message_i18n.dart'; @MessageI18nCatalog() const catalog = 'no';",
    'class target':
        "import 'package:message_i18n/message_i18n.dart'; @MessageI18nCatalog() class Wrong {}",
    'multiple catalogs':
        '$valid\n@MessageI18nCatalog() const another = catalog;',
    'duplicate annotation': valid.replaceFirst(
      '@MessageI18nCatalog()',
      '@MessageI18nCatalog()\n@MessageI18nCatalog()',
    ),
    'missing translation': valid.replaceFirst(", 'ko': '저장'", ''),
    'empty translation': valid.replaceFirst("'Save'", "' '"),
    'placeholder mismatch': valid.replaceFirst("'Save'", "'{name}'"),
    'duplicate locale': valid.replaceFirst(
      "['en', 'ko']",
      "['en', 'ko', 'EN']",
    ),
    'default absent': valid.replaceFirst(
      "defaultLocale: 'en'",
      "defaultLocale: 'ja'",
    ),
    'unresolved const': valid.replaceFirst("'Save'", 'undefinedWord'),
  };
  for (final entry in failures.entries) {
    test('rejects ${entry.key}', () async {
      final result = await generate(entry.value);
      expect(result.succeeded, isFalse);
      expect(result.outputs, isEmpty);
      expect(result.errors, isNotEmpty);
    });
  }
  test('unannotated catalog emits nothing', () async {
    final result = await generate(
      valid.replaceFirst('@MessageI18nCatalog()', ''),
    );
    expect(result.succeeded, isTrue);
    expect(result.outputs, isEmpty);
  });
  test('generates one standalone library', () async {
    final result = await generate(valid);
    expect(result.succeeded, isTrue);
    expect(result.outputs, [
      AssetId('consumer', 'lib/catalog.message_i18n.g.dart'),
    ]);
    final output = await result.readerWriter.readAsString(
      result.outputs.single,
    );
    expect(output, contains('abstract final class MessageKeys'));
    expect(output, contains('static const String save = "save";'));
  });

  test('rejects message key identifier collisions', () async {
    final result = await generate(
      valid.replaceFirst(
        "{'save': LocalizedMessage({'en': 'Save', 'ko': '저장'})}",
        "{'a.a': LocalizedMessage({'en': 'A', 'ko': '가'}), 'a_a': LocalizedMessage({'en': 'B', 'ko': '나'}), 'a-a': LocalizedMessage({'en': 'C', 'ko': '다'})}",
      ),
    );
    expect(result.succeeded, isFalse);
    expect(result.outputs, isEmpty);
    expect(result.errors.join('\n'), contains('MessageKeys.aA'));
    for (final key in ['a.a', 'a_a', 'a-a']) {
      expect(result.errors.join('\n'), contains(key));
    }
  });

  test(
    'rejects message keys outside the source grammar without output',
    () async {
      final result = await generate(
        valid.replaceFirst(
          "{'save': LocalizedMessage({'en': 'Save', 'ko': '저장'})}",
          r"{'App.Title': LocalizedMessage({'en': 'A', 'ko': '가'}), '123.title': LocalizedMessage({'en': 'B', 'ko': '나'}), '한국어.제목': LocalizedMessage({'en': 'C', 'ko': '다'}), 'app..title': LocalizedMessage({'en': 'D', 'ko': '라'}), 'price\$usd': LocalizedMessage({'en': 'E', 'ko': '마'})}",
        ),
      );
      expect(result.succeeded, isFalse);
      expect(result.outputs, isEmpty);
      final errors = result.errors.join('\n');
      expect(errors, contains('invalid_key'));
      for (final key in [
        'App.Title',
        '123.title',
        '한국어.제목',
        'app..title',
        r'price$usd',
      ]) {
        expect(errors, contains(key));
      }
      expect(errors, isNot(contains('MessageKeys.appTitle')));
    },
  );

  for (final key in ['class', 'hash.code']) {
    test('rejects non-declarable generated identifier from $key', () async {
      final result = await generate(valid.replaceFirst("'save'", "'$key'"));
      expect(result.succeeded, isFalse);
      expect(result.outputs, isEmpty);
      expect(result.errors.join('\n'), contains(key));
      expect(result.errors.join('\n'), contains('Cannot generate MessageKeys'));
    });
  }
  test('supports prefixed core types and imported const spread', () async {
    final result = await generate(
      '''
import 'package:message_i18n/message_i18n.dart' as i18n;
import 'words.dart';
@i18n.MessageI18nCatalog()
const catalog = i18n.MessageCatalog(defaultLocale: 'en', supportedLocales: ['en'],
  messages: {...words});
''',
      extra: {
        'consumer|lib/words.dart': '''
import 'package:message_i18n/message_i18n.dart';
const words = {'save': LocalizedMessage({'en': 'Save'})};
''',
      },
    );
    expect(result.succeeded, isTrue);
    expect(result.outputs, hasLength(1));
  });
  test('rejects duplicate keys in imported const sources', () async {
    final result = await generate(
      valid
          .replaceFirst(
            "import 'package:message_i18n/message_i18n.dart';",
            "import 'package:message_i18n/message_i18n.dart';\nimport 'bad.dart';",
          )
          .replaceFirst(
            "{'save': LocalizedMessage({'en': 'Save', 'ko': '저장'})}",
            'words',
          ),
      extra: {
        'consumer|lib/bad.dart':
            "import 'package:message_i18n/message_i18n.dart'; const words = {'save': LocalizedMessage({'en':'a','ko':'가'}), 'save': LocalizedMessage({'en':'b','ko':'나'})};",
      },
    );
    expect(result.succeeded, isFalse);
    expect(result.outputs, isEmpty);
  });
}
