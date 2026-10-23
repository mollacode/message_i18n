import 'package:flutter/material.dart';
import 'package:message_i18n/message_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_i18n_example/main.dart';
import 'package:message_i18n_example/i18n/catalog.message_i18n.g.dart';

void main() {
  testWidgets('shared example resolver, language switch and prior route', (
    tester,
  ) async {
    final resolver = createMessageResolver(selected: 'ko');
    await tester.pumpWidget(MessageExample(resolver: resolver));
    expect(find.text('저장'), findsOneWidget);
    await tester.tap(find.text('다음 화면'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('en'));
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsOneWidget);
    expect(resolver.locale, 'en');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsOneWidget);
    await tester.tap(find.text('Reload messages'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
  test('example missing-key diagnostic hook', () {
    final diagnostics = <MessageDiagnostic>[];
    final messages = createMessageResolver(
      selected: 'ko',
      onDiagnostic: diagnostics.add,
    );
    expect(messages.text('does.not.exist'), 'does.not.exist');
    expect(diagnostics.single.code, 'missing_key');
  });
  testWidgets('long text and large text scale scroll without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MessageExample(resolver: createMessageResolver(selected: 'ja')),
    );
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -300),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
