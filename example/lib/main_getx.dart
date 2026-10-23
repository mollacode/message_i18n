import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:message_i18n/message_i18n.dart';
import 'package:message_i18n_flutter/message_i18n_flutter.dart';

import 'i18n/catalog.message_i18n.g.dart';
import 'state_management_page.dart';

class MessagesController extends GetxController {
  final MessageResolver _resolver = createMessageResolver(
    selected: defaultMessageLocale,
  );

  int revision = 0;
  String get locale => _resolver.locale;
  String get selected => _resolver.selected;
  String text(String key) => _resolver.text(key);
  String format(String key, Map<String, String> arguments) =>
      _resolver.format(key, arguments);

  void select(String locale) {
    _resolver.select(locale);
    Get.locale = messageLocale(_resolver.locale);
    revision++;
    update();
  }

  void reload() {
    _resolver.reload();
    revision++;
    update();
  }
}

MessagesController registerMessagesController() =>
    Get.put(MessagesController(), permanent: true);

void main() {
  registerMessagesController();
  runApp(const GetXExample());
}

class GetXExample extends StatefulWidget {
  const GetXExample({super.key});

  @override
  State<GetXExample> createState() => GetXExampleState();
}

class GetXExampleState extends State<GetXExample> {
  void reloadForHotReload() {
    Get.find<MessagesController>().reload();
  }

  @override
  void reassemble() {
    super.reassemble();
    reloadForHotReload();
  }

  @override
  Widget build(BuildContext context) => GetBuilder<MessagesController>(
    builder: (messages) => GetMaterialApp(
      debugShowCheckedModeBanner: false,
      locale: messageLocale(messages.locale),
      supportedLocales: messageLocales(supportedMessageLocales),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const GetXMessagesPage(depth: 0),
    ),
  );
}

class GetXMessagesPage extends StatelessWidget {
  const GetXMessagesPage({required this.depth, super.key});

  final int depth;

  @override
  Widget build(BuildContext context) => GetBuilder<MessagesController>(
    builder: (messages) => StateManagementPage(
      depth: depth,
      locale: messages.locale,
      text: messages.text,
      format: messages.format,
      select: messages.select,
      reload: messages.reload,
      nextPage: (_) => GetXMessagesPage(depth: depth + 1),
      dialog: (_) => const GetXMessagesDialog(),
    ),
  );
}

class GetXMessagesDialog extends StatelessWidget {
  const GetXMessagesDialog({super.key});

  @override
  Widget build(BuildContext context) => GetBuilder<MessagesController>(
    builder: (messages) => StateManagementDialog(text: messages.text),
  );
}
