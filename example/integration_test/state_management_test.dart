import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:message_i18n_example/main_getx.dart' as gx;
import 'package:message_i18n_example/main_riverpod.dart' as rp;
import 'package:message_i18n_example/state_management_page.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Riverpod device flow updates route, dialog and reload', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: rp.RiverpodExample()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('language-en')));
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('next-page')));
    await tester.pumpAndSettle();
    expect(find.text('depth:1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dialog')));
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsNWidgets(2));
    await tester.tap(find.byKey(const ValueKey('close-dialog')));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(rp.RiverpodMessagesPage).last),
      listen: false,
    );
    final before = container.read(rp.messagesProvider).revision;
    await tester.tap(find.byKey(const ValueKey('reload')));
    await tester.pump();
    expect(container.read(rp.messagesProvider).revision, before + 1);
    expect(
      Localizations.localeOf(
        tester.element(find.byType(StateManagementPage).last),
      ),
      const Locale('en'),
    );
  });

  testWidgets('GetX device flow updates route, dialog and reload', (
    tester,
  ) async {
    addTearDown(Get.reset);
    final controller = gx.registerMessagesController();
    await tester.pumpWidget(const gx.GetXExample());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('language-en')));
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('next-page')));
    await tester.pumpAndSettle();
    expect(find.text('depth:1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dialog')));
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsNWidgets(2));
    await tester.tap(find.byKey(const ValueKey('close-dialog')));
    await tester.pumpAndSettle();

    final before = controller.revision;
    await tester.tap(find.byKey(const ValueKey('reload')));
    await tester.pump();
    expect(controller.revision, before + 1);
    expect(
      Localizations.localeOf(
        tester.element(find.byType(StateManagementPage).last),
      ),
      const Locale('en'),
    );
  });
}
