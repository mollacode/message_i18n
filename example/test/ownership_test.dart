import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:message_i18n/message_i18n.dart';
import 'package:message_i18n_flutter/message_i18n_flutter.dart';

void main() {
  testWidgets('Riverpod owns exactly the resolver passed to Scope', (
    tester,
  ) async {
    var loads = 0;
    final provider = Provider<MessageResolver>(
      (ref) => MessageResolver.fromLoader(
        selected: 'en',
        loader: (locale) {
          loads++;
          return GeneratedLocaleMessages(locale, {'save': locale});
        },
      ),
    );
    MessageResolver? owned;
    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(
          builder: (context, ref, _) {
            owned = ref.watch(provider);
            return MessageI18nScope(
              resolver: owned!,
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Builder(
                  builder: (context) {
                    expect(identical(context.i18n, owned), isTrue);
                    return Text(context.tr('save'));
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
    expect(loads, 1);
    owned!.select('ko');
    await tester.pump();
    expect(find.text('ko'), findsOneWidget);
    expect(loads, 2);
  });
  testWidgets(
    'GetX owns exactly the resolver passed to Scope without String.tr collision',
    (tester) async {
      var loads = 0;
      final owned = Get.put(
        MessageResolver.fromLoader(
          selected: 'en',
          loader: (locale) {
            loads++;
            return GeneratedLocaleMessages(locale, {'save': locale});
          },
        ),
      );
      addTearDown(Get.reset);
      await tester.pumpWidget(
        MessageI18nScope(
          resolver: Get.find<MessageResolver>(),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder: (context) {
                expect(identical(context.i18n, owned), isTrue);
                return Text(context.tr('save'));
              },
            ),
          ),
        ),
      );
      expect(loads, 1);
      owned.select('ja');
      await tester.pump();
      expect(find.text('ja'), findsOneWidget);
      expect(loads, 2);
    },
  );
}
