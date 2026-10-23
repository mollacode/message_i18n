import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_i18n/message_i18n.dart';
import 'package:message_i18n_flutter/message_i18n_flutter.dart';

MessageResolver resolver({
  String selected = 'en',
  String Function()? revision,
  void Function()? loaded,
}) => MessageResolver.fromLoader(
  selected: selected,
  loader: (locale) {
    loaded?.call();
    return GeneratedLocaleMessages(locale, {
      'save': '$locale${revision?.call() ?? ''}',
      'welcome': 'Hi {name}',
    });
  },
);

void main() {
  test(
    'script and region conversion preserves metadata; invalid segments rejected',
    () {
      for (final entry in <String, Locale>{
        'en': const Locale('en'),
        'ko_KR': const Locale('ko', 'KR'),
        'zh-Hant': const Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hant',
        ),
        'zh-Hant-TW': const Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hant',
          countryCode: 'TW',
        ),
        'sr-Latn-RS': const Locale.fromSubtags(
          languageCode: 'sr',
          scriptCode: 'Latn',
          countryCode: 'RS',
        ),
        'es-419': const Locale.fromSubtags(
          languageCode: 'es',
          countryCode: '419',
        ),
      }.entries) {
        expect(messageLocale(entry.key), entry.value);
      }
      expect(() => messageLocale('en-US-extra'), throwsFormatException);
      expect(messageLocales(['ko', 'en']), [
        const Locale('ko'),
        const Locale('en'),
      ]);
    },
  );
  testWidgets('outside scope is explicit and maybeOf returns null', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (context) {
            expect(MessageI18nScope.maybeOf(context), isNull);
            expect(() => context.tr('save'), throwsFlutterError);
            expect(() => context.reloadMessages(), throwsFlutterError);
            return const SizedBox();
          },
        ),
      ),
    );
  });
  testWidgets(
    'shared identity, same-locale reload, replacement, removal and parameter formatting',
    (tester) async {
      var loads = 0;
      var revision = '';
      final first = resolver(loaded: () => loads++, revision: () => revision);
      var builds = 0;
      final child = Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (context) {
            builds++;
            return Column(
              children: [
                Text(context.tr('save')),
                Text(context.format('welcome', {'name': 'Dart'})),
                IdentityProbe(
                  onResolver: (value) => expect(
                    identical(value, MessageI18nScope.of(context)),
                    isTrue,
                  ),
                ),
              ],
            );
          },
        ),
      );
      await tester.pumpWidget(MessageI18nScope(resolver: first, child: child));
      expect(loads, 1);
      expect(find.text('Hi Dart'), findsOneWidget);
      revision = ' revised';
      first.reload();
      await tester.pump();
      expect(find.text('en revised'), findsOneWidget);
      expect(builds, 2);
      final second = resolver(selected: 'ko');
      await tester.pumpWidget(MessageI18nScope(resolver: second, child: child));
      expect(find.text('ko'), findsOneWidget);
      final afterReplace = builds;
      first.select('ja');
      await tester.pump();
      expect(builds, afterReplace);
      second.select('en');
      await tester.pump();
      expect(find.text('en'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      second.reload();
      first.reload();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(second.text('save'), 'en');
    },
  );
  testWidgets(
    'commands do not subscribe their caller; dependent widget still updates',
    (tester) async {
      final value = resolver();
      var commandBuilds = 0;
      late BuildContext commandContext;
      final child = Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            Builder(
              builder: (context) {
                commandContext = context;
                commandBuilds++;
                return const SizedBox();
              },
            ),
            Builder(builder: (context) => Text(context.tr('save'))),
          ],
        ),
      );
      await tester.pumpWidget(MessageI18nScope(resolver: value, child: child));
      commandContext.updateLocale('ko');
      await tester.pump();
      expect(find.text('ko'), findsOneWidget);
      expect(commandBuilds, 1);
      commandContext.reloadMessages();
      await tester.pump();
      expect(commandBuilds, 1);
    },
  );
  testWidgets('format diagnoses missing and extra arguments through context', (
    tester,
  ) async {
    final issues = <MessageDiagnostic>[];
    final messages = MessageResolver.fromLoader(
      selected: 'en',
      onDiagnostic: issues.add,
      loader: (_) => GeneratedLocaleMessages('en', {'welcome': 'Hi {name}'}),
    );
    await tester.pumpWidget(
      MessageI18nScope(
        resolver: messages,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) =>
                Text(context.format('welcome', {'extra': 'unused'})),
          ),
        ),
      ),
    );
    expect(find.text('Hi {name}'), findsOneWidget);
    expect(issues.map((i) => i.code), ['missing_argument', 'extra_argument']);
  });
  testWidgets('initState cache is stale; dependency-based cache refreshes', (
    tester,
  ) async {
    final messages = resolver();
    await tester.pumpWidget(
      MessageI18nScope(
        resolver: messages,
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: CacheExample(),
        ),
      ),
    );
    messages.select('ko');
    await tester.pump();
    expect(find.text('stale:en current:ko'), findsOneWidget);
  });
  for (final maintain in [true, false]) {
    testWidgets(
      'route stack and MaterialApp metadata maintainState=$maintain',
      (tester) async {
        final value = resolver();
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MessageI18nScope(
            resolver: value,
            child: Builder(
              builder: (context) => MaterialApp(
                navigatorKey: navigator,
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                locale: messageLocale(context.i18n.locale),
                supportedLocales: messageLocales(['en', 'ko']),
                home: const RoutePage(label: 'home'),
              ),
            ),
          ),
        );
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            maintainState: maintain,
            builder: (_) => const RoutePage(label: 'A'),
          ),
        );
        await tester.pumpAndSettle();
        navigator.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => const RoutePage(label: 'B')),
        );
        await tester.pumpAndSettle();
        final context = tester.element(find.byKey(const ValueKey('B')));
        context.updateLocale('ko');
        await tester.pumpAndSettle();
        expect(find.text('B:ko'), findsOneWidget);
        expect(
          tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
          const Locale('ko'),
        );
        expect(
          tester.widget<MaterialApp>(find.byType(MaterialApp)).supportedLocales,
          [const Locale('en'), const Locale('ko')],
        );
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        expect(find.text('A:ko'), findsOneWidget);
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const RoutePage(label: 'new'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('new:ko'), findsOneWidget);
      },
    );
  }
  testWidgets(
    'nested navigator, dialog, bottom sheet and overlay share root locale',
    (tester) async {
      final value = resolver();
      final nested = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MessageI18nScope(
          resolver: value,
          child: MaterialApp(
            home: Scaffold(
              body: Navigator(
                key: nested,
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (_) => const RoutePage(label: 'nested'),
                ),
              ),
            ),
          ),
        ),
      );
      nested.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const RoutePage(label: 'nestedB'),
        ),
      );
      await tester.pumpAndSettle();
      var context = tester.element(find.byKey(const ValueKey('nestedB')));
      showDialog<void>(
        context: context,
        builder: (context) =>
            AlertDialog(content: Text('dialog:${context.tr('save')}')),
      );
      await tester.pumpAndSettle();
      value.select('ko');
      await tester.pumpAndSettle();
      expect(find.text('dialog:ko'), findsOneWidget);
      Navigator.of(tester.element(find.byType(AlertDialog))).pop();
      await tester.pumpAndSettle();
      nested.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('nested:ko'), findsOneWidget);
      context = tester.element(find.byKey(const ValueKey('nested')));
      showModalBottomSheet<void>(
        context: context,
        builder: (context) => Text('sheet:${context.tr('save')}'),
      );
      await tester.pumpAndSettle();
      value.select('en');
      await tester.pumpAndSettle();
      expect(find.text('sheet:en'), findsOneWidget);
      Navigator.of(tester.element(find.text('sheet:en'))).pop();
      await tester.pumpAndSettle();
      final entry = OverlayEntry(
        builder: (context) => Positioned(
          top: 0,
          left: 0,
          child: Text('overlay:${context.tr('save')}'),
        ),
      );
      Overlay.of(context).insert(entry);
      await tester.pump();
      value.select('ko');
      await tester.pump();
      expect(find.text('overlay:ko'), findsOneWidget);
      entry.remove();
      entry.dispose();
    },
  );
}

class IdentityProbe extends StatelessWidget {
  const IdentityProbe({super.key, required this.onResolver});
  final void Function(MessageResolver) onResolver;
  @override
  Widget build(BuildContext context) {
    onResolver(context.i18n);
    return const SizedBox();
  }
}

class RoutePage extends StatelessWidget {
  const RoutePage({super.key, required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Text('$label:${context.tr('save')}', key: ValueKey(label)),
  );
}

// Deliberately broken initState cache beside the supported dependency pattern.
class CacheExample extends StatefulWidget {
  const CacheExample({super.key});
  @override
  State<CacheExample> createState() => _CacheExampleState();
}

class _CacheExampleState extends State<CacheExample> {
  late String stale;
  late String current;
  @override
  void initState() {
    super.initState();
    stale = MessageI18nScope.read(context).text('save');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    current = context.tr('save');
  }

  @override
  Widget build(BuildContext context) => Text('stale:$stale current:$current');
}
