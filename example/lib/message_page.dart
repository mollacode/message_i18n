import 'package:flutter/material.dart';
import 'package:message_i18n_flutter/message_i18n_flutter.dart';
import 'i18n/catalog.message_i18n.g.dart';

class MessagePage extends StatelessWidget {
  const MessagePage({super.key, this.depth = 0});
  final int depth;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.tr(MessageKeys.appTitle))),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            children: [
              for (final locale in supportedMessageLocales)
                ChoiceChip(
                  label: Text(locale),
                  selected: context.i18n.locale == locale,
                  onSelected: (_) => context.updateLocale(locale),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            context.tr(MessageKeys.commonSave),
            key: const ValueKey('save-message'),
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          Text(context.format(MessageKeys.welcomeUser, {'name': 'Dart'})),
          // Raw strings remain supported for dynamic keys and migration.
          Text(context.tr('sample.multiline')),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MessagePage(depth: depth + 1),
                  ),
                ),
                child: Text(context.tr(MessageKeys.actionNext)),
              ),
              OutlinedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    content: Text(context.tr(MessageKeys.commonSave)),
                  ),
                ),
                child: Text(context.tr(MessageKeys.actionDialog)),
              ),
              OutlinedButton(
                onPressed: context.reloadMessages,
                child: Text(context.tr(MessageKeys.actionReload)),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
