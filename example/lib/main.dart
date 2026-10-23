import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:message_i18n/message_i18n.dart';
import 'package:message_i18n_flutter/message_i18n_flutter.dart';

import 'i18n/catalog.message_i18n.g.dart';
import 'message_page.dart';

void main() =>
    runApp(MessageExample(resolver: createMessageResolver(selected: 'ko-KR')));

class MessageExample extends StatefulWidget {
  const MessageExample({super.key, required this.resolver});
  final MessageResolver resolver;
  @override
  State<MessageExample> createState() => _MessageExampleState();
}

class _MessageExampleState extends State<MessageExample> {
  @override
  void reassemble() {
    super.reassemble();
    widget.resolver.reload();
  }

  @override
  Widget build(BuildContext context) =>
      MessageI18nScope(resolver: widget.resolver, child: const MessageApp());
}

class MessageApp extends StatelessWidget {
  const MessageApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    onGenerateTitle: (context) => context.tr(MessageKeys.appTitle),
    locale: messageLocale(context.i18n.locale),
    supportedLocales: messageLocales(supportedMessageLocales),
    // Consumer-owned delegates; the library does not install these.
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    home: const MessagePage(),
  );
}
