# message_i18n_builder

**English** | [한국어](https://github.com/mollacode/message_i18n/blob/main/packages/message_i18n_builder/README.ko.md)

Message-centered localization for Dart and Flutter. Write all translations for a message together in a const Dart catalog, generate a standalone Dart runtime, and share JSON or Excel files with translators.

```dart
// Author translations together.
'common.save': LocalizedMessage({'ko': '저장', 'en': 'Save', 'ja': '保存'})

// Read them in Flutter.
Text(context.tr(MessageKeys.commonSave));
Text(context.format(MessageKeys.welcomeUser, {'name': 'Dart'}));
Text(context.tr('sample.multiline')); // Raw strings are also supported.

// Change the language for subscribed widgets.
context.updateLocale('en-US');
```

`message_i18n` provides the pure Dart core and authoring tools. `message_i18n_flutter` provides the Flutter adapter; neither package contains native platform plugin code.

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

When reviewing a message, it helps to see its translations and placeholder names in one place. A catalog groups translations by message key, so a developer can review a wording change across languages without switching between locale files.

- **One source of truth:** a const Dart catalog is the authoritative source. JSON and XLSX are exchange formats.
- **Validation before generation:** detect missing translations, blank values, invalid locales, and inconsistent placeholders.
- **Separate authoring and runtime:** applications import a generated loader; authoring tools import the catalog.
- **Explicit ownership:** your application owns a resolver and shares it with the Flutter scope or an existing dependency injection system.
- **Reviewable translation imports:** merge creates a candidate and a key comparison report without changing the source.
- **A small Flutter API:** `context.tr`, `context.format`, `context.updateLocale`, and `context.reloadMessages`.

This workflow suits teams that maintain translations in code while exchanging spreadsheets with translators. Keys remain strings: this version does not generate typed message accessors or implement ICU plural rules.

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

The core runs without Flutter. The Flutter adapter depends on the core; neither package requires Riverpod or GetX. The authoring CLI runs on your development machine using filesystem and process APIs; it is not a browser API. Applications use the generated runtime loader.

## Quick start

Use `build_runner` for the default development workflow. If your app already uses other generators, the same build/watch command runs them together. `MessageI18nTool` remains available as an optional, compatible CLI workflow.

### 1. Install the packages

Run `dart pub add message_i18n` for Dart, or `flutter pub add message_i18n message_i18n_flutter` for Flutter. Add these development dependencies to the application's `pubspec.yaml`, then run `dart pub get` or `flutter pub get`:

```yaml
dev_dependencies:
  message_i18n_builder: ^0.1.0
  build_runner: '>=2.16.2 <2.17.0'
```

The builder supports build 4.x. The integration baseline with go_router_builder is build_runner 2.16.2; blindly combining the newest versions can conflict on the build major version.

For Flutter's built-in widget localization, also add:

```yaml
dependencies:
  flutter_localizations:
    sdk: flutter
```

### 2. Write the source catalog

Create `lib/i18n/catalog.dart`; the filename is your choice. Do not import this source into application runtime. Annotate one top-level const catalog per input library:

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
  },
);
```

Every supported locale needs a nonblank translation. The default must be supported and placeholder names must agree across translations. Imported constants and const map spreads are resolved statically.

#### Message key rules

A catalog key is the exact string used for lookup. Follow these rules when writing it:

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

Rename an invalid or colliding source key, then run build again. The validator never rewrites a key automatically. When migrating an existing key, update the catalog key and every raw-string reference; generated member references update after the next build. The generated constants section below explains how to use the resulting fields.

#### Placeholder and format parameter rules

Write a replaceable value as `{identifier}`. An identifier must match `[A-Za-z_][A-Za-z0-9_]*`: it starts with an ASCII letter or underscore and then uses ASCII letters, digits or underscores. Names are case-sensitive. The lowercase message-key rule does not apply to placeholders, so a name such as `{userName}` is valid.

Every translation of one message must use the same set of placeholder names. Their order and repetition count may differ by language, and the same placeholder may appear more than once in one translation.

Pass a `Map<String, String>` whose keys exactly match the placeholder names:

```dart
final text = messages.format(
  MessageKeys.welcomeUser,
  {'name': 'Dart'},
);
// With the English catalog above: Welcome, Dart.
```

A missing argument leaves that placeholder in the result and emits `missing_argument`. An unused argument is ignored and emits `extra_argument`. Convert numbers, dates and other values to strings in the application before passing them.

Positional placeholders such as `{0}`, empty or unmatched braces, nested braces and ICU plural/select/gender syntax fail catalog validation. There is no syntax for escaping braces in this version.

### 3. Validate and generate

Run from the application root. No `tool/i18n.dart` entrypoint is required:

```bash
dart run build_runner build
```

This validates the catalog and creates `lib/i18n/catalog.message_i18n.g.dart`, an independent runtime library. Do not connect it to the source using `part`.

The output name follows the source name. For example, `lib/i18n/account.dart` produces `lib/i18n/account.message_i18n.g.dart`. Changing the source filename or location is fine as long as imports point to the corresponding generated file.

### Generated runtime contents

Each annotated source catalog produces one standalone generated library. For the catalog above, the generated file contains these declarations:

| Generated item | What it does | Short example |
|---|---|---|
| `supportedMessageLocales` | A `List<String>` copied from the catalog's `supportedLocales`. Use it when configuring the locales supported by a Flutter app. | `messageLocales(supportedMessageLocales)` |
| `defaultMessageLocale` | The catalog's `defaultLocale`. Generated locale resolution uses it when a request cannot be matched. | `createMessageResolver(selected: defaultMessageLocale)` |
| `resolveGeneratedLocale(requested)` | Resolves a requested locale against the generated supported and default locales. | `resolveGeneratedLocale('en-US') // 'en'` |
| `loadGeneratedMessages(requested)` | Resolves a locale and returns its generated locale name and message map as `GeneratedLocaleMessages`. | `loadGeneratedMessages('ko-KR').messages` |
| `createMessageResolver(...)` | Creates the app-owned `MessageResolver` backed by the generated loader. An optional `onDiagnostic` callback receives runtime diagnostics. | `createMessageResolver(selected: 'ko-KR')` |
| `MessageKeys` | Contains one `static const String` for every catalog key. The value remains the exact source key. | `messages.text(MessageKeys.commonSave)` |
| `load<Locale>Messages()` | Returns the generated message map for one supported locale. One function is generated per locale, such as `loadEnMessages()` and `loadKoMessages()`. | `loadKoMessages()[MessageKeys.commonSave]` |

