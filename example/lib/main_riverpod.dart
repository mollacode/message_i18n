import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:message_i18n/message_i18n.dart';
import 'package:message_i18n_flutter/message_i18n_flutter.dart';

import 'i18n/catalog.message_i18n.g.dart';
import 'state_management_page.dart';

class MessagesState {
  const MessagesState._(this._resolver, this.revision);

  final MessageResolver _resolver;
  final int revision;

  String get locale => _resolver.locale;
  String get selected => _resolver.selected;
  String text(String key) => _resolver.text(key);
  String format(String key, Map<String, String> arguments) =>
      _resolver.format(key, arguments);
}

class MessagesController extends Notifier<MessagesState> {
  @override
  MessagesState build() =>
      MessagesState._(createMessageResolver(selected: defaultMessageLocale), 0);

  void select(String locale) {
    final resolver = state._resolver;
    resolver.select(locale);
    state = MessagesState._(resolver, state.revision + 1);
  }

  void reload() {
    final resolver = state._resolver;
    resolver.reload();
    state = MessagesState._(resolver, state.revision + 1);
  }
}

final messagesProvider = NotifierProvider<MessagesController, MessagesState>(
  MessagesController.new,
);

void main() => runApp(const ProviderScope(child: RiverpodExample()));

class RiverpodExample extends ConsumerStatefulWidget {
  const RiverpodExample({super.key});

  @override
  ConsumerState<RiverpodExample> createState() => RiverpodExampleState();
}

class RiverpodExampleState extends ConsumerState<RiverpodExample> {
  void reloadForHotReload() {
    ref.read(messagesProvider.notifier).reload();
  }

  @override
  void reassemble() {
    super.reassemble();
    reloadForHotReload();
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(messagesProvider);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: messageLocale(messages.locale),
      supportedLocales: messageLocales(supportedMessageLocales),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const RiverpodMessagesPage(depth: 0),
    );
  }
}

class RiverpodMessagesPage extends ConsumerWidget {
  const RiverpodMessagesPage({required this.depth, super.key});

  final int depth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = ref.watch(messagesProvider);
    final controller = ref.read(messagesProvider.notifier);
    return StateManagementPage(
      depth: depth,
      locale: messages.locale,
      text: messages.text,
      format: messages.format,
      select: controller.select,
      reload: controller.reload,
      nextPage: (_) => RiverpodMessagesPage(depth: depth + 1),
      dialog: (_) => const RiverpodMessagesDialog(),
    );
  }
}

class RiverpodMessagesDialog extends ConsumerWidget {
  const RiverpodMessagesDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      StateManagementDialog(text: ref.watch(messagesProvider).text);
}
