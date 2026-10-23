import 'package:flutter/material.dart';

import 'i18n/catalog.message_i18n.g.dart';

typedef MessageText = String Function(String key);
typedef MessageFormat =
    String Function(String key, Map<String, String> arguments);

class StateManagementPage extends StatelessWidget {
  const StateManagementPage({
    super.key,
    required this.depth,
    required this.locale,
    required this.text,
    required this.format,
    required this.select,
    required this.reload,
    required this.nextPage,
    required this.dialog,
  });

  final int depth;
  final String locale;
  final MessageText text;
  final MessageFormat format;
  final void Function(String locale) select;
  final VoidCallback reload;
  final WidgetBuilder nextPage;
  final WidgetBuilder dialog;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(text(MessageKeys.appTitle))),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            children: [
              for (final value in supportedMessageLocales)
                ChoiceChip(
                  key: ValueKey('language-$value'),
                  label: Text(value),
                  selected: locale == value,
                  onSelected: (_) => select(value),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            text(MessageKeys.commonSave),
            key: const ValueKey('save-message'),
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          Text(format(MessageKeys.welcomeUser, {'name': 'Dart'})),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton(
                key: const ValueKey('next-page'),
                onPressed: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute<void>(builder: nextPage)),
                child: Text(text(MessageKeys.actionNext)),
              ),
              OutlinedButton(
                key: const ValueKey('dialog'),
                onPressed: () =>
                    showDialog<void>(context: context, builder: dialog),
                child: Text(text(MessageKeys.actionDialog)),
              ),
              OutlinedButton(
                key: const ValueKey('reload'),
                onPressed: reload,
                child: Text(text(MessageKeys.actionReload)),
              ),
            ],
          ),
          Text('depth:$depth', key: const ValueKey('route-depth')),
        ],
      ),
    ),
  );
}

class StateManagementDialog extends StatelessWidget {
  const StateManagementDialog({super.key, required this.text});

  final MessageText text;

  @override
  Widget build(BuildContext context) => AlertDialog(
    content: Text(text(MessageKeys.commonSave)),
    actions: [
      TextButton(
        key: const ValueKey('close-dialog'),
        onPressed: () => Navigator.of(context).pop(),
        child: Text(text(MessageKeys.actionDialog)),
      ),
    ],
  );
}