Most applications use `createMessageResolver`, `MessageKeys`, and `supportedMessageLocales`. The resolution and loader functions are available for advanced integration, diagnostics, and tests; normal lookup should go through `MessageResolver`.

If you import a generated library with a prefix, access all of its generated declarations through that prefix:

```dart
import 'i18n/catalog.message_i18n.g.dart' as appI18n;

final messages = appI18n.createMessageResolver(selected: 'en-US');
final locales = appI18n.supportedMessageLocales;
final title = messages.text(appI18n.MessageKeys.appTitle);
```

Each source catalog still produces a separate runtime library. An import prefix disambiguates declarations; it does not merge catalogs or resolvers.

### 4. Use the generated runtime

After generation, use it from `lib/main.dart`. Flutter composition is shown in the next section.

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

The same build that creates the runtime library also creates `MessageKeys`. Each field is a `static const String` whose value is the exact catalog key:

```dart
abstract final class MessageKeys {
  static const String appTitle = 'app.title';
  static const String commonSave = 'common.save';
  static const String welcomeUser = 'welcome.user';
}
```

Both forms are supported:

| Form | Use it when |
|---|---|
| `context.tr(MessageKeys.appTitle)` | The key is known at compile time. Misspelled, deleted or renamed generated members become compile errors. |
| `context.tr('app.title')` | The key is dynamic or the application is migrating gradually. Missing keys are reported by the normal runtime diagnostic. |

