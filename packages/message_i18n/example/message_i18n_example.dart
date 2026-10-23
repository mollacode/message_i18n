import 'package:message_i18n/message_i18n.dart';

const _supportedLocales = ['en', 'ko'];

GeneratedLocaleMessages _loadMessages(String requestedLocale) {
  final locale = resolveLocale(requestedLocale, _supportedLocales, 'en');
  final messages = switch (locale) {
    'ko' => <String, String>{'greeting': '안녕하세요, {name}님.', 'language': '한국어'},
    _ => <String, String>{'greeting': 'Hello, {name}.', 'language': 'English'},
  };
  return GeneratedLocaleMessages(locale, messages);
}

void main() {
  final diagnostics = <MessageDiagnostic>[];
  final resolver = MessageResolver.fromLoader(
    selected: 'en',
    loader: _loadMessages,
    onDiagnostic: diagnostics.add,
  );

  print(resolver.format('greeting', {'name': 'Dart'}));

  resolver.select('ko-KR');
  print(resolver.format('greeting', {'name': 'Dart'}));

  resolver.text('missing.key');
  assert(resolver.locale == 'ko');
  assert(diagnostics.single.code == 'missing_key');
}
