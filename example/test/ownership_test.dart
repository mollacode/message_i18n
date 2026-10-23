import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:message_i18n_flutter/message_i18n_flutter.dart';
import 'package:message_i18n_example/main_getx.dart' as gx;
import 'package:message_i18n_example/main_riverpod.dart' as rp;
import 'package:message_i18n_example/state_management_page.dart';

void main() {
  test('Riverpod publishes only after a successful selection or reload', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final first = container.read(rp.messagesProvider);
    final controller = container.read(rp.messagesProvider.notifier);

    expect(() => controller.select('en--US'), throwsFormatException);
    expect(container.read(rp.messagesProvider), same(first));

    controller.select('en-US');
    expect(container.read(rp.messagesProvider).locale, 'en');
    expect(container.read(rp.messagesProvider).revision, 1);
    controller.reload();
    expect(container.read(rp.messagesProvider).selected, 'en-US');
    expect(container.read(rp.messagesProvider).revision, 2);
  });

  test('Riverpod wrapper is a UI signal, not a historical snapshot', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final previous = container.read(rp.messagesProvider);

    container.read(rp.messagesProvider.notifier).select('en');
    final current = container.read(rp.messagesProvider);

    expect(identical(previous, current), isFalse);
    expect(previous.revision, 0);
    expect(current.revision, 1);
    expect(previous.locale, 'en');
    expect(previous.text('common.save'), 'Save');
  });

  testWidgets('Riverpod owns updates without MessageI18nScope', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: rp.RiverpodExample()));
    await tester.pumpAndSettle();
    expect(find.byType(MessageI18nScope), findsNothing);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(rp.RiverpodMessagesPage)),
      listen: false,
    );
    final controller = container.read(rp.messagesProvider.notifier);
    expect(() => controller.select('en--US'), throwsFormatException);
    await tester.pump();
    expect(find.text('저장'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('next-page')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('language-en')).last);
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsOneWidget);
    expect(
      Localizations.localeOf(
        tester.element(find.byType(StateManagementPage).last),
      ),
      const Locale('en'),
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('dialog')));
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsNWidgets(2));
    controller.select('ja');
    await tester.pumpAndSettle();
    expect(find.text('保存'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Riverpod root reassemble reloads the owned resolver', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: rp.RiverpodExample()));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(rp.RiverpodMessagesPage)),
      listen: false,
    );
    final before = container.read(rp.messagesProvider).revision;

    tester
        .state<rp.RiverpodExampleState>(find.byType(rp.RiverpodExample))
        .reloadForHotReload();
    await tester.pump();

    expect(container.read(rp.messagesProvider).revision, before + 1);
    expect(tester.takeException(), isNull);
  });

  group('GetX ownership', () {
    tearDown(Get.reset);

    testWidgets('invalid locale preserves controller and visible state', (
      tester,
    ) async {
      final controller = gx.registerMessagesController();
      await tester.pumpWidget(const gx.GetXExample());
      await tester.pumpAndSettle();
      expect(find.byType(MessageI18nScope), findsNothing);

      expect(() => controller.select('en--US'), throwsFormatException);
      await tester.pump();

      expect(controller.locale, 'ko');
      expect(controller.revision, 0);
      expect(find.text('저장'), findsOneWidget);
      expect(identical(Get.find<gx.MessagesController>(), controller), isTrue);
    });

    testWidgets('one update changes GetMaterialApp, route and dialog', (
      tester,
    ) async {
      final controller = gx.registerMessagesController();
      await tester.pumpWidget(const gx.GetXExample());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('next-page')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('language-en')).last);
      await tester.pumpAndSettle();

      expect(controller.revision, 1);
      expect(find.text('Save'), findsOneWidget);
      expect(
        Localizations.localeOf(
          tester.element(find.byType(StateManagementPage).last),
        ),
        const Locale('en'),
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Save'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('dialog')));
      await tester.pumpAndSettle();
      expect(find.text('Save'), findsNWidgets(2));
      controller.select('ja');
      await tester.pumpAndSettle();
      expect(controller.revision, 2);
      expect(find.text('保存'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('rapid selection has no async frame leak', (tester) async {
      final controller = gx.registerMessagesController();
      await tester.pumpWidget(const gx.GetXExample());
      await tester.pumpAndSettle();

      for (var i = 0; i < 12; i++) {
        for (final locale in ['en', 'ko', 'ja', 'ja']) {
          controller.select(locale);
        }
      }
      await tester.pumpAndSettle();

      expect(controller.revision, 48);
      expect(controller.locale, 'ja');
      expect(find.text('保存'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('GetX root reassemble reloads without locale selection', (
      tester,
    ) async {
      final controller = gx.registerMessagesController();
      await tester.pumpWidget(const gx.GetXExample());
      await tester.pumpAndSettle();
      final before = controller.revision;

      tester
          .state<gx.GetXExampleState>(find.byType(gx.GetXExample))
          .reloadForHotReload();
      await tester.pump();

      expect(controller.revision, before + 1);
      expect(controller.selected, 'ko');
      expect(tester.takeException(), isNull);
    });
  });
}
