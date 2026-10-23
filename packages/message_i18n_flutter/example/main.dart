import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:message_i18n/message_i18n.dart';
import 'package:message_i18n_flutter/message_i18n_flutter.dart';

const _supportedLocales = ['en', 'ko'];

GeneratedLocaleMessages _loadMessages(String requestedLocale) {
  final locale = resolveLocale(requestedLocale, _supportedLocales, 'en');
  final messages = switch (locale) {
    'ko' => <String, String>{
      'title': 'message_i18n 예제',
      'greeting': '안녕하세요, {name}님.',
      'switch': 'English',
    },
    _ => <String, String>{
      'title': 'message_i18n example',
      'greeting': 'Hello, {name}.',
      'switch': '한국어',
    },
  };
  return GeneratedLocaleMessages(locale, messages);
}

void main() {
  final resolver = MessageResolver.fromLoader(
    selected: 'en',
    loader: _loadMessages,
  );
  runApp(MessageI18nScope(resolver: resolver, child: const ExampleApp()));
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    final resolver = context.i18n;
    return MaterialApp(
      locale: messageLocale(resolver.locale),
      supportedLocales: messageLocales(_supportedLocales),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const ExampleHome(),
    );
  }
}

class ExampleHome extends StatelessWidget {
  const ExampleHome({super.key});

  @override
  Widget build(BuildContext context) {
    final nextLocale = context.i18n.locale == 'en' ? 'ko' : 'en';
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('title'))),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.format('greeting', {'name': 'Dart'})),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.updateLocale(nextLocale),
              child: Text(context.tr('switch')),
            ),
          ],
        ),
      ),
    );
  }
}