The Builder first checks the source-key grammar described above. It then converts valid key segments separated by dots, hyphens or underscores to lowerCamelCase. It never invents a prefix, suffix, number, hash or alias. Generation fails when different valid keys produce the same member, or when the result is a Dart keyword or an inherited `Object` member.

```text
a.a, a_a, a-a  -> MessageKeys.aA  -> build failure
class           -> MessageKeys.class -> build failure
123.title       -> invalid_key -> build failure before constant generation
```

Rename the catalog key and run build again. A failed build does not emit a partial `MessageKeys` class. Constants appear after the initial build and update whenever build or watch processes a catalog change. Removing or renaming a key removes its generated member, so remaining constant references fail during analysis or compilation.

Each generated catalog library declares its own `MessageKeys`. When an application consumes more than one, use import prefixes and use each key with the resolver created by the same generated library:

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

During development, leave this single command running. Installed Freezed, router and JSON builders also participate as their inputs change:

```bash
dart run build_runner watch
```

## Flutter setup

The Flutter app also imports only the generated loader. `supportedMessageLocales` in the example below is generated from the catalog's `supportedLocales`; `defaultMessageLocale` and the other generated declarations are listed in [Generated runtime contents](#generated-runtime-contents). `MessageI18nTool` and the source catalog remain in development code; see [Authoring and code generation](#authoring-and-code-generation). The following `lib/main.dart` uses the generated messages:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:message_i18n_flutter/message_i18n_flutter.dart';
import 'i18n/catalog.message_i18n.g.dart';

