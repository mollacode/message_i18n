import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:message_i18n_example/main.dart';
import 'package:message_i18n_example/i18n/catalog.message_i18n.g.dart';

/// Test-only VM extension reads actual mounted Text widgets after reassemble.
void main() {
  final resolver = createMessageResolver(selected: 'ko');
  registerExtension('ext.message_i18n.snapshot', (_, parameters) async {
    final texts = <String>[];
    String? save;
    List<String>? supported;
    void visit(Element element) {
      final widget = element.widget;
      if (widget is Text && widget.data != null) {
        texts.add(widget.data!);
        if (widget.key == const ValueKey('save-message')) save = widget.data;
      }
      if (widget is MaterialApp) {
        supported = widget.supportedLocales
            .map((l) => l.toLanguageTag())
            .toList();
      }
      element.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
    return ServiceExtensionResponse.result(
      jsonEncode({
        'save': save,
        'resolvedText': resolver.text(MessageKeys.commonSave),
        'directText': loadGeneratedMessages(
          'ko',
        ).messages[MessageKeys.commonSave],
        'texts': texts,
        'selected': resolver.selected,
        'identity': identityHashCode(resolver),
        'supported': supported,
      }),
    );
  });
  registerExtension('ext.message_i18n.select', (_, parameters) async {
    resolver.select(parameters['locale']!);
    return ServiceExtensionResponse.result('{}');
  });
  runApp(MessageExample(resolver: resolver));
}
