import 'dart:convert';
import 'dart:io';
import 'package:message_i18n/message_i18n.dart';
import 'package:message_i18n/message_i18n_codegen.dart';
import 'package:message_i18n/src/tool/generation.dart';
import 'package:test/test.dart';

String _normalizeNewlines(String value) => value.replaceAll('\r\n', '\n');

void main() {
  test(
    'standalone and CLI runtime agree including escaped strings and reload',
    () async {
      final temp = Directory.systemTemp.createTempSync('standalone_');
      try {
        const unusual = 'quote " slash \\ dollar \$ newline\nemoji 😀';
        const catalog = MessageCatalog(
          defaultLocale: 'en',
          supportedLocales: ['en', 'ko'],
          messages: {
            'common.save': LocalizedMessage({'en': unusual, 'ko': '저장'}),
            'hello-user': LocalizedMessage({
              'en': 'Hi {name}',
              'ko': '{name}님',
            }),
          },
        );
        final standalone = emitStandaloneCatalog(catalog);
        expect(standalone, emitStandaloneCatalog(catalog));
        expect(standalone, isNot(contains('part of')));
        expect(standalone, isNot(contains('catalog.dart')));
        File('${temp.path}/standalone.dart').writeAsStringSync(standalone);
        final legacy = Directory('${temp.path}/legacy')..createSync();
        for (final entry in emitCatalog(catalog).entries) {
          File('${legacy.path}/${entry.key}').writeAsStringSync(entry.value);
        }
        File('${temp.path}/main.dart').writeAsStringSync('''
import 'dart:convert';
import 'standalone.dart' as a;
import 'legacy/message_loader.g.dart' as b;
void main() {
  final left = a.createMessageResolver(selected: 'en-US');
  final right = b.createMessageResolver(selected: 'en-US');
  final rows = <Object>[];
  for (final locale in ['en-US', 'ko-KR', 'fr']) {
    left.select(locale); right.select(locale);
    left.reload(); right.reload();
    rows.add([left.text(a.MessageKeys.commonSave), right.text('common.save'), left.format(a.MessageKeys.helloUser, {'name': 'Dart'}), right.format('hello-user', {'name': 'Dart'})]);
  }
  print(jsonEncode(rows));
}
''');
        final result = await Process.run(
          Platform.resolvedExecutable,
          [
            '--packages=${Directory.current.path}/.dart_tool/package_config.json',
            '${temp.path}/main.dart',
          ],
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        );
        expect(result.exitCode, 0, reason: '${result.stderr}');
        final rows = jsonDecode(result.stdout as String) as List<Object?>;
        for (final rawRow in rows) {
          final row = rawRow! as List<Object?>;
          expect(row[0], row[1]);
          expect(row[2], row[3]);
        }
        expect((rows[0]! as List<Object?>)[0], unusual);
        expect((rows[1]! as List<Object?>)[0], '저장');
        expect((rows[2]! as List<Object?>)[0], unusual);
      } finally {
        temp.deleteSync(recursive: true);
      }
    },
  );

  test('message key identifiers are deterministic', () {
    expect(messageKeyIdentifier('app.title'), 'appTitle');
    expect(messageKeyIdentifier('common_save'), 'commonSave');
    expect(messageKeyIdentifier('action-reload'), 'actionReload');
    expect(messageKeyIdentifier('profile_2'), 'profile2');

    const first = MessageCatalog(
      defaultLocale: 'en',
      supportedLocales: ['en'],
      messages: {
        'z.last': LocalizedMessage({'en': 'Last'}),
        'a.first': LocalizedMessage({'en': 'First'}),
      },
    );
    const reversed = MessageCatalog(
      defaultLocale: 'en',
      supportedLocales: ['en'],
      messages: {
        'a.first': LocalizedMessage({'en': 'First'}),
        'z.last': LocalizedMessage({'en': 'Last'}),
      },
    );
    expect(emitStandaloneCatalog(first), emitStandaloneCatalog(reversed));
  });

  test('standalone rejects collisions without invented names', () {
    const catalog = MessageCatalog(
      defaultLocale: 'en',
      supportedLocales: ['en'],
      messages: {
        'a.a': LocalizedMessage({'en': 'dot'}),
        'a_a': LocalizedMessage({'en': 'underscore'}),
        'a-a': LocalizedMessage({'en': 'dash'}),
      },
    );
    expect(
      () => emitStandaloneCatalog(catalog),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('MessageKeys.aA'),
            contains('"a.a"'),
            contains('"a_a"'),
            contains('"a-a"'),
            isNot(contains('aA2')),
          ),
        ),
      ),
    );
  });

  test('standalone rejects reserved and invalid identifiers', () {
    for (final key in ['class', 'hash.code']) {
      final catalog = MessageCatalog(
        defaultLocale: 'en',
        supportedLocales: const ['en'],
        messages: {
          key: const LocalizedMessage({'en': 'value'}),
        },
      );
      expect(
        () => emitStandaloneCatalog(catalog),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains(key),
          ),
        ),
      );
    }
  });

  test('invalid and collision diagnostics are complete and deterministic', () {
    MessageCatalog catalog(List<String> keys) => MessageCatalog(
      defaultLocale: 'en',
      supportedLocales: const ['en'],
      messages: {
        for (final key in keys) key: const LocalizedMessage({'en': 'value'}),
      },
    );
    String diagnostic(List<String> keys) {
      try {
        emitStandaloneCatalog(catalog(keys));
        fail('generation unexpectedly succeeded');
      } on FormatException catch (error) {
        return error.message;
      }
    }

    final forward = diagnostic(['class', 'a_a', 'a.a']);
    final reversed = diagnostic(['a.a', 'a_a', 'class']);
    expect(forward, reversed);
    expect(forward, contains('"class"'));
    expect(forward, contains('MessageKeys.aA'));
    expect(forward, contains('"a.a"'));
    expect(forward, contains('"a_a"'));
  });

  test('multiple generated libraries use import-prefixed MessageKeys', () async {
    final temp = Directory.systemTemp.createTempSync('message_keys_prefix_');
    try {
      const first = MessageCatalog(
        defaultLocale: 'en',
        supportedLocales: ['en'],
        messages: {
          'screen.title': LocalizedMessage({'en': 'Account'}),
        },
      );
      const second = MessageCatalog(
        defaultLocale: 'en',
        supportedLocales: ['en'],
        messages: {
          'screen.title': LocalizedMessage({'en': 'Checkout'}),
        },
      );
      File(
        '${temp.path}/account.dart',
      ).writeAsStringSync(emitStandaloneCatalog(first));
      File(
        '${temp.path}/checkout.dart',
      ).writeAsStringSync(emitStandaloneCatalog(second));
      File('${temp.path}/main.dart').writeAsStringSync('''
import 'account.dart' as account;
import 'checkout.dart' as checkout;
void main() {
  final a = account.createMessageResolver(selected: 'en');
  final b = checkout.createMessageResolver(selected: 'en');
  print(a.text(account.MessageKeys.screenTitle));
  print(b.text(checkout.MessageKeys.screenTitle));
}
''');
      final result = await Process.run(
        Platform.resolvedExecutable,
        [
          '--packages=${Directory.current.path}/.dart_tool/package_config.json',
          '${temp.path}/main.dart',
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(
        _normalizeNewlines((result.stdout as String).trim()),
        'Account\nCheckout',
      );
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

  test('removed generated key makes a stale constant reference fail', () async {
    final temp = Directory.systemTemp.createTempSync('message_keys_stale_');
    try {
      MessageCatalog catalog(String key) => MessageCatalog(
        defaultLocale: 'en',
        supportedLocales: const ['en'],
        messages: {
          key: const LocalizedMessage({'en': 'Title'}),
        },
      );
      final generated = File('${temp.path}/messages.dart')
        ..writeAsStringSync(emitStandaloneCatalog(catalog('app.title')));
      File('${temp.path}/main.dart').writeAsStringSync('''
import 'messages.dart';
void main() => print(createMessageResolver(selected: 'en').text(MessageKeys.appTitle));
''');
      Future<ProcessResult> run() => Process.run(
        Platform.resolvedExecutable,
        [
          '--packages=${Directory.current.path}/.dart_tool/package_config.json',
          '${temp.path}/main.dart',
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      expect((await run()).exitCode, 0);
      generated.writeAsStringSync(
        emitStandaloneCatalog(catalog('app.heading')),
      );
      final stale = await run();
      expect(stale.exitCode, isNot(0));
      expect('${stale.stderr}', contains('appTitle'));
    } finally {
      temp.deleteSync(recursive: true);
    }
  });
}