void main() {
  final resolver = createMessageResolver(selected: 'ko-KR');
  runApp(MessageI18nScope(resolver: resolver, child: const MyApp()));
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
            Text(context.tr('sample.multiline')),
            TextButton(
              onPressed: () => context.updateLocale('en-US'),
              child: const Text('English'),
            ),
          ],
        ),
      ),
    ),
  );
}
```

Place `MessageI18nScope` above `MaterialApp` so routes, nested navigators, dialogs, bottom sheets, and overlays can share it. A context above the scope cannot read it.

`flutter_localizations` and its delegates are configured by the consumer. The library translates your messages; it does not automatically configure built-in Material/Cupertino labels. `messageLocale` preserves script and country subtags when converting a locale string to Flutter's `Locale`.

Read translations in `build`, or recompute cached labels in `didChangeDependencies`. A string saved once in `initState` will not change when the language changes.

## Runtime API and locale behavior

| Dart resolver | Flutter API | Behavior |
|---|---|---|
| `text(key)` | `context.tr(key)` | Look up a message |
| `format(key, arguments)` | `context.format(key, arguments)` | Substitute named string arguments |
| `select(locale)` | `context.updateLocale(locale)` | Load a locale and notify listeners |
| `reload()` | `context.reloadMessages()` | Reload the last requested locale and notify listeners |
| `locale` / `selected` | `context.i18n.locale` / `.selected` | Resolved locale / original request |
| `addListener` / `removeListener` | Scope manages its subscription | Subscribe outside Flutter |

`tr`, `format`, and `context.i18n` register a widget dependency. `updateLocale` and `reloadMessages` use non-listening access. `MessageI18nScope.read(context)` is also available for non-listening access; `of` listens and `maybeOf` allows an absent scope.

### Locale selection

Normalization accepts a two- or three-letter language, an optional four-letter script, and an optional two-letter or three-digit region:

| Input | Normalized |
|---|---|
| `en_US` | `en-US` |
| `zh_hant_tw` | `zh-Hant-TW` |
| `ko-KR` | `ko-KR` |

Selection tries the exact locale, removes trailing subtags one at a time, then uses the catalog default. For example, `zh-Hant-TW → zh-Hant → zh → default`, choosing the first supported entry. Unsupported variants, extensions, or segment order throw `FormatException`; an invalid locale is not treated as an ordinary fallback request.

The resolver retains one current message map and replaces it on selection or reload. There is no per-message fallback map or all-locale map cache. This does **not** guarantee that other locale strings are absent from the application binary or the entire VM heap.

### Placeholders and diagnostics

Only `{identifier}` placeholders are supported, with names matching `[A-Za-z_][A-Za-z0-9_]*`. Arguments are `Map<String, String>`. Brace escaping, nested expressions, ICU plural/select/gender, and automatic number/date formatting are outside this version's scope.

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

Diagnostics carry code, key, and locale. Strict catalog checks catch translation problems before generation. `MessageResolver.fromLoader` is a lower-level API for loader bridges and test fakes; applications normally use the generated factory.

## State management and ownership

Choose one owner and one subscription mechanism for the application-wide resolver. The built-in scope, Riverpod, and GetX integrations below are alternatives; do not wrap the state-management examples in `MessageI18nScope`.

### Built-in MessageI18nScope

Without another state manager, create one resolver at the composition root and pass it to `MessageI18nScope` above `MaterialApp`. The scope subscribes to the external resolver but neither creates nor disposes it. Widgets use `context.tr`, `context.format`, `context.updateLocale`, and `context.reloadMessages` as shown in [Flutter setup](#flutter-setup).

Those context extensions require a `MessageI18nScope` ancestor. The Riverpod and GetX integrations instead call the resolver through their own provider or controller, so they do not use the context extensions.

### Riverpod

The consumer application adds `flutter_riverpod`. `ProviderScope` owns the provider container, a `NotifierProvider` owns one generated resolver, and watched immutable state rebuilds both `MaterialApp.locale` and message widgets. Always change or reload the locale through the notifier; calling the resolver directly would bypass Riverpod's state publication.

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

class RiverpodApp extends ConsumerWidget {
  const RiverpodApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          Text(messages.text(MessageKeys.appTitle)),
          Text(
            messages.format(
              MessageKeys.welcomeUser,
              {'name': 'Dart'},
            ),
          ),
          TextButton(
            onPressed: () => controller.select('en-US'),
            child: const Text('English'),
          ),
          TextButton(
            onPressed: controller.reload,
            child: const Text('Reload'),
          ),
        ],
      ),
    );
  }
}
```

`MessagesState` creates a new wrapper after a successful `select` or `reload`, so `ref.watch` observes a new state even though the application deliberately keeps the same resolver instance. If locale loading throws, the new state assignment is not reached and the previous resolver state remains active.

### GetX

The consumer application adds `get`. `GetMaterialApp` supplies the GetX root, `initialBinding` registers one application-wide controller, and `GetBuilder` subscribes message widgets. The controller updates GetX's root locale after the resolver has successfully selected a locale, then calls `update()` for message widgets.

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
    Get.updateLocale(messageLocale(_resolver.locale));
    update();
  }

  void reload() {
    _resolver.reload();
    update();
  }
}

class AppBinding extends Bindings {
  @override
  void dependencies() {
    Get.put<MessagesController>(MessagesController(), permanent: true);
  }
}

void main() => runApp(
  GetMaterialApp(
    initialBinding: AppBinding(),
    locale: messageLocale(defaultMessageLocale),
    supportedLocales: messageLocales(supportedMessageLocales),
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: const GetXMessagesPage(),
  ),
);

