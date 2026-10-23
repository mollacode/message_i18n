# message_i18n

**English** | [한국어](https://github.com/mollacode/message_i18n/blob/main/README.ko.md)

A message-centered localization library for Dart and Flutter. Keep every translation of a message together in a const Dart catalog, generate a standalone runtime, and exchange JSON or Excel files with translators.

```dart
// Author translations together.
'common.save': LocalizedMessage({'ko': '저장', 'en': 'Save', 'ja': '保存'})

// Read them in Flutter.
Text(context.tr(MessageKeys.commonSave));
Text(context.format(MessageKeys.welcomeUser, {'name': 'Dart'}));
Text(context.tr('common.save')); // Raw strings are also supported.

// Change the language for subscribed widgets.
context.updateLocale('en-US');
```

Use `message_i18n` for the pure Dart runtime and authoring tools, and add `message_i18n_flutter` when you need Flutter integration. Neither package contains native platform code.

## Contents

- [Why message-centered catalogs?](#why-message-centered-catalogs)
- [Packages and requirements](#packages-and-requirements)
- [Quick start](#quick-start)
- [Flutter setup](#flutter-setup)
- [Runtime API and locale behavior](#runtime-api-and-locale-behavior)
- [State management and ownership](#state-management-and-ownership)
- [Authoring and code generation](#authoring-and-code-generation)
- [CLI reference](#cli-reference)
- [Translation workflow](#translation-workflow)
- [Generated files and recovery](#generated-files-and-recovery)
- [Watch and hot reload](#watch-and-hot-reload)
- [Troubleshooting](#troubleshooting)
- [CI integration](#ci-integration)
- [Scope and limitations](#scope-and-limitations)
- [License](#license)
- [README references](#readme-references)

## Why message-centered catalogs?

A message is easier to review when all of its translations and placeholders are visible together. The catalog groups them under one key, so you can compare wording across languages without moving between locale files.

- **One source of truth:** a const Dart catalog is the authoritative source. JSON and XLSX are exchange formats.
- **Validation before generation:** detect missing translations, blank values, invalid locales, and inconsistent placeholders.
- **Separate authoring and runtime:** applications import a generated loader; authoring tools import the catalog.
- **Explicit ownership:** your application owns a resolver and shares it with the Flutter scope or an existing dependency injection system.
- **Reviewable translation imports:** merge creates a candidate and a key comparison report without changing the source.
- **A small Flutter API:** `context.tr`, `context.format`, `context.updateLocale`, and `context.reloadMessages`.

This approach works well when translations live in code but translators work with spreadsheets. Message keys are still strings; this version does not generate typed placeholder methods or support ICU plural rules.

```text
const Dart catalog ── build_runner ──> standalone generated runtime
        │                                              │
        │ export                                       ▼
        ▼                                     app-owned MessageResolver
     JSON / XLSX                                       │
        │ merge                                        ▼
        ▼                                      MessageI18nScope
 candidate + key report                                │
        │ human review                                 ▼
        └──────────────> update catalog          context.tr / format
```

## Packages and requirements

| Package | Purpose | Declared minimum |
|---|---|---|
| `message_i18n` | Dart model, runtime, validation, generation, exchange tools | Dart 3.11 |
| `message_i18n_builder` | Development Builder and const catalog analysis | Dart 3.11 |
| `message_i18n_flutter` | Flutter scope, context extensions, locale adapters | Dart 3.11 / Flutter 3.47 |

The core works without Flutter, and the Flutter adapter depends only on that core. Riverpod and GetX are optional. Authoring commands use filesystem and process APIs, so run them in your development environment rather than in a browser. The application itself loads the generated runtime.

## Quick start

Start with `build_runner`. Its build and watch commands can run message_i18n alongside the other generators already used by your app. Use `MessageI18nTool` only when you need its optional CLI workflow.

### 1. Install the packages

For a Dart app, run `dart pub add message_i18n`. For Flutter, run `flutter pub add message_i18n message_i18n_flutter`. Then add these development dependencies to the app's `pubspec.yaml` and run `dart pub get` or `flutter pub get`:

```yaml
dev_dependencies:
  message_i18n_builder: ^0.1.0
  build_runner: '>=2.16.2 <2.17.0'
```

The builder supports build 4.x. The tested baseline with go_router_builder uses build_runner 2.16.2. Check compatible build versions before upgrading generators together, because their major-version constraints can conflict.

For Flutter's built-in widget localization, also add:

```yaml
dependencies:
  flutter_localizations:
    sdk: flutter
```

### 2. Write the source catalog

Create a catalog such as `lib/i18n/catalog.dart`; the path and filename are up to you. Keep this authoring file out of runtime imports, and annotate one top-level const catalog in each input library:

```dart
import 'package:message_i18n/message_i18n.dart';

@MessageI18nCatalog()
const appCatalog = MessageCatalog(
  defaultLocale: 'ko',
  supportedLocales: ['ko', 'en', 'ja'],
  messages: {
    'common.save': LocalizedMessage({
      'ko': '저장',
      'en': 'Save',
      'ja': '保存',
    }),
    'welcome.user': LocalizedMessage({
      'ko': '{name}님, 환영합니다.',
      'en': 'Welcome, {name}.',
      'ja': '{name}さん、ようこそ。',
    }),
    'language.english': LocalizedMessage({
      'ko': '영어',
      'en': 'English',
      'ja': '英語',
    }),
    'action.reload': LocalizedMessage({
      'ko': '번역 다시 읽기',
      'en': 'Reload messages',
      'ja': '翻訳を再読込',
    }),
  },
);
```

Provide a nonblank translation for every supported locale, include the default locale in that list, and use the same placeholder names in every translation of a message. The builder also resolves imported constants and const map spreads.

#### Message key rules

The catalog key is the exact value used at lookup time, so write it according to these rules:

- The key must match `^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$`.
- It starts with an ASCII lowercase letter. Each segment contains only ASCII lowercase letters and digits, and segments use one dot, hyphen or underscore as a separator.
- Whitespace, uppercase letters, non-ASCII characters, other symbols, leading/trailing separators and consecutive separators are invalid.
- Use a stable semantic name such as `feature.action`. Dotted names are recommended but not required.
- For a valid key, the Builder removes the separators and joins the segments as a lowerCamelCase `MessageKeys` field.
- The generated field must match `[A-Za-z$][A-Za-z0-9$]*` and must not be a Dart keyword or an inherited `Object` instance member such as `hashCode`.
- Every converted field name must be unique. The Builder does not add a prefix, suffix, number, hash or alias to repair a name.

```text
app.title       -> appTitle       (valid)
welcome-user    -> welcomeUser    (valid)
App.title       -> invalid_key    (uppercase; validation failure)
한국어.제목      -> invalid_key    (non-ASCII; validation failure)
app..title      -> invalid_key    (consecutive separators; validation failure)
app.title-      -> invalid_key    (trailing separator; validation failure)
a.a, a_a, a-a  -> aA             (collision; build failure)
class           -> class          (reserved; build failure)
123.title       -> 123Title       (invalid; build failure)
```

If a key is invalid or collides with another generated name, rename it in the catalog and rebuild. The validator will not alter it for you. When renaming an existing key, update every raw-string reference as well; generated member references will update on the next build. See [Generated message key constants](#generated-message-key-constants) for how to use those members.

#### Placeholder and format parameter rules

Mark a replaceable value as `{identifier}`. The identifier must match `[A-Za-z_][A-Za-z0-9_]*`: begin with an ASCII letter or underscore, then use ASCII letters, digits, or underscores. Names are case-sensitive. Placeholder names do not follow the lowercase message-key rule, so `{userName}` is valid.

Use the same set of placeholder names in every translation of a message. Languages may place them in a different order or repeat them a different number of times.

Pass a `Map<String, String>` whose keys exactly match the placeholder names:

```dart
final text = messages.format(
  MessageKeys.welcomeUser,
  {'name': 'Dart'},
);
// With the English catalog above: Welcome, Dart.
```

If an argument is missing, the placeholder stays in the output and the resolver emits `missing_argument`. Extra arguments are ignored and reported as `extra_argument`. Convert numbers, dates, and other values to strings before passing them.

Catalog validation rejects positional placeholders such as `{0}`, empty or unmatched braces, nested braces, and ICU plural/select/gender syntax. This version does not provide brace escaping.

### 3. Validate and generate

Run the build from the application root. You do not need a `tool/i18n.dart` entrypoint:

```bash
dart run build_runner build
```

The build validates the catalog and writes `lib/i18n/catalog.message_i18n.g.dart` as an independent runtime library. Import it directly rather than connecting it to the source with `part`.

The output follows the source filename: `lib/i18n/account.dart`, for example, produces `lib/i18n/account.message_i18n.g.dart`. You may move or rename the source as long as runtime imports point to the matching generated file.

### Generated runtime contents

Each annotated catalog produces its own standalone library. The catalog above generates these declarations:

| Generated item | What it does | Short example |
|---|---|---|
| `supportedMessageLocales` | A `List<String>` copied from the catalog's `supportedLocales`. Use it when configuring the locales supported by a Flutter app. | `messageLocales(supportedMessageLocales)` |
| `defaultMessageLocale` | The catalog's `defaultLocale`. Generated locale resolution uses it when a request cannot be matched. | `createMessageResolver(selected: defaultMessageLocale)` |
| `resolveGeneratedLocale(requested)` | Resolves a requested locale against the generated supported and default locales. | `resolveGeneratedLocale('en-US') // 'en'` |
| `loadGeneratedMessages(requested)` | Resolves a locale and returns its generated locale name and message map as `GeneratedLocaleMessages`. | `loadGeneratedMessages('ko-KR').messages` |
| `createMessageResolver(...)` | Creates the app-owned `MessageResolver` backed by the generated loader. An optional `onDiagnostic` callback receives runtime diagnostics. | `createMessageResolver(selected: 'ko-KR')` |
| `MessageKeys` | Contains one `static const String` for every catalog key. The value remains the exact source key. | `messages.text(MessageKeys.commonSave)` |
| `load<Locale>Messages()` | Returns the generated message map for one supported locale. One function is generated per locale, such as `loadEnMessages()` and `loadKoMessages()`. | `loadKoMessages()[MessageKeys.commonSave]` |

Most apps need only `createMessageResolver`, `MessageKeys`, and `supportedMessageLocales`. Use the lower-level locale and loader functions for custom integrations, diagnostics, or tests; regular message lookup belongs on `MessageResolver`.

When a generated library has an import prefix, use that prefix for every declaration it contains:

```dart
import 'i18n/catalog.message_i18n.g.dart' as appI18n;

final messages = appI18n.createMessageResolver(selected: 'en-US');
final locales = appI18n.supportedMessageLocales;
final saved = messages.text(appI18n.MessageKeys.commonSave);
```

Each source catalog remains a separate runtime library. The prefix only disambiguates names; it does not combine catalogs or resolvers.

### 4. Use the generated runtime

Once the file exists, import it from runtime code such as `lib/main.dart`. The next section shows the Flutter setup.

```dart
import 'i18n/catalog.message_i18n.g.dart';

void main() {
  final messages = createMessageResolver(selected: 'ko-KR');
  print(messages.text(MessageKeys.commonSave));
  print(messages.format(MessageKeys.welcomeUser, {'name': 'Dart'}));
  messages.select('en-US');
  // Raw strings remain available for dynamic keys or gradual migration.
  print(messages.text('common.save'));
}
```

### Generated message key constants

The runtime build also generates `MessageKeys`. Every field is a `static const String` that preserves the catalog key exactly:

```dart
abstract final class MessageKeys {
  static const String actionReload = 'action.reload';
  static const String commonSave = 'common.save';
  static const String languageEnglish = 'language.english';
  static const String welcomeUser = 'welcome.user';
}
```

Both forms are supported:

| Form | Use it when |
|---|---|
| `context.tr(MessageKeys.commonSave)` | The key is known at compile time. Misspelled, deleted or renamed generated members become compile errors. |
| `context.tr('common.save')` | The key is dynamic or the application is migrating gradually. Missing keys are reported by the normal runtime diagnostic. |

The Builder validates the source key before converting dot-, hyphen-, or underscore-separated segments to lowerCamelCase. It never adds a prefix, suffix, number, hash, or alias to make a name compile. Generation fails if two keys produce the same member or if the result is a Dart keyword or inherited `Object` member.

```text
a.a, a_a, a-a  -> MessageKeys.aA  -> build failure
class           -> MessageKeys.class -> build failure
123.title       -> invalid_key -> build failure before constant generation
```

Resolve these errors by renaming the catalog key and rebuilding. A failed build does not leave a partial `MessageKeys` class. Constants appear after the first successful build and change whenever build or watch processes the catalog. If you remove or rename a key, any old member reference will fail during analysis or compilation.

Every generated catalog library has its own `MessageKeys`. If an app uses several catalogs, distinguish their imports with prefixes and pair each key with the resolver from the same library:

```dart
import 'account.message_i18n.g.dart' as accountI18n;
import 'checkout.message_i18n.g.dart' as checkoutI18n;

final accountMessages = accountI18n.createMessageResolver(selected: 'en');
final checkoutMessages = checkoutI18n.createMessageResolver(selected: 'en');

accountMessages.text(accountI18n.MessageKeys.profileTitle);
checkoutMessages.text(checkoutI18n.MessageKeys.paymentTitle);
```

### What runs once, and what repeats?

| Task | When to do it |
|---|---|
| Install packages/Builder and annotate the catalog | Initial setup; adjust when paths or dependencies change |
| Initial build | Before importing the generated loader |
| Change messages, translations, placeholders or default/supported locales | Build again, or keep watch running |
| Select a locale or use an existing key on another screen | No generation if the catalog did not change |
| build --only-check | Detect missing, modified or stale generated files without repairing outputs |
| Legacy CLI check | Optional catalog-only validation without generated files |

During development, keep one watch command running. Freezed, router, JSON, and other installed builders will run from the same watcher when their inputs change:

```bash
dart run build_runner watch
```

## Flutter setup

Flutter runtime code imports the generated library, not the source catalog. In the example below, `supportedMessageLocales` comes from the catalog's `supportedLocales`. [Generated runtime contents](#generated-runtime-contents) lists `defaultMessageLocale` and the remaining declarations. Keep `MessageI18nTool` and the source catalog in development code; [Authoring and code generation](#authoring-and-code-generation) explains that workflow. A complete `lib/main.dart` looks like this:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:message_i18n_flutter/message_i18n_flutter.dart';
import 'i18n/catalog.message_i18n.g.dart';

void main() => runApp(const AppRoot());

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  final _resolver = createMessageResolver(selected: 'ko-KR');

  @override
  void reassemble() {
    super.reassemble();
    _resolver.reload();
  }

  @override
  Widget build(BuildContext context) {
    return MessageI18nScope(
      resolver: _resolver,
      child: const MyApp(),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    locale: messageLocale(context.i18n.locale),
    supportedLocales: messageLocales(supportedMessageLocales),
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.tr(MessageKeys.commonSave)),
            Text(context.format(MessageKeys.welcomeUser, {'name': 'Dart'})),
            Text(context.tr('common.save')),
            TextButton(
              onPressed: () => context.updateLocale('en-US'),
              child: Text(context.tr(MessageKeys.languageEnglish)),
            ),
          ],
        ),
      ),
    ),
  );
}
```

Put `MessageI18nScope` above `MaterialApp`. Routes, nested navigators, dialogs, bottom sheets, and overlays can then reach the same resolver. A context created above the scope cannot read it.

Configure `flutter_localizations` and its delegates in the app. message_i18n translates your messages but does not set up Material or Cupertino's built-in labels. When converting a locale string to Flutter's `Locale`, `messageLocale` preserves script and country subtags.

Read translated text in `build`, or refresh cached labels in `didChangeDependencies`. A string captured once in `initState` will stay unchanged when the locale changes.

## Runtime API and locale behavior

| Dart resolver | Flutter API | Behavior |
|---|---|---|
| `text(key)` | `context.tr(key)` | Look up a message |
| `format(key, arguments)` | `context.format(key, arguments)` | Substitute named string arguments |
| `select(locale)` | `context.updateLocale(locale)` | Load a locale and notify listeners |
| `reload()` | `context.reloadMessages()` | Reload the last requested locale and notify listeners |
| `locale` / `selected` | `context.i18n.locale` / `.selected` | Resolved locale / original request |
| `addListener` / `removeListener` | Scope manages its subscription | Subscribe outside Flutter |

Calling `tr`, `format`, or `context.i18n` subscribes the widget to resolver changes. Commands such as `updateLocale` and `reloadMessages` read without subscribing. For direct access, `MessageI18nScope.of` listens, `read` does not, and `maybeOf` handles a missing scope.

### Locale selection

A locale may contain a two- or three-letter language code, an optional four-letter script, and an optional two-letter or three-digit region:

| Input | Normalized |
|---|---|
| `en_US` | `en-US` |
| `zh_hant_tw` | `zh-Hant-TW` |
| `ko-KR` | `ko-KR` |

Locale selection starts with an exact match, removes trailing subtags one at a time, and finally falls back to the catalog default. For `zh-Hant-TW`, the order is `zh-Hant-TW → zh-Hant → zh → default`; the first supported entry wins. Invalid variants, extensions, or subtag order throw `FormatException` instead of entering the fallback chain.

The resolver keeps only the current message map and replaces it after selection or reload. It has no per-message fallback map or cache of every locale. Other locale strings may still exist elsewhere in the application binary or VM heap.

### Placeholders and diagnostics

Placeholders use `{identifier}` names that match `[A-Za-z_][A-Za-z0-9_]*`, and formatting accepts a `Map<String, String>`. This version does not handle escaped braces, nested expressions, ICU plural/select/gender rules, or automatic number and date formatting.

```dart
final messages = createMessageResolver(
  selected: 'en',
  onDiagnostic: (issue) {
    print('${issue.code}: ${issue.key} (${issue.locale})');
  },
);
```

| Condition | Runtime result | Diagnostic |
|---|---|---|
| Unknown message | Returns the key itself | `missing_key` |
| Missing argument | Keeps the unresolved placeholder | `missing_argument` |
| Extra argument | Ignores the unused argument | `extra_argument` |
| Unsupported placeholder syntax | Returns the unformatted message | `unsupported_placeholder` |

Each diagnostic includes a code, key, and locale. Strict catalog validation catches translation errors before generation. `MessageResolver.fromLoader` exists for loader bridges and test fakes; application code will usually use the generated factory.

## State management and ownership

Give the application-wide resolver one owner and one way to notify the UI. The built-in scope, Riverpod, and GetX examples are three alternatives. When Riverpod or GetX owns the resolver, do not add `MessageI18nScope` around it.

The examples below were verified with Flutter 3.47.7, flutter_riverpod 3.4.3, and get 4.7.3. Riverpod and GetX remain optional app dependencies; none of the message_i18n packages depends on them.

### Built-in MessageI18nScope

If the app does not use another state manager, create one resolver at the composition root and pass it to `MessageI18nScope` above `MaterialApp`. The scope listens to that resolver but does not create or dispose it. Widgets can then use `context.tr`, `context.format`, `context.updateLocale`, and `context.reloadMessages` as shown in [Flutter setup](#flutter-setup).

These context extensions work only below `MessageI18nScope`. Riverpod and GetX route the same operations through their provider or controller instead, so those examples do not use the extensions.

### Riverpod

Add `flutter_riverpod` to the app and place `ProviderScope` at its root. A `NotifierProvider` owns the generated resolver and publishes a new state wrapper and revision after a successful change. This rebuilds both `MaterialApp.locale` and the widgets that display messages. Change or reload the locale through the notifier; calling the resolver directly bypasses that update.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:message_i18n/message_i18n.dart';
import 'package:message_i18n_flutter/message_i18n_flutter.dart';

import 'i18n/catalog.message_i18n.g.dart';

class MessagesState {
  const MessagesState._(this._resolver, this.revision);

  final MessageResolver _resolver;
  final int revision;

  String get locale => _resolver.locale;
  String text(String key) => _resolver.text(key);
  String format(String key, Map<String, String> arguments) =>
      _resolver.format(key, arguments);
}

class MessagesController extends Notifier<MessagesState> {
  @override
  MessagesState build() => MessagesState._(
    createMessageResolver(selected: defaultMessageLocale),
    0,
  );

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

void main() => runApp(
  const ProviderScope(child: RiverpodApp()),
);

class RiverpodApp extends ConsumerStatefulWidget {
  const RiverpodApp({super.key});

  @override
  ConsumerState<RiverpodApp> createState() => _RiverpodAppState();
}

class _RiverpodAppState extends ConsumerState<RiverpodApp> {
  @override
  void reassemble() {
    super.reassemble();
    ref.read(messagesProvider.notifier).reload();
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(messagesProvider);
    return MaterialApp(
      locale: messageLocale(messages.locale),
      supportedLocales: messageLocales(supportedMessageLocales),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const RiverpodMessagesPage(),
    );
  }
}

class RiverpodMessagesPage extends ConsumerWidget {
  const RiverpodMessagesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = ref.watch(messagesProvider);
    final controller = ref.read(messagesProvider.notifier);
    return Scaffold(
      body: Column(
        children: [
          Text(messages.text(MessageKeys.commonSave)),
          Text(
            messages.format(
              MessageKeys.welcomeUser,
              {'name': 'Dart'},
            ),
          ),
          TextButton(
            onPressed: () => controller.select('en-US'),
            child: Text(messages.text(MessageKeys.languageEnglish)),
          ),
          TextButton(
            onPressed: controller.reload,
            child: Text(messages.text(MessageKeys.actionReload)),
          ),
        ],
      ),
    );
  }
}
```

After `select` or `reload` succeeds, `MessagesState` wraps the same resolver in a new state object. This wrapper and its revision are UI notification values, not historical translation snapshots: an older wrapper still reads the current locale from the shared mutable resolver. If locale loading throws, no state is published and the previous locale remains active.

### GetX

Add `get` to the app and use `GetMaterialApp` as its root. Register one permanent controller before `runApp`, then let a root `GetBuilder` rebuild `GetMaterialApp.locale` and the message widgets from that controller.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:message_i18n/message_i18n.dart';
import 'package:message_i18n_flutter/message_i18n_flutter.dart';

import 'i18n/catalog.message_i18n.g.dart';

class MessagesController extends GetxController {
  final MessageResolver _resolver = createMessageResolver(
    selected: defaultMessageLocale,
  );

  String get locale => _resolver.locale;
  String text(String key) => _resolver.text(key);
  String format(String key, Map<String, String> arguments) =>
      _resolver.format(key, arguments);

  void select(String locale) {
    _resolver.select(locale);
    Get.locale = messageLocale(_resolver.locale);
    update();
  }

  void reload() {
    _resolver.reload();
    update();
  }
}

void main() {
  Get.put(MessagesController(), permanent: true);
  runApp(const GetXApp());
}

class GetXApp extends StatefulWidget {
  const GetXApp({super.key});

  @override
  State<GetXApp> createState() => _GetXAppState();
}

class _GetXAppState extends State<GetXApp> {
  @override
  void reassemble() {
    super.reassemble();
    Get.find<MessagesController>().reload();
  }

  @override
  Widget build(BuildContext context) => GetBuilder<MessagesController>(
    builder: (messages) => GetMaterialApp(
      locale: messageLocale(messages.locale),
      supportedLocales: messageLocales(supportedMessageLocales),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const GetXMessagesPage(),
    ),
  );
}

class GetXMessagesPage extends StatelessWidget {
  const GetXMessagesPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: GetBuilder<MessagesController>(
      builder: (messages) => Column(
        children: [
          Text(messages.text(MessageKeys.commonSave)),
          Text(
            messages.format(
              MessageKeys.welcomeUser,
              {'name': 'Dart'},
            ),
          ),
          TextButton(
            onPressed: () => messages.select('en-US'),
            child: Text(messages.text(MessageKeys.languageEnglish)),
          ),
          TextButton(
            onPressed: messages.reload,
            child: Text(messages.text(MessageKeys.actionReload)),
          ),
        ],
      ),
    ),
  );
}
```

The controller synchronizes `Get.locale` with the resolver, then one `update()` rebuilds both the root `GetMaterialApp` and the message `GetBuilder`. This avoids `Get.updateLocale`, which performs an asynchronous whole-app reassemble in get 4.7.3 and can conflict with widget-test frames and the hot-reload hook above. message_i18n does not register GetX `translations` or add a `String.tr` extension. Use the controller's `text` and `format` methods for message_i18n lookups.

## Authoring and code generation

`message_i18n_builder` reads annotated constants statically and validates them without running the app or `MessageI18nTool`. It writes the locale factories and loader to one file, while the runtime continues to hold only the current locale's message map.

### Builder paths and filenames

| Change | Update |
|---|---|
| catalog.dart → messages.dart | App import becomes messages.message_i18n.g.dart |
| Move the catalog directory | App generated import and generate_for, if configured |
| Rename the catalog variable | Keep the annotation; the generated loader API stays the same |
| Inputs outside lib | Include them in build target sources and generate_for |

By default, the Builder reads Dart files under `lib/` and skips generated files. Annotate one catalog per library. When you import more than one generated library, give each import a prefix. Output appears beside its source with a fixed suffix; the CLI settings `generatedDirectory`, `sourcePaths`, and `watchEntrypoint` do not affect the Builder.

To limit which files the Builder reads, configure `build.yaml` in the app:

```yaml
targets:
  $default:
    builders:
      message_i18n_builder:
        generate_for:
          - lib/localization/messages.dart
```

### Optional CLI and existing projects

Use the configuration below only for catalog checks, JSON/XLSX exchange, or the legacy CLI generator. The regular Builder workflow does not need it. When migrating, add the annotation and development dependencies, run a build, and update the app's generated import. Remove the old generated directory yourself when it is no longer needed, and do not run the Builder and CLI watchers at the same time.

To use the optional CLI, create `tool/i18n.dart`:

```dart
import 'package:message_i18n/message_i18n_tool.dart';
import 'package:your_app/i18n/catalog.dart';

Future<void> main(List<String> args) => MessageI18nTool(
  catalog: appCatalog,
  sourcePaths: const ['lib/i18n'],
  generatedDirectory: 'lib/i18n/generated',
  watchEntrypoint: 'tool/i18n.dart',
).run(args);
```

Replace `your_app` with the `name` declared in your application's `pubspec.yaml`.

### Legacy CLI configuration details

`MessageI18nTool` is the entry point for the optional authoring CLI. Give it a const `MessageCatalog`, and it can validate, generate, watch, export, or merge translations. The tool runs only when a developer or CI invokes its entrypoint; starting the application does not run it.

#### Development lifecycle

```text
one-time setup:  catalog file + tool entrypoint + initial generate
ongoing work:    edit catalog → generate, or edit catalog → watch auto-generation
application:     generated loader → resolver → Dart or Flutter UI
CI:              check --verify-generated
translation:     export → external edit → merge candidate → human review → catalog
```

You normally create the catalog file and tool entrypoint once. The catalog itself remains the source of truth, so keep editing it as messages and locales change. Run `generate` after each change, or leave `watch` running to regenerate automatically.

#### Tool configuration

| Argument | Role |
|---|---|
| `catalog` | The authoritative `MessageCatalog` object already imported by the tool entrypoint. It is not a file path. |
| `sourcePaths` | Existing project directories watched for `.dart` changes by `watch`. They do not discover catalog objects. |
| `generatedDirectory` | A dedicated directory inside the project for generated locale files, loader, and manifest. Do not place hand-written files there. |
| `watchEntrypoint` | The project-relative Dart entrypoint launched in a fresh process for each watch generation cycle. The current CLI also checks that this file exists before every public command. |
| `projectRoot` | Base directory for relative paths and file-safety checks. It defaults to the current directory. |

#### Custom paths and filenames

The paths `lib/i18n/catalog.dart`, `tool/i18n.dart`, and `lib/i18n/generated/` are examples. You can choose another layout as long as the Dart imports, tool settings, commands, and runtime import all point to the same places. For example:

```dart
import 'package:message_i18n/message_i18n_tool.dart';
import 'package:my_app/localization/messages.dart';

Future<void> main(List<String> args) => MessageI18nTool(
  catalog: applicationMessages,
  sourcePaths: const ['lib/localization'],
  generatedDirectory: 'lib/localization/generated',
  watchEntrypoint: 'scripts/localization.dart',
).run(args);
```

Use the entrypoint's actual path when running a command:

```bash
dart run scripts/localization.dart generate
dart run scripts/localization.dart watch
```

| What you change | What must change with it |
|---|---|
| Catalog file path or name | The Dart import in the tool entrypoint |
| Catalog object name | The object passed to `catalog:` |
| Directory containing catalog sources | Include it in `sourcePaths` if `watch` must react to its changes |
| Tool entrypoint path or name | `watchEntrypoint` and every `dart run <entrypoint>` command |
| Generated directory | `generatedDirectory` and the application's generated-loader import |
| Command working root | Run beside the consumer `pubspec.yaml`, or set `projectRoot` explicitly |

A direct `generate` command can import a catalog outside `sourcePaths`, but `watch` only sees changes inside the configured directories. Relative paths start at `projectRoot`. Keep generated output in a dedicated directory inside the project so the tool can manage it safely.

#### Manual generation or watch

For explicit generation after a catalog change:

```bash
dart run tool/i18n.dart generate
```

For automatic generation while editing:

```bash
dart run tool/i18n.dart watch
```

`watch` generates once at startup and then monitors `.dart` files under `sourcePaths`. Runtime code continues to import the generated loader, never the authoring catalog or tool entrypoint.

## CLI reference

Run CLI commands from the app root that contains `pubspec.yaml` and the configured tool entrypoint:

```bash
dart run tool/i18n.dart <command> [options]
```

| Command | When to use it | Main options |
|---|---|---|
| `check` | Before generation and in fast validation jobs | `--verify-generated` |
| `generate` | After catalog changes or in a build step | `--output <directory>` |
| `watch` | During local translation editing | `--debounce-ms <integer>` |
| `export` | Before sending translations to a translator | `--locales`, `--format`, `--output`, `--split-by-locale` |
| `merge` | After receiving edited JSON/XLSX files | repeat `--input`, optional `--output` |

### `check`: validate the catalog

```bash
dart run tool/i18n.dart check
dart run tool/i18n.dart check --verify-generated
```

`check` validates locale identifiers, the default and supported locale relationship, message keys, missing or blank translations, and placeholder syntax across languages. It never writes generated files. In CI, add `--verify-generated` to create the expected output in a temporary directory and compare it with the tool-owned files in `generatedDirectory`. The command fails if an output is missing, modified, or stale.

### `generate`: write runtime files

```bash
dart run tool/i18n.dart generate
dart run tool/i18n.dart generate --output lib/i18n/generated
```

`generate` validates the catalog, then writes one Dart message file per locale along with `message_loader.g.dart` and `message_i18n_manifest.json`. Use `--output` to override `generatedDirectory` for one run; the target must be a dedicated directory inside the project. The command stages and formats complete files before replacing its existing output. It uses the manifest to remove stale files and refuses to overwrite files it does not own.

Run `generate` whenever the catalog, supported locales, or generation settings change. The application can keep importing the same generated loader path.

### `watch`: regenerate while editing

```bash
dart run tool/i18n.dart watch
dart run tool/i18n.dart watch --debounce-ms 400
```

`watch` generates once, then monitors `.dart` files under `sourcePaths`. By default it groups rapid edits within 250 ms and runs each generation cycle in a fresh Dart process, one at a time. It ignores generated output, `build/`, and `.dart_tool/` to avoid loops. If a cycle fails, the last successful output remains in place and the watcher waits for the next edit. Press `Ctrl+C` to stop it.

After a successful cycle, hot reload is enough for message text changes. Use hot restart when the locale structure or generated imports change.

### `export`: create translator files

```bash
dart run tool/i18n.dart export --locales ko,en --format json
dart run tool/i18n.dart export --locales ko,en --format xlsx --output build/translations.xlsx
dart run tool/i18n.dart export --locales ko,en --format xlsx --split-by-locale
```

Both `--locales` and `--format` are required. Pass locales as a comma-separated list and choose either `json` or `xlsx`. Without `--output`, the command creates a timestamped directory under `build/message_i18n/exports/`. For a combined export, point `--output` to a file with the selected extension. With `--split-by-locale`, point it to a directory instead. Export never overwrites an existing destination.

### `merge`: create a review candidate

```bash
dart run tool/i18n.dart merge --input build/translations.json
dart run tool/i18n.dart merge \
  --input build/ko.xlsx \
  --input build/en.xlsx \
  --output build/message_i18n/review
```

Add one `--input` option for each `.json` or `.xlsx` file. If several files contain the same key and locale, the last input wins and the tool prints a warning. Choose a new output directory under the project's `build/` directory; the command writes `merged_catalog.dart` and `key-comparison.json` there.

`merge` leaves the source catalog untouched and never fills missing input values from that source. Review the candidate, key comparison, and warnings, then copy accepted changes into `catalog.dart` yourself and run `check` and `generate` again.

### Help, version, and exit codes

```bash
dart run tool/i18n.dart --help
dart run tool/i18n.dart <command> --help
dart run tool/i18n.dart --version
```

Exit code **0** indicates success. Code **1** covers validation, malformed input, parsing, process, and file errors; **64** indicates invalid command usage. Normal output goes to stdout, while errors and merge warnings go to stderr. `__watch-cycle` belongs to the watcher and should not be called directly.

Strict validation can report `invalid_locale`, `empty_locales`, `duplicate_locale`, `missing_default`, `invalid_key`, `unsupported_locale`, `empty_translation`, `missing_translation`, `unsupported_placeholder`, and `placeholder_mismatch`. Reports are sorted by severity, key, locale, and code. Duplicate const map keys and incompatible value types fail in Dart before the tool starts.

## Translation workflow

### 1. Export a validated catalog

```bash
dart run tool/i18n.dart export --locales ko,en --format json --output build/translations.json
dart run tool/i18n.dart export --locales ko,en --format xlsx --output build/translations.xlsx
dart run tool/i18n.dart export --locales ko,en --format xlsx --split-by-locale
```

If you omit the destination, the export goes to `build/message_i18n/exports/<timestamp>/`. A combined export uses a file with the matching extension; a split export uses a directory. Existing files stay untouched, and automatically named directories receive a suffix if the timestamp already exists.

JSON groups values by key and then locale:

```json
{
  "common.save": {"ko": "저장", "en": "Save"},
  "welcome.user": {"ko": "{name}님, 환영합니다.", "en": "Welcome, {name}."}
}
```

XLSX uses a sheet named `translations`:

| key | ko | en |
|---|---|---|
| common.save | 저장 | Save |
| welcome.user | {name}님, 환영합니다. | Welcome, {name}. |

The first header must be exactly `key`, followed by locale columns in the requested order. The sheet has no description, source-path, or hidden metadata columns. Keep every cell as text: imports reject numeric and formula cells, and exports store values beginning with `=`, `+`, `-`, or `@` explicitly as text.

The importer rejects duplicate normalized locale headers, duplicate key rows, and nonempty rows without a key. It ignores completely empty rows and reads blank translation cells as empty strings.

### 2. Merge returned files

```bash
dart run tool/i18n.dart merge --input build/translations.json --input build/translations.xlsx
```

The output directory defaults to `build/message_i18n/merges/<timestamp>/` and contains:

- `merged_catalog.dart`: a standalone `mergedCatalog` candidate.
- `key-comparison.json`: sorted key differences relative to the original catalog.

**Merge uses only the files you supply.** It neither changes the original catalog nor fills missing keys or translations from it. When inputs overlap, the last value for a key and locale wins, and a warning identifies both input positions. An English-only import therefore remains English-only; Korean and Japanese values are not silently copied from the source.

Missing languages, blank values, placeholder differences, and key differences appear as warnings or reports, but the tool can still create a candidate. Exit code 0 means that candidate creation succeeded, not that strict validation passed. Malformed files and I/O errors return 1. Merge output must stay under the app's `build/` directory.

Key comparison looks only at which keys exist; it does not compare translation text. The human-readable report currently uses Korean:

```text
원본과 병합본의 키가 일치합니다.
```

This means the key sets match. When they differ, the applicable sections are printed:

```text
원본에만 있는 키는 다음과 같습니다.
- old.key
병합본에만 있는 키는 다음과 같습니다.
- new.key
```

The first section contains keys found only in the source, and the second contains keys found only in the merged candidate. The same result is available in machine-readable form:

```json
{"matched":false,"originalOnly":["old.key"],"mergedOnly":["new.key"]}
```

### 3. Review and apply

Review the warnings, translated text, and key differences before copying approved changes into the Dart catalog. Then run `dart run build_runner build`. Projects that still use CLI generation should run `check`, `generate`, and `check --verify-generated`. There is no command that applies a merge candidate automatically.

## Generated files and recovery

If a build fails, build_runner may remove the previous output. Fix the catalog and wait for generation to succeed before reloading the app.

Reserve `.message_i18n.g.dart` paths for build_runner because a build may replace anything written there by hand. `build --only-check` reports differences without writing or deleting public output; changes inside the private `.dart_tool` cache are separate. An invalid catalog fails the build, so fix it and rebuild or let watch recover. Builder-managed output does not have the legacy CLI's rollback guarantee.

### Legacy CLI file ownership


Treat the generated directory as tool-owned. Its manifest records the schema, catalog fingerprint, locales, key count, and owned files. To change a translation, edit the catalog and regenerate instead of modifying the output.

Either commit generated files for review and reproducibility, or create them before analysis and build. When they are committed, use `check --verify-generated` in CI to catch stale output.

Before replacing its files, the CLI validates the catalog, stages and formats complete output, and checks that the destination has not changed. It uses **per-file rename with rollback on failure**, so the whole file set is not swapped atomically. Files outside the manifest remain untouched, and stale cleanup removes only manifest-owned files. The CLI rejects path escapes, symlinks, and attempts to take ownership of unrelated files.

An OS lock prevents two processes from generating into the same target. Its zero-byte guard file, such as `.generated.message_i18n.lock`, stays beside the output and is ignored by Git; the actual lock is released when the process exits. Do not delete the guard to bypass contention. After a forced shutdown or power loss, run `check --verify-generated` and regenerate if needed. Recovery of the entire file set cannot be guaranteed after every abrupt interruption.

## Watch and hot reload

In a separate terminal, run:

```bash
dart run build_runner watch
```

build_runner tracks input files and their dependencies. If a build fails, correct the reported source while the watcher keeps running; it will try again after the next change. Press Ctrl-C to stop. Other installed builders use the same watch process.

Generation does not reload the Flutter app for you. The root owner must refresh its existing resolver when Flutter calls `reassemble()` during hot reload. The `AppRoot` shown in [Flutter setup](#flutter-setup) does this directly:

```dart
@override
void reassemble() {
  super.reassemble();
  _resolver.reload();
}
```

The Riverpod example calls `ref.read(messagesProvider.notifier).reload()` from `RiverpodApp.reassemble()`. The GetX example calls `Get.find<MessagesController>().reload()` from `GetXApp.reassemble()`. Each hook goes through the same owner that normally publishes UI updates.

| Change | Development action |
|---|---|
| Existing translation text | Generate, then hot reload with the owner's `_resolver.reload()` hook |
| New message key and its usage | Generate, then hot reload |
| Supported locales or initialization structure | Generate, then hot restart |

The watcher never connects to the Flutter daemon, so it cannot request a reload. Remember that hot reload does not rerun `main`, `initState`, or existing static initializers. See [Flutter's hot reload documentation](https://docs.flutter.dev/tools/hot-reload) for the full behavior.

## Troubleshooting

| Symptom | Check or action |
|---|---|
| A message key appears instead of text | Check the key and `missing_key` diagnostic; regenerate after catalog changes |
| `{name}` remains visible | Supply `name` as a string argument to `format` |
| A requested locale resolves to another locale | Inspect `selected`, `locale`, and the supported-locale fallback chain |
| Widgets keep the previous language | Read during rebuild and share one resolver. Put the built-in Scope above routes, or make every route/dialog watch the same Riverpod provider or GetX controller. |
| Scope lookup fails | Use a descendant context or move the scope above the consumer |
| Built-in Flutter labels are wrong | Configure `flutter_localizations`, delegates, `locale`, and `supportedLocales` in the consumer |
| Edited source is not visible after reload | Wait for successful generation and ensure `reassemble` calls the existing resolver's `reload` |
| Merge succeeds but candidate validation fails | Merge success means a review candidate exists; resolve its warnings before applying |
| Excel import rejects a cell | Use text cells, exact `key` header, and the `translations` sheet |
| Generated verification fails | Run build, review output, then build --only-check; use legacy commands only for legacy outputs |
| Generation reports a lock conflict | Stop or wait for the competing process; do not remove its guard file |

## CI integration

If generated files are committed, resolve dependencies and check before running a build that would repair them:

```bash
dart run build_runner build --only-check
```

If Git ignores generated files, generate them before analyzing, testing, or building the app. Running only-check afterward verifies the files just created; it does not say anything about committed-file freshness. Missing output correctly causes only-check to fail. The legacy CLI's `check --verify-generated` applies only to its multi-file manifest format.

The tested integration set uses build_runner 2.16.2, build 4.0.11, Freezed 4.0.3, go_router_builder 4.5.2, go_router 18.1.1, and json_serializable 6.15.2 on Dart 3.13 and Flutter 3.47. The Builder itself supports Dart 3.11. When using another combination, check both dependency resolution and the generated code at runtime.

## Scope and limitations

This version generates String constants for message keys, but not typed functions for placeholders. ICU plurals and gender, remote delivery, a translation web UI, native resource generation, automatic source updates, and deferred locale downloads are also outside its scope. The app chooses and stores the user's requested locale.

## License

message_i18n uses the [MIT No Attribution (MIT-0)](LICENSE) license. You may use, modify, and distribute it for any purpose, including commercial projects, without attribution. The software comes without warranty, and each dependency retains its own license.

## README references

The structure of this guide draws on the following widely used pub.dev package READMEs. They are writing references only, not runtime dependencies or performance comparisons.

| Reference | Documentation pattern used |
|---|---|
| [Get](https://pub.dev/packages/get) | Language navigation and feature-oriented sections |
| [Dio](https://pub.dev/packages/dio) | Table of contents, quick start, focused API examples |
| [http](https://pub.dev/packages/http) | Minimal usage followed by ownership and testing guidance |
| [path_provider](https://pub.dev/packages/path_provider) | Clear requirements and capability tables |
| [shared_preferences](https://pub.dev/packages/shared_preferences) | Explicit API behavior and limitations |
| [url_launcher](https://pub.dev/packages/url_launcher) | Complete setup example and configuration caveats |

The English and Korean editions describe the same APIs and workflow.
