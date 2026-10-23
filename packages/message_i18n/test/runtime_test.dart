import 'package:message_i18n/message_i18n.dart';
import 'package:message_i18n/src/tool/validation.dart';
import 'package:test/test.dart';

const catalog = MessageCatalog(
  defaultLocale: 'ko',
  supportedLocales: ['ko', 'en', 'ja'],
  messages: {
    'save': LocalizedMessage({'ko': '저장', 'en': 'Save', 'ja': '保存'}),
    'welcome': LocalizedMessage({
      'ko': '{name}님',
      'en': 'Hi {name}',
      'ja': '{name}さん',
    }),
  },
);

void main() {
  group('invalid locale before happy path', () {
    for (final value in [
      '',
      'e',
      'en--US',
      'en-US-Latn',
      'en-US-u-ca',
      'en-variant',
      'zh-Hant-TW-more',
    ]) {
      test(
        value.isEmpty ? 'empty' : value,
        () => expect(() => normalizeLocale(value), throwsFormatException),
      );
    }
    test('canonical script, country and numeric region', () {
      for (final pair in {
        ' en_US ': 'en-US',
        'ZH_hant_tw': 'zh-Hant-TW',
        'sr_latn_rs': 'sr-Latn-RS',
        'es_419': 'es-419',
        'ko': 'ko',
      }.entries) {
        expect(normalizeLocale(pair.key), pair.value);
      }
      expect(resolveLocale('zh-Hant-TW', ['en', 'zh-Hant'], 'en'), 'zh-Hant');
      expect(resolveLocale('zh-Hant-TW', ['en', 'zh'], 'en'), 'zh');
      expect(resolveLocale('fr-FR', ['en'], 'en'), 'en');
    });
  });
  test('validator collects independent issues then recovers', () {
    const broken = MessageCatalog(
      defaultLocale: 'ja',
      supportedLocales: ['ko', 'en', 'en_US', 'en-US'],
      messages: {
        ' key ': LocalizedMessage({'ko': '', 'en': '{name}', 'fr': '{0}'}),
      },
    );
    final issues = validateCatalog(broken);
    expect(
      issues.map((i) => i.code),
      containsAll([
        'missing_default',
        'duplicate_locale',
        'invalid_key',
        'missing_translation',
        'empty_translation',
        'unsupported_locale',
        'unsupported_placeholder',
        'placeholder_mismatch',
      ]),
    );
    expect(validateCatalog(catalog), isEmpty);
    expect(catalog.messages['save']!.translations['ko'], '저장');
    expect(() => catalog.supportedLocales.add('fr'), throwsUnsupportedError);
  });
  test('validator enforces lowercase ASCII message key segments', () {
    for (final key in [
      '',
      ' key',
      'key ',
      'app title',
      'App.title',
      'app.Title',
      'APP.TITLE',
      '한국어.제목',
      'عنوان.تطبيق',
      '1app.title',
      '.app',
      '_app',
      '-app',
      'app.',
      'app..title',
      'app_-title',
      r'price$usd',
    ]) {
      final issues = validateCatalog(
        MessageCatalog(
          defaultLocale: 'en',
          supportedLocales: const ['en'],
          messages: {
            key: const LocalizedMessage({'en': 'Value'}),
          },
        ),
      );
      expect(issues, hasLength(1));
      expect(issues.single.code, ValidationCode.invalidKey);
      expect(issues.single.key, key);
      expect(
        issues.single.message,
        contains(r'^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$'),
      );
    }

    for (final key in [
      'app',
      'app.title',
      'welcome-user',
      'profile_2',
      'feature.action2-value_name',
    ]) {
      final catalog = MessageCatalog(
        defaultLocale: 'en',
        supportedLocales: const ['en', 'ko'],
        messages: {
          key: const LocalizedMessage({
            'en': 'Hello {userName}',
            'ko': '{userName}님 안녕하세요',
          }),
        },
      );
      expect(validateCatalog(catalog), isEmpty, reason: key);
    }
  });
  test('unsupported braces and repeated placeholder set', () {
    for (final value in [
      '{',
      '}',
      '{{name}}',
      '{0}',
      '{}',
      '{n, plural, one{x}}',
    ]) {
      expect(() => placeholderNames(value), throwsFormatException);
    }
    expect(placeholderNames('{name} {name} {_id}'), {'name', '_id'});
    expect(formatMessage('{name} {name}', {'name': r'$1'}), r'$1 $1');
  });
  test(
    'one factory per load, failed select preserves state, diagnostics and listeners',
    () {
      final calls = <String>[];
      final diagnostics = <MessageDiagnostic>[];
      var revision = 0;
      final resolver = MessageResolver.fromLoader(
        selected: 'ko-KR',
        onDiagnostic: diagnostics.add,
        loader: (requested) {
          final locale = resolveLocale(requested, ['ko', 'en'], 'ko');
          calls.add(locale);
          return GeneratedLocaleMessages(locale, {
            'save': '$locale:$revision',
            'welcome': '{name} {name}',
          });
        },
      );
      expect(calls, ['ko']);
      expect(resolver.text('missing'), 'missing');
      expect(diagnostics.last.code, 'missing_key');
      expect(resolver.format('welcome', {'extra': 'x'}), '{name} {name}');
      expect(
        diagnostics.map((d) => d.code),
        containsAll(['missing_argument', 'extra_argument']),
      );
      expect(resolver.format('welcome', {'name': 'Dart'}), 'Dart Dart');
      expect(() => resolver.select('en--US'), throwsFormatException);
      expect(resolver.locale, 'ko');
      expect(resolver.selected, 'ko-KR');
      var notifications = 0;
      void listener() {
        notifications++;
        expect(resolver.text('save'), '${resolver.locale}:$revision');
      }

      resolver.addListener(listener);
      resolver.addListener(listener);
      resolver.select('en-US');
      resolver.select('ko');
      revision++;
      resolver.reload();
      expect(notifications, 3);
      expect(calls, ['ko', 'en', 'ko', 'ko']);
      expect(resolver.text('save'), 'ko:1');
      resolver.removeListener(listener);
      resolver.reload();
      expect(notifications, 3);
    },
  );
  test('listener snapshot permits subscription changes', () {
    final resolver = MessageResolver.fromLoader(
      selected: 'en',
      loader: (_) => GeneratedLocaleMessages('en', {}),
    );
    var count = 0;
    late void Function() listener;
    listener = () {
      count++;
      resolver.removeListener(listener);
    };
    resolver.addListener(listener);
    resolver.reload();
    resolver.reload();
    expect(count, 1);
  });
}