class GetXMessagesPage extends StatelessWidget {
  const GetXMessagesPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: GetBuilder<MessagesController>(
      builder: (messages) => Column(
        children: [
          Text(messages.text(MessageKeys.appTitle)),
          Text(
            messages.format(
              MessageKeys.welcomeUser,
              {'name': 'Dart'},
            ),
          ),
          TextButton(
            onPressed: () => messages.select('en-US'),
            child: const Text('English'),
          ),
          TextButton(
            onPressed: messages.reload,
            child: const Text('Reload'),
          ),
        ],
      ),
    ),
  );
}
```

The controller calls `Get.updateLocale` for Flutter's localized Material/Cupertino resources and `update()` for `GetBuilder` message consumers. This package does not register GetX `translations` and does not provide a `String.tr` extension; use the controller's `text` and `format` methods to avoid confusion with GetX's own localization API.

Riverpod and GetX remain optional consumer dependencies. The message_i18n packages do not depend on either state manager.

## Authoring and code generation

`message_i18n_builder` statically reads annotated constants and uses the shared validator. It does not execute your application or `MessageI18nTool`. The output keeps locale factories and the loader in one file while preserving the runtime's current-locale Map behavior.

### Builder paths and filenames

| Change | Update |
|---|---|
| catalog.dart → messages.dart | App import becomes messages.message_i18n.g.dart |
| Move the catalog directory | App generated import and generate_for, if configured |
| Rename the catalog variable | Keep the annotation; the generated loader API stays the same |
| Inputs outside lib | Include them in build target sources and generate_for |

Default inputs are Dart files under lib, excluding generated files. Annotate one catalog per library. Use import prefixes when consuming multiple generated libraries. Output sits beside the source with a fixed suffix; CLI generatedDirectory/sourcePaths/watchEntrypoint settings do not configure the Builder.

Optionally narrow inputs in the consumer's build.yaml:

```yaml
targets:
  $default:
    builders:
      message_i18n_builder:
        generate_for:
          - lib/localization/messages.dart
```

### Optional CLI and existing projects

The configuration below is for catalog-only check, JSON/XLSX export/merge, or retaining legacy CLI generation. It is not required for the default Builder workflow. To migrate, add the annotation and development dependencies, build, then change the app import. The old generated directory is not automatically deleted. Do not run both watchers together.

To use the optional CLI, create `tool/i18n.dart`:

```dart
import 'package:message_i18n/message_i18n_tool.dart';
import '../lib/i18n/catalog.dart';

Future<void> main(List<String> args) => MessageI18nTool(
  catalog: appCatalog,
  sourcePaths: const ['lib/i18n'],
  generatedDirectory: 'lib/i18n/generated',
  watchEntrypoint: 'tool/i18n.dart',
).run(args);
```

### Legacy CLI configuration details

`MessageI18nTool` connects the authoring side of the package to its generated runtime. It receives a const `MessageCatalog` object directly and provides validation, generation, watching, export, and merge commands. It runs only when a developer or CI invokes the tool entrypoint; it does not run when the application starts.

#### Development lifecycle

```text
one-time setup:  catalog file + tool entrypoint + initial generate
ongoing work:    edit catalog → generate, or edit catalog → watch auto-generation
application:     generated loader → resolver → Dart or Flutter UI
CI:              check --verify-generated
translation:     export → external edit → merge candidate → human review → catalog
```

Creating the catalog file and tool entrypoint is normally a one-time setup. The catalog contents are not one-time configuration: they remain the authoritative source and are edited whenever messages or locales change. Those changes must be followed by `generate`, unless `watch` is already running and performs the generation cycle automatically.

#### Tool configuration

| Argument | Role |
|---|---|
| `catalog` | The authoritative `MessageCatalog` object already imported by the tool entrypoint. It is not a file path. |
| `sourcePaths` | Existing project directories watched for `.dart` changes by `watch`. They do not discover catalog objects. |
| `generatedDirectory` | A dedicated directory inside the project for generated locale files, loader, and manifest. Do not place hand-written files there. |
| `watchEntrypoint` | The project-relative Dart entrypoint launched in a fresh process for each watch generation cycle. The current CLI also checks that this file exists before every public command. |
| `projectRoot` | Base directory for relative paths and file-safety checks. It defaults to the current directory. |

#### Custom paths and filenames

`lib/i18n/catalog.dart`, `tool/i18n.dart`, and `lib/i18n/generated/` are examples, not required names. A different layout works when its Dart imports, tool settings, commands, and runtime imports agree. For example:

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

Run that entrypoint by its actual path:

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

A catalog outside `sourcePaths` can still be imported when you invoke `generate` directly, but `watch` will not observe changes outside its configured directories. All relative paths are resolved from `projectRoot`. Keep the generated directory inside the project and dedicated to tool-owned output.

#### Manual generation or watch

For explicit generation after a catalog change:

```bash
dart run tool/i18n.dart generate
```

For automatic generation while editing:

```bash
dart run tool/i18n.dart watch
```

`watch` performs an initial generation and then observes `.dart` files under `sourcePaths`. Application code always consumes the generated loader; it never imports the authoring catalog or tool entrypoint.

## CLI reference

Run every command from the consumer application's root, where `pubspec.yaml` and the configured tool entrypoint exist:

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

`check` validates locale identifiers, the default and supported locale relationship, message keys, missing or blank translations, and placeholder syntax and consistency. It does not write generated files. Add `--verify-generated` in CI to generate expected output in a temporary directory and compare each expected tool-owned file with `generatedDirectory`; it fails when generated files are missing, modified, or stale.

### `generate`: write runtime files

```bash
dart run tool/i18n.dart generate
dart run tool/i18n.dart generate --output lib/i18n/generated
```

`generate` validates the catalog and writes one Dart message file per locale, `message_loader.g.dart`, and `message_i18n_manifest.json`. The optional `--output` overrides `generatedDirectory` for that run and must name a dedicated directory inside the project. Generation stages and formats complete files before replacing tool-owned output. The manifest controls stale-file deletion; the command refuses to overwrite files it does not own.

Run `generate` after changing the catalog, supported locales, or generation settings. Application code then continues to import the same generated loader path.

### `watch`: regenerate while editing

```bash
dart run tool/i18n.dart watch
dart run tool/i18n.dart watch --debounce-ms 400
```

`watch` performs an initial generation, then watches `.dart` files under `sourcePaths`. It groups rapid changes using a 250 ms debounce by default and runs generation cycles serially in fresh Dart processes. Generated output, `build/`, and `.dart_tool/` are excluded to prevent loops. A failed cycle preserves the last successful output and keeps watching so the next valid edit can recover. Stop it with `Ctrl+C`.

After a successful cycle, use Flutter hot reload for message text changes. Use hot restart when locale structure or generated imports change.

### `export`: create translator files

```bash
dart run tool/i18n.dart export --locales ko,en --format json
dart run tool/i18n.dart export --locales ko,en --format xlsx --output build/translations.xlsx
dart run tool/i18n.dart export --locales ko,en --format xlsx --split-by-locale
```

`--locales` is a comma-separated list of supported locales and `--format` is `json` or `xlsx`; both are required. Without `--output`, the command creates a new timestamped directory under `build/message_i18n/exports/`. For one combined file, `--output` must have the selected format's extension. With `--split-by-locale`, `--output` is a directory and the command writes one file per locale. Existing export destinations are not overwritten.

### `merge`: create a review candidate

```bash
dart run tool/i18n.dart merge --input build/translations.json
dart run tool/i18n.dart merge \
  --input build/ko.xlsx \
  --input build/en.xlsx \
  --output build/message_i18n/review
```

Repeat `--input` for each `.json` or `.xlsx` file. When the same key and locale occurs more than once, the later input wins and the tool prints a warning. The output must be a new directory under the project's `build/` directory. It contains `merged_catalog.dart` and `key-comparison.json`.

`merge` never edits the source catalog and does not fill values absent from the inputs with source values. Review the candidate, the key comparison, and all warnings, then manually apply accepted changes to `catalog.dart` and run `check` and `generate` again.

### Help, version, and exit codes

```bash
dart run tool/i18n.dart --help
dart run tool/i18n.dart <command> --help
dart run tool/i18n.dart --version
```

Exit code **0** means success, **1** means a validation, input structure, parsing, process, or file operation failure, and **64** means invalid command usage. Normal results go to stdout; errors and merge warnings go to stderr. `__watch-cycle` is an internal command used by `watch` and should not be invoked directly.

Strict validation reports `invalid_locale`, `empty_locales`, `duplicate_locale`, `missing_default`, `invalid_key`, `unsupported_locale`, `empty_translation`, `missing_translation`, `unsupported_placeholder`, and `placeholder_mismatch`. Issues are sorted by severity, key, locale, then code. Dart itself rejects duplicate const map keys and incompatible value types before the tool can run.

## Translation workflow

### 1. Export a validated catalog

```bash
dart run tool/i18n.dart export --locales ko,en --format json --output build/translations.json
dart run tool/i18n.dart export --locales ko,en --format xlsx --output build/translations.xlsx
dart run tool/i18n.dart export --locales ko,en --format xlsx --split-by-locale
```

Without an explicit destination, exports go under `build/message_i18n/exports/<timestamp>/`. A single output is a file with the matching extension; split output is a directory. Existing files are not overwritten. Automatically allocated directories use suffixes when names collide.

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

The first header must be exactly `key`; locale columns follow the requested order. There are no description, source-path, or hidden metadata columns. Keep cells as text: numeric and formula cells are rejected. Exported values beginning with `=`, `+`, `-`, or `@` are explicitly stored as text.

Duplicate normalized locale headers or duplicate key rows are structural errors. Completely empty rows are ignored; nonempty rows without keys are rejected. Blank translation cells are read as empty strings.

### 2. Merge returned files

```bash
dart run tool/i18n.dart merge --input build/translations.json --input build/translations.xlsx
```

The output directory defaults to `build/message_i18n/merges/<timestamp>/` and contains:

- `merged_catalog.dart`: a standalone `mergedCatalog` candidate.
- `key-comparison.json`: sorted key differences relative to the original catalog.

**Merge uses only the supplied inputs.** It does not update the original or fill missing keys/translations from it. For overlapping key/locale pairs, the last input wins and a warning identifies the previous and final input numbers. Thus, importing only English does not silently restore Korean and Japanese from the original catalog.

Missing languages, blank values, placeholder differences, and key differences produce warnings or reports but do not prevent a candidate from being created. Successful candidate creation returns exit code 0; it does not mean the candidate passes strict validation. Malformed files and I/O failures return 1. Output must remain under the consumer's `build/` directory.

Key comparison checks key sets, not translation equality. The current human-readable report uses Korean:

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

The first section lists original-only keys; the second lists merged-only keys. The machine-readable equivalent is:

```json
{"matched":false,"originalOnly":["old.key"],"mergedOnly":["new.key"]}
```

### 3. Review and apply

Review warnings, translations, and key differences. Manually apply approved changes to the original Dart catalog, then run `dart run build_runner build`. For legacy CLI generation, use `check`, `generate`, and `check --verify-generated`. The tool intentionally has no command to apply a candidate automatically.

## Generated files and recovery

A failed build can remove the previous output file. Fix the source and wait for successful regeneration before reloading the app.

The Builder's `.message_i18n.g.dart` paths are reserved for build_runner. Do not put hand-written files there: build can replace modified output. `build --only-check` reports differences without writing or deleting public output files; internal `.dart_tool` cache activity is separate. Invalid catalogs fail the build; fix them and rebuild or let watch recover. The legacy CLI rollback guarantee does not apply to Builder-managed outputs.

### Legacy CLI file ownership


Treat the generated directory as tool output. The manifest records the schema, catalog fingerprint, locales, key count, and owned files. Do not edit generated translations; update the catalog and regenerate.

You can commit generated files for review and reproducibility, or generate them before analysis and build. If you commit them, CI can detect stale output with `check --verify-generated`.

Generation validates, stages, formats, and checks the target snapshot before replacing owned files. Replacement uses **per-file rename with rollback on failure**, not an atomic swap of the whole file set. Unowned files are preserved; stale cleanup is limited to manifest-owned files. Path escapes, symlinks, and attempts to claim non-generated files are rejected.

An OS lock prevents concurrent generation to the same target. A zero-byte sibling guard such as `.generated.message_i18n.lock` remains on disk and is ignored by Git; the OS releases its lock when the process exits. Do not delete the guard to bypass contention. After a hard kill or power loss, use `check --verify-generated` and regenerate if necessary; whole-set recovery from every abrupt interruption is not guaranteed.

## Watch and hot reload

In a separate terminal, run:

```bash
dart run build_runner watch
```

build_runner tracks changed inputs and their dependencies. Diagnose a failed build and correct the source to recover within the same watch session. Stop with Ctrl-C. Other installed builders share the same watcher.

After generation succeeds, trigger Flutter hot reload yourself. To refresh an existing resolver, add the following hook to the application-owned `State` that holds it:

```dart
@override
void reassemble() {
  super.reassemble();
  resolver.reload();
}
```

| Change | Development action |
|---|---|
| Existing translation text | Generate, then hot reload with `resolver.reload()` |
| New message key and its usage | Generate, then hot reload |
| Supported locales or initialization structure | Generate, then hot restart |

The watcher does not connect to the Flutter daemon or trigger reload automatically. Reload does not re-run `main`, `initState`, or existing static initialization; see [Flutter's hot reload documentation](https://docs.flutter.dev/tools/hot-reload).

## Troubleshooting

| Symptom | Check or action |
|---|---|
| A message key appears instead of text | Check the key and `missing_key` diagnostic; regenerate after catalog changes |
| `{name}` remains visible | Supply `name` as a string argument to `format` |
| A requested locale resolves to another locale | Inspect `selected`, `locale`, and the supported-locale fallback chain |
| Widgets keep the previous language | Read inside `build`/`didChangeDependencies`; share one resolver and place the scope above routes |
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

If generated files are ignored by Git, build first, then analyze/test/build the application. A subsequent only-check verifies the just-generated outputs, not the freshness of committed files. Missing outputs correctly fail only-check. Legacy CLI check --verify-generated only checks its multi-file/manifest format.

The joint integration baseline is build_runner 2.16.2, build 4.0.11, Freezed 4.0.3, go_router_builder 4.5.2, go_router 18.1.1 and json_serializable 6.15.2. That combined fixture uses Dart 3.13 and Flutter 3.47. The Builder itself requires Dart 3.11. Verify both dependency resolution and execution of generated code.

## Scope and limitations

This version generates String key constants, but does not provide typed placeholder functions. It also does not provide ICU plurals/gender, remote translation delivery, a translation web UI, native resource generation, automatic source application, or deferred locale downloads. Applications choose and persist the requested locale themselves.

## License

Licensed under [MIT No Attribution (MIT-0)](LICENSE). You may use, modify, and distribute this software for any purpose, including commercial use, without an attribution requirement. It is provided without warranty. Dependencies retain their own licenses.

## README references

Documentation structure was inspired by these widely used pub.dev package READMEs. These are presentation references, not runtime dependencies or performance comparisons.

| Reference | Documentation pattern used |
|---|---|
| [Get](https://pub.dev/packages/get) | Language navigation and feature-oriented sections |
| [Dio](https://pub.dev/packages/dio) | Table of contents, quick start, focused API examples |
| [http](https://pub.dev/packages/http) | Minimal usage followed by ownership and testing guidance |
| [path_provider](https://pub.dev/packages/path_provider) | Clear requirements and capability tables |
| [shared_preferences](https://pub.dev/packages/shared_preferences) | Explicit API behavior and limitations |
| [url_launcher](https://pub.dev/packages/url_launcher) | Complete setup example and configuration caveats |

The English and Korean editions describe the same APIs and workflow.
