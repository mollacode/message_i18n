# message_i18n_builder

[English](https://github.com/mollacode/message_i18n/blob/main/packages/message_i18n_builder/README.md) | **한국어**

Dart와 Flutter를 위한 메시지 중심 다국어 라이브러리입니다. 하나의 const Dart catalog에 메시지별 번역을 함께 작성하고, 독립 Dart runtime 파일을 생성하며, 번역 담당자와 JSON 또는 Excel 파일을 교환할 수 있습니다.

```dart
// 메시지 하나의 번역을 함께 작성합니다.
'common.save': LocalizedMessage({'ko': '저장', 'en': 'Save', 'ja': '保存'})

// Flutter에서 번역을 조회합니다.
Text(context.tr(MessageKeys.commonSave));
Text(context.format(MessageKeys.welcomeUser, {'name': 'Dart'}));
Text(context.tr('sample.multiline')); // 문자열 key도 지원합니다.

// 구독 중인 위젯의 언어를 변경합니다.
context.updateLocale('en-US');
```

`message_i18n`은 순수 Dart core와 작성 도구를 제공합니다. `message_i18n_flutter`는 Flutter 어댑터를 제공하며 두 패키지 모두 네이티브 플랫폼 플러그인 코드를 포함하지 않습니다.

## 목차

- [메시지 중심 catalog의 장점](#메시지-중심-catalog의-장점)
- [패키지와 요구사항](#패키지와-요구사항)
- [빠른 시작](#빠른-시작)
- [Flutter 설정](#flutter-설정)
- [Runtime API와 locale 동작](#runtime-api와-locale-동작)
- [상태 관리와 소유권](#상태-관리와-소유권)
- [개발용 catalog와 코드 생성](#개발용-catalog와-코드-생성)
- [CLI 명령](#cli-명령)
- [번역 작업 흐름](#번역-작업-흐름)
- [생성 파일과 복구](#생성-파일과-복구)
- [Watch와 hot reload](#watch와-hot-reload)
- [문제 해결](#문제-해결)
- [CI 연동](#ci-연동)
- [지원 범위와 제한](#지원-범위와-제한)
- [라이선스](#라이선스)
- [README 참고 자료](#readme-참고-자료)

## 메시지 중심 catalog의 장점

메시지 하나를 검토할 때 여러 언어의 문구와 placeholder를 한곳에서 비교할 수 있습니다. 언어별 파일을 오가며 확인하는 대신, 메시지 키 아래에서 번역을 함께 관리합니다.

- **단일 원본:** const Dart catalog가 기준이며 JSON/XLSX는 교환 형식입니다.
- **생성 전 검증:** 번역 누락, 빈 값, 잘못된 locale, placeholder 불일치를 검사합니다.
- **작성 도구와 runtime 분리:** 앱은 generated loader를, 작성 도구는 catalog를 import합니다.
- **명확한 소유권:** 앱이 resolver를 소유하고 Flutter scope 또는 기존 DI 도구와 공유합니다.
- **검토 가능한 번역 반영:** merge는 원본을 수정하지 않고 후보와 키 비교 보고서를 생성합니다.
- **간결한 Flutter API:** `context.tr`, `context.format`, `context.updateLocale`, `context.reloadMessages`를 제공합니다.

코드에서 번역을 관리하면서 번역 담당자와 스프레드시트를 교환하는 팀에 적합합니다. 메시지 키는 문자열이며, 현재 버전은 타입 안전 접근자나 ICU 복수형 규칙을 생성하지 않습니다.

```text
const Dart catalog ── check / generate ──> 언어별 생성 파일 + loader
        │                                           │
        │ export                                    ▼
        ▼                                  앱 소유 MessageResolver
     JSON / XLSX                                    │
        │ merge                                     ▼
        ▼                                   MessageI18nScope
   후보 + 키 비교 보고서                            │
        │ 사람이 검토                               ▼
        └────────────> catalog 수정          context.tr / format
```

## 패키지와 요구사항

| 패키지 | 역할 | 선언된 최소 버전 |
|---|---|---|
| `message_i18n` | Dart 모델, runtime, 검증, 생성, 번역 교환 도구 | Dart 3.11 |
| `message_i18n_builder` | 개발용 Builder와 const catalog 분석 | Dart 3.11 |
| `message_i18n_flutter` | Flutter scope, context 확장, locale 변환 | Dart 3.11 / Flutter 3.47 |

core는 Flutter 없이 동작합니다. Flutter 어댑터는 core에 의존하며, 두 패키지 모두 Riverpod나 GetX를 필수로 요구하지 않습니다. 작성용 CLI는 파일 시스템과 프로세스 API를 사용해 개발 환경에서 실행합니다. 브라우저용 API가 아니며, 앱에서는 생성된 runtime loader를 사용합니다.

## 빠른 시작

기본 개발 흐름은 `build_runner`입니다. 다른 생성기를 이미 사용한다면 같은 build/watch 명령으로 함께 실행할 수 있습니다. 기존 `MessageI18nTool`은 선택적인 CLI 호환 경로로 유지합니다.

### 1. 패키지 설치

Dart 앱에는 `dart pub add message_i18n`, Flutter 앱에는 `flutter pub add message_i18n message_i18n_flutter`를 실행합니다. 앱의 `pubspec.yaml`에 다음 개발 의존성을 추가하고 `dart pub get` 또는 `flutter pub get`을 실행합니다.

```yaml
dev_dependencies:
  message_i18n_builder: ^0.1.0
  build_runner: '>=2.16.2 <2.17.0'
```

Builder는 build 4 계열을 지원합니다. 현재 go_router_builder와 함께 쓰는 기준은 build_runner 2.16.2입니다. 최신 버전들을 무조건 함께 지정하면 build 메이저 제약이 충돌할 수 있습니다.

Flutter 기본 위젯도 지역화하려면 다음 SDK 의존성을 추가하세요.

```yaml
dependencies:
  flutter_localizations:
    sdk: flutter
```

### 2. 원본 catalog 작성

`lib/i18n/catalog.dart`에 작성합니다. 파일명은 자유롭게 바꿀 수 있습니다. 원본은 앱 runtime에서 import하지 않습니다. 입력 library당 top-level const catalog 하나에 annotation을 붙입니다.

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

모든 지원 언어에 비어 있지 않은 번역이 필요합니다. 기본 언어는 지원 목록에 있어야 하고, placeholder 이름 집합은 언어별로 같아야 합니다. Import한 const와 Map spread도 정적으로 해석합니다.

#### 메시지 key 규칙

Catalog key는 조회에 사용하는 정확한 문자열입니다. 다음 규칙에 맞춰 작성합니다.

- Key는 `^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$` 형식이어야 합니다.
- 시작 문자는 ASCII 소문자여야 합니다. 각 구간에는 ASCII 소문자와 숫자만 사용할 수 있으며 구간은 점, 하이픈 또는 밑줄 하나로 구분합니다.
- 공백, 대문자, 비 ASCII 문자, 다른 기호, 시작·마지막 구분자와 연속된 구분자는 사용할 수 없습니다.
- `feature.action`처럼 의미가 안정적인 이름을 사용합니다. 점 구분 형식은 권장 방식이며 필수 문법은 아닙니다.
- 유효한 key는 Builder가 구분자를 제거하고 lowerCamelCase `MessageKeys` field로 합칩니다.
- 생성 field는 `[A-Za-z$][A-Za-z0-9$]*` 형식이어야 하며 Dart 예약어나 `hashCode` 같은 상속된 `Object` instance member일 수 없습니다.
- 변환된 field 이름은 모두 고유해야 합니다. Builder는 이름을 고치기 위한 접두사·접미사·번호·hash·별칭을 추가하지 않습니다.

```text
app.title       -> appTitle       (유효)
welcome-user    -> welcomeUser    (유효)
App.title       -> invalid_key    (대문자; 검증 실패)
한국어.제목      -> invalid_key    (비 ASCII; 검증 실패)
app..title      -> invalid_key    (연속 구분자; 검증 실패)
app.title-      -> invalid_key    (마지막 구분자; 검증 실패)
a.a, a_a, a-a  -> aA             (충돌; build 실패)
class           -> class          (예약어; build 실패)
123.title       -> 123Title       (유효하지 않음; build 실패)
```

유효하지 않거나 충돌하는 원본 key를 직접 수정한 뒤 build를 다시 실행합니다. Validator는 key를 자동으로 변경하지 않습니다. 기존 key를 변경할 때에는 catalog key와 모든 raw string 참조를 함께 수정해야 하며, generated member 참조는 다음 build 후 갱신됩니다. 생성된 field의 사용법은 아래 메시지 key 상수 절에서 설명합니다.

#### Placeholder와 format parameter 규칙

치환할 위치는 `{identifier}`로 작성합니다. Identifier는 `[A-Za-z_][A-Za-z0-9_]*` 형식이어야 합니다. 첫 문자는 영문자 또는 밑줄이고, 이후에는 영문자·숫자·밑줄을 사용할 수 있습니다. 이름은 대소문자를 구분합니다. Message key의 소문자 규칙은 placeholder에 적용되지 않으므로 `{userName}` 같은 이름은 유효합니다.

한 message의 모든 언어는 같은 placeholder 이름 집합을 사용해야 합니다. 언어에 따라 나타나는 순서와 반복 횟수는 달라도 되며, 같은 placeholder를 한 번역에서 여러 번 사용할 수 있습니다.

Placeholder 이름과 정확히 일치하는 key를 가진 `Map<String, String>`을 전달합니다.

```dart
final text = messages.format(
  MessageKeys.welcomeUser,
  {'name': 'Dart'},
);
// 위 catalog의 영어 결과: Welcome, Dart.
```

인자가 누락되면 해당 placeholder를 결과에 그대로 남기고 `missing_argument`를 전달합니다. 사용하지 않는 인자는 무시하고 `extra_argument`를 전달합니다. 숫자·날짜 등 다른 타입의 값은 앱에서 문자열로 변환한 뒤 전달합니다.

`{0}` 같은 위치 placeholder, 비었거나 짝이 맞지 않는 brace, 중첩 brace와 ICU plural/select/gender 문법은 catalog 검증에 실패합니다. 현재 버전에는 brace를 escape하는 문법이 없습니다.

### 3. 검증과 최초 생성

앱 루트에서 실행합니다. 별도의 `tool/i18n.dart`는 필요하지 않습니다.

```bash
dart run build_runner build
```

검증 후 `lib/i18n/catalog.message_i18n.g.dart`를 생성합니다. 이 파일은 원본과 `part`로 연결하지 않는 독립 runtime library입니다.

출력 파일명은 원본 파일명을 따릅니다. 예를 들어 `lib/i18n/account.dart`에서는 `lib/i18n/account.message_i18n.g.dart`가 생성됩니다. 원본 파일명이나 위치를 바꿔도 해당 generated 파일을 올바르게 import하면 됩니다.

### 생성되는 runtime 항목

Annotation을 붙인 원본 catalog마다 독립된 generated library 하나가 생성됩니다. 위 catalog의 generated 파일에는 다음 선언이 포함됩니다.

| 생성 항목 | 역할 | 간단한 예제 |
|---|---|---|
| `supportedMessageLocales` | Catalog의 `supportedLocales`에서 가져온 `List<String>`입니다. Flutter 앱의 지원 locale을 설정할 때 사용합니다. | `messageLocales(supportedMessageLocales)` |
| `defaultMessageLocale` | Catalog의 `defaultLocale`입니다. 요청 locale을 찾을 수 없으면 generated locale 판정에서 이 값을 사용합니다. | `createMessageResolver(selected: defaultMessageLocale)` |
| `resolveGeneratedLocale(requested)` | 요청 locale을 generated 지원 locale과 기본 locale에 맞춰 결정합니다. | `resolveGeneratedLocale('en-US') // 'en'` |
| `loadGeneratedMessages(requested)` | Locale을 결정하고 해당 locale 이름과 메시지 Map을 `GeneratedLocaleMessages`로 반환합니다. | `loadGeneratedMessages('ko-KR').messages` |
| `createMessageResolver(...)` | Generated loader를 사용하는 앱 소유 `MessageResolver`를 만듭니다. 선택적인 `onDiagnostic` callback으로 runtime 진단을 받을 수 있습니다. | `createMessageResolver(selected: 'ko-KR')` |
| `MessageKeys` | Catalog key마다 `static const String` 하나를 제공합니다. 값은 원본 key 문자열 그대로입니다. | `messages.text(MessageKeys.commonSave)` |
| `load<Locale>Messages()` | 지원 locale 하나의 generated message Map을 반환합니다. `loadEnMessages()`, `loadKoMessages()`처럼 locale마다 하나씩 생성됩니다. | `loadKoMessages()[MessageKeys.commonSave]` |

대부분의 앱은 `createMessageResolver`, `MessageKeys`, `supportedMessageLocales`를 사용합니다. Locale 판정 함수와 loader 함수는 고급 연동, 진단, 테스트에 사용할 수 있으며 일반적인 메시지 조회는 `MessageResolver`를 거치는 것이 좋습니다.

Generated library에 import prefix를 붙였다면 모든 생성 항목을 같은 prefix로 접근합니다.

```dart
import 'i18n/catalog.message_i18n.g.dart' as appI18n;

final messages = appI18n.createMessageResolver(selected: 'en-US');
final locales = appI18n.supportedMessageLocales;
final title = messages.text(appI18n.MessageKeys.appTitle);
```

원본 catalog마다 별도 runtime library가 생성되는 점은 그대로입니다. Import prefix는 선언 이름을 구분하며 catalog나 resolver를 합치지 않습니다.

### 4. 생성된 runtime 사용

생성 후 `lib/main.dart`에서 사용합니다. Flutter 연결은 다음 섹션을 참고하세요.

```dart
import 'i18n/catalog.message_i18n.g.dart';

void main() {
  final messages = createMessageResolver(selected: 'ko-KR');
  print(messages.text(MessageKeys.commonSave));
  print(messages.format(MessageKeys.welcomeUser, {'name': 'Dart'}));
  messages.select('en-US');
  // 동적 key나 점진적 전환에는 문자열을 계속 사용할 수 있습니다.
  print(messages.text('common.save'));
}
```

### 생성된 메시지 key 상수

Runtime library를 만드는 같은 build에서 `MessageKeys`도 생성합니다. 각 field는 catalog의 원본 key 문자열을 정확히 값으로 갖는 `static const String`입니다.

```dart
abstract final class MessageKeys {
  static const String appTitle = 'app.title';
  static const String commonSave = 'common.save';
  static const String welcomeUser = 'welcome.user';
}
```

두 형식을 모두 지원합니다.

| 형식 | 사용 시점 |
|---|---|
| `context.tr(MessageKeys.appTitle)` | Compile 시점에 key를 알 수 있을 때 사용합니다. 생성 멤버의 오타·삭제·이름 변경은 compile error가 됩니다. |
| `context.tr('app.title')` | 동적 key 또는 점진적 전환에 사용합니다. 없는 key는 기존 runtime diagnostic으로 보고합니다. |

Builder는 먼저 위의 원본 key 문법을 검사합니다. 유효한 key의 점·하이픈·밑줄 구간을 lowerCamelCase로 변환하며 접두사·접미사·번호·hash·별칭을 임의로 추가하지 않습니다. 서로 다른 유효한 key가 같은 멤버를 만들거나 결과가 Dart 예약어 또는 상속된 `Object` member이면 생성을 실패시킵니다.

```text
a.a, a_a, a-a  -> MessageKeys.aA  -> build 실패
class           -> MessageKeys.class -> build 실패
123.title       -> invalid_key -> 상수 생성 전 build 실패
```

Catalog의 원본 key를 수정한 뒤 다시 build하세요. 실패한 build는 불완전한 `MessageKeys`를 생성하지 않습니다. 상수는 최초 build 뒤 만들어지며 build 또는 watch가 catalog 변경을 처리할 때 갱신됩니다. key를 삭제하거나 이름을 바꾸면 생성 멤버도 사라지므로 남아 있는 상수 참조가 analyze나 compile 단계에서 실패합니다.

Generated catalog library마다 자체 `MessageKeys`가 있습니다. 여러 catalog를 사용하는 앱은 import prefix로 구분하고, 각 key는 같은 generated library에서 만든 resolver와 함께 사용합니다.

```dart
import 'account.message_i18n.g.dart' as accountI18n;
import 'checkout.message_i18n.g.dart' as checkoutI18n;

final accountMessages = accountI18n.createMessageResolver(selected: 'en');
final checkoutMessages = checkoutI18n.createMessageResolver(selected: 'en');

accountMessages.text(accountI18n.MessageKeys.profileTitle);
checkoutMessages.text(checkoutI18n.MessageKeys.paymentTitle);
```

### 한 번 하는 작업과 반복하는 작업

| 작업 | 실행 시점 |
|---|---|
| 패키지·Builder 설치, catalog annotation | 처음 도입할 때; 경로·의존성 변경 시 조정 |
| 최초 build | generated loader를 import하기 전 |
| 메시지·번역·placeholder·기본/지원 locale 변경 | 매번 build 또는 실행 중인 watch가 자동 생성 |
| 현재 locale 선택, 기존 키를 다른 화면에서 사용 | catalog가 그대로면 생성 불필요 |
| build --only-check | 생성 파일 누락·수동 수정·오래된 결과 검사; 출력 파일을 고치지 않음 |
| 기존 CLI check | 생성 파일 없이 catalog만 검사하고 싶을 때 선택적으로 사용 |

편집 중에는 다음 명령 하나를 실행해 둡니다. 등록된 Freezed·라우터·JSON Builder도 변경에 따라 함께 동작합니다.

```bash
dart run build_runner watch
```

## Flutter 설정

Flutter 앱도 generated loader만 import합니다. 아래 예제의 `supportedMessageLocales`는 catalog의 `supportedLocales`에서 생성되며, `defaultMessageLocale`을 포함한 다른 생성 항목은 [생성되는 runtime 항목](#생성되는-runtime-항목)에 정리되어 있습니다. `MessageI18nTool`과 원본 catalog는 개발 코드에만 두며 자세한 절차는 [개발용 catalog와 코드 생성](#개발용-catalog와-코드-생성)을 참고하세요. 다음은 생성된 메시지를 사용하는 `lib/main.dart` 예제입니다.

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

`MessageI18nScope`를 `MaterialApp`보다 위에 두면 route, 중첩 Navigator, dialog, bottom sheet, overlay에서 같은 resolver를 공유할 수 있습니다. Scope 위쪽의 context로는 조회할 수 없습니다.

`flutter_localizations`와 delegate는 사용하는 앱에서 설정합니다. 이 라이브러리가 앱의 메시지를 번역하더라도 Material/Cupertino 기본 문구가 자동으로 설정되는 것은 아닙니다. `messageLocale`은 문자열을 Flutter `Locale`로 바꿀 때 script와 country 정보를 보존합니다.

번역은 `build`에서 조회하거나 `didChangeDependencies`에서 다시 계산하세요. `initState`에서 한 번 저장한 문자열은 언어가 바뀌어도 갱신되지 않습니다.

## Runtime API와 locale 동작

| Dart resolver | Flutter API | 동작 |
|---|---|---|
| `text(key)` | `context.tr(key)` | 메시지 조회 |
| `format(key, arguments)` | `context.format(key, arguments)` | 이름 기반 문자열 인자 치환 |
| `select(locale)` | `context.updateLocale(locale)` | 언어를 로드하고 listener에 알림 |
| `reload()` | `context.reloadMessages()` | 마지막 요청 언어를 다시 로드하고 알림 |
| `locale` / `selected` | `context.i18n.locale` / `.selected` | 실제 선택 언어 / 원래 요청값 |
| `addListener` / `removeListener` | Scope가 구독 관리 | Flutter 밖에서 변경 구독 |

`tr`, `format`, `context.i18n`은 위젯에 변경 의존성을 등록합니다. `updateLocale`과 `reloadMessages`는 구독하지 않는 조회를 사용합니다. `MessageI18nScope.read(context)`도 구독하지 않습니다. `of`는 구독하며, `maybeOf`는 Scope가 없는 경우를 처리할 수 있습니다.

### Locale 선택

2~3자리 영문 language, 선택적인 4자리 script, 선택적인 2자리 영문 또는 3자리 숫자 region을 지원합니다.

| 입력 | 정규화 |
|---|---|
| `en_US` | `en-US` |
| `zh_hant_tw` | `zh-Hant-TW` |
| `ko-KR` | `ko-KR` |

정확한 locale부터 시작해 뒤쪽 subtag를 하나씩 제거하고, 마지막에는 catalog의 기본 언어를 사용합니다. 예를 들어 `zh-Hant-TW → zh-Hant → zh → default` 순서에서 처음 지원되는 항목을 선택합니다. 지원하지 않는 variant, extension, 잘못된 순서는 `FormatException`이며 일반적인 fallback 요청으로 처리하지 않습니다.

resolver는 현재 메시지 Map 하나를 보유하고 언어 선택이나 reload 때 교체합니다. 메시지별 fallback Map이나 전체 언어 Map cache는 없습니다. 다른 언어 문자열이 앱 바이너리 또는 VM heap 전체에서 제거된다는 보장은 아닙니다.

### Placeholder와 진단

`{identifier}`만 지원하며 이름은 `[A-Za-z_][A-Za-z0-9_]*` 규칙을 따릅니다. 인자는 `Map<String, String>`입니다. 중괄호 escape, 중첩 표현, ICU plural/select/gender, 자동 숫자·날짜 형식 지정은 지원 범위 밖입니다.

```dart
final messages = createMessageResolver(
  selected: 'en',
  onDiagnostic: (issue) {
    print('${issue.code}: ${issue.key} (${issue.locale})');
  },
);
```

| 상황 | Runtime 결과 | 진단 코드 |
|---|---|---|
| 없는 메시지 | 키 자체 반환 | `missing_key` |
| 인자 누락 | 해당 placeholder 유지 | `missing_argument` |
| 초과 인자 | 사용하지 않는 인자 무시 | `extra_argument` |
| 미지원 placeholder 문법 | 치환 전 메시지 반환 | `unsupported_placeholder` |

진단에는 code, key, locale이 담깁니다. 엄격한 catalog 검증으로 생성 전에 번역 문제를 확인할 수 있습니다. `MessageResolver.fromLoader`는 loader 연결과 테스트 fake를 위한 저수준 API이며 일반 앱은 생성된 factory를 사용합니다.

## 상태 관리와 소유권

앱 범위 resolver의 소유자와 구독 방식은 하나만 선택합니다. 아래의 기본 Scope, Riverpod, GetX 방식은 서로 대안 관계이며 상태 관리 예제를 다시 `MessageI18nScope`로 감싸지 않습니다.

### 기본 MessageI18nScope

다른 상태 관리 도구가 없다면 composition root에서 resolver 하나를 만들고 `MaterialApp` 위의 `MessageI18nScope`에 전달합니다. Scope는 외부 resolver를 구독하지만 생성하거나 dispose하지 않습니다. 위젯은 [Flutter 설정](#flutter-설정)에서 설명한 `context.tr`, `context.format`, `context.updateLocale`, `context.reloadMessages`를 사용합니다.

이 context 확장은 상위에 `MessageI18nScope`가 있어야 동작합니다. Riverpod과 GetX 통합은 각 provider 또는 controller를 통해 resolver를 호출하므로 context 확장을 사용하지 않습니다.

### Riverpod

사용하는 앱에서 `flutter_riverpod`을 추가합니다. `ProviderScope`가 provider container를 소유하고, `NotifierProvider`가 generated resolver 하나를 소유하며, 구독한 immutable state가 `MaterialApp.locale`과 메시지 위젯을 함께 다시 빌드합니다. Locale 변경과 reload는 반드시 notifier를 통해 수행해야 합니다. Resolver를 직접 호출하면 Riverpod의 state 발행을 우회하게 됩니다.

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

`MessagesState`는 `select` 또는 `reload` 성공 뒤 새 wrapper를 만듭니다. 따라서 앱이 의도적으로 같은 resolver 객체를 유지해도 `ref.watch`는 새로운 state를 관찰합니다. Locale 로드가 예외를 던지면 새 state 대입까지 도달하지 않으므로 이전 resolver 상태가 계속 유지됩니다.

### GetX

사용하는 앱에서 `get`을 추가합니다. `GetMaterialApp`이 GetX root를 제공하고, `initialBinding`이 앱 범위 controller 하나를 등록하며, `GetBuilder`가 메시지 위젯을 구독합니다. Controller는 resolver가 locale 선택에 성공한 뒤 GetX root locale을 갱신하고 `update()`를 호출해 메시지 위젯을 갱신합니다.

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

Controller는 Flutter의 지역화된 Material/Cupertino 리소스를 위해 `Get.updateLocale`을 호출하고, `GetBuilder` 메시지 소비자를 위해 `update()`를 호출합니다. 이 패키지는 GetX `translations`를 등록하거나 `String.tr` 확장을 제공하지 않습니다. GetX 자체 다국어 API와 혼동하지 않도록 controller의 `text`와 `format`을 사용합니다.

Riverpod과 GetX는 사용하는 앱에서 선택적으로 추가합니다. message_i18n 패키지는 두 상태 관리 도구에 의존하지 않습니다.

## 개발용 catalog와 코드 생성

`message_i18n_builder`는 annotation이 있는 const 값을 정적으로 읽고 공통 validator로 검사합니다. 앱이나 `MessageI18nTool`을 실행하지 않습니다. 생성물은 locale별 factory와 loader를 한 파일에 두며 현재 언어 Map만 선택하는 기존 runtime 동작을 유지합니다.

### Builder 경로와 파일명

| 변경 | 함께 바꿀 항목 |
|---|---|
| `catalog.dart` → `messages.dart` | 앱 import를 `messages.message_i18n.g.dart`로 변경 |
| catalog 디렉터리 이동 | 앱 generated import 및 설정했다면 generate_for 수정 |
| catalog 변수명 변경 | annotation 유지; 생성 loader API는 동일 |
| lib 밖의 입력 사용 | build target sources와 generate_for에 포함 |

기본 입력은 lib의 Dart 파일이며 생성 파일은 제외합니다. 한 library당 catalog 하나를 표시합니다. 여러 파일의 loader를 함께 import하면 prefix를 사용하세요. 기본 출력은 원본 옆의 고정 suffix이며 CLI의 generatedDirectory/sourcePaths/watchEntrypoint 설정은 적용되지 않습니다.

필요하면 소비자의 build.yaml에서 대상을 좁힙니다.

```yaml
targets:
  $default:
    builders:
      message_i18n_builder:
        generate_for:
          - lib/localization/messages.dart
```

### 선택적인 CLI와 기존 프로젝트

아래 설정은 catalog-only check, JSON/XLSX export·merge 또는 기존 CLI 생성 방식을 유지할 때 사용합니다. 기본 Builder 흐름에는 필요하지 않습니다. 기존 프로젝트는 annotation과 개발 의존성을 추가하고 build 후 앱 import를 새 파일로 바꾸면 됩니다. 기존 generated 디렉터리는 자동 삭제하지 않습니다. 두 watcher를 동시에 실행하지 마세요.

선택적인 CLI를 사용하려면 `tool/i18n.dart`를 만듭니다.

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

### 기존 CLI 설정 상세

`MessageI18nTool`은 이 패키지의 번역 작성 영역과 generated runtime을 연결합니다. Import된 const `MessageCatalog` 객체를 직접 전달받아 검증·생성·감시·내보내기·병합 명령을 제공합니다. 개발자나 CI가 tool entrypoint를 실행할 때만 동작하며 앱 시작 시 실행되지 않습니다.

#### 개발 주기

```text
최초 설정:  catalog 파일 + tool entrypoint + 최초 generate
반복 작업:  catalog 수정 → generate 또는 catalog 수정 → watch 자동 생성
앱 runtime: generated loader → resolver → Dart 또는 Flutter UI
CI:         check --verify-generated
번역 교환:  export → 외부 편집 → merge 후보 → 사람 검토 → catalog 반영
```

Catalog 파일과 tool entrypoint 작성은 일반적으로 한 번만 합니다. 하지만 catalog 내용은 일회성 설정이 아니라 계속 편집하는 번역 기준 원본입니다. 메시지나 locale이 바뀌면 `generate`를 다시 실행해야 하며, `watch`가 실행 중이면 생성 주기를 자동으로 수행합니다.

#### 도구 설정값

| 인자 | 역할 |
|---|---|
| `catalog` | Tool entrypoint가 이미 import한 기준 `MessageCatalog` 객체입니다. 파일 경로가 아닙니다. |
| `sourcePaths` | `watch`가 `.dart` 변경을 감시할 프로젝트 내부의 기존 디렉터리입니다. Catalog 객체를 자동 탐색하지 않습니다. |
| `generatedDirectory` | 언어별 파일, loader, manifest를 저장하는 프로젝트 내부의 전용 디렉터리입니다. 직접 작성한 파일을 넣지 마세요. |
| `watchEntrypoint` | Watch의 각 생성 주기마다 새 프로세스로 실행할 프로젝트 상대 경로의 Dart 진입점입니다. 현재 CLI는 모든 공개 명령을 실행하기 전에도 이 파일이 존재하는지 검사합니다. |
| `projectRoot` | 상대 경로 해석과 파일 안전 검사의 기준 디렉터리입니다. 기본값은 현재 디렉터리입니다. |

#### 경로와 파일명 변경

`lib/i18n/catalog.dart`, `tool/i18n.dart`, `lib/i18n/generated/`은 예제이며 필수 이름이 아닙니다. Dart import, 도구 설정, 실행 명령과 앱 runtime import가 서로 일치하면 다른 구조를 사용할 수 있습니다.

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

실제 진입점 경로로 명령을 실행합니다.

```bash
dart run scripts/localization.dart generate
dart run scripts/localization.dart watch
```

| 변경 사항 | 함께 수정할 항목 |
|---|---|
| Catalog 파일 위치·이름 | Tool entrypoint의 Dart import |
| Catalog 객체 이름 | `catalog:`에 전달하는 객체 |
| Catalog 원본이 있는 디렉터리 | `watch`가 변경을 감지해야 한다면 `sourcePaths`에 포함 |
| Tool entrypoint 위치·이름 | `watchEntrypoint`과 모든 `dart run <진입점>` 명령 |
| Generated directory | `generatedDirectory`와 앱의 generated loader import |
| 명령 실행 기준 루트 | 앱 `pubspec.yaml` 옆에서 실행하거나 `projectRoot`를 명시 |

Catalog가 `sourcePaths` 밖에 있어도 직접 실행한 `generate`는 Dart import를 통해 동작할 수 있지만, `watch`는 설정된 디렉터리 밖의 변경을 감지하지 못합니다. 모든 상대 경로는 `projectRoot`를 기준으로 해석됩니다. Generated directory는 프로젝트 안에서 도구가 전용으로 사용하는 디렉터리로 유지하세요.

#### 직접 생성 또는 watch

Catalog 변경 뒤 직접 생성하려면 다음 명령을 실행합니다.

```bash
dart run tool/i18n.dart generate
```

편집 중 자동 생성하려면 다음 명령을 실행해 둡니다.

```bash
dart run tool/i18n.dart watch
```

`watch`는 시작할 때 한 번 생성하고 이후 `sourcePaths` 아래의 `.dart` 파일을 감시합니다. 앱 코드는 항상 generated loader를 사용하며 작성용 catalog나 tool entrypoint를 import하지 않습니다.

## CLI 명령

`pubspec.yaml`과 설정한 도구 진입점이 있는 앱 프로젝트 루트에서 모든 명령을 실행합니다.

```bash
dart run tool/i18n.dart <명령> [옵션]
```

| 명령 | 사용하는 시점 | 주요 옵션 |
|---|---|---|
| `check` | 생성 전 또는 빠른 CI 검증 | `--verify-generated` |
| `generate` | Catalog 변경 후 또는 build 단계 | `--output <디렉터리>` |
| `watch` | 로컬에서 번역을 편집하는 동안 | `--debounce-ms <정수>` |
| `export` | 번역 담당자에게 파일을 보내기 전 | `--locales`, `--format`, `--output`, `--split-by-locale` |
| `merge` | 수정된 JSON/XLSX를 전달받은 뒤 | `--input` 반복, 선택적인 `--output` |

### `check`: catalog 검증

```bash
dart run tool/i18n.dart check
dart run tool/i18n.dart check --verify-generated
```

`check`는 locale 식별자, 기본 언어와 지원 언어의 관계, 메시지 키, 누락되거나 빈 번역, placeholder 문법과 언어별 일치 여부를 검사합니다. 생성 파일은 수정하지 않습니다. CI에서는 `--verify-generated`를 추가해 임시 디렉터리에 예상 결과를 만든 뒤 `generatedDirectory`의 각 도구 소유 파일과 비교할 수 있습니다. 생성 파일이 없거나 수정되었거나 오래된 경우 실패합니다.

### `generate`: runtime 파일 생성

```bash
dart run tool/i18n.dart generate
dart run tool/i18n.dart generate --output lib/i18n/generated
```

`generate`는 catalog를 검증한 뒤 언어별 Dart 메시지 파일, `message_loader.g.dart`, `message_i18n_manifest.json`을 생성합니다. `--output`을 사용하면 이번 실행에 한해 `generatedDirectory`를 바꿀 수 있으며 프로젝트 내부의 전용 디렉터리여야 합니다. 완성된 파일을 staging 영역에서 format한 뒤 도구 소유 파일을 교체합니다. Manifest를 기준으로 오래된 파일을 삭제하고 도구가 소유하지 않은 파일은 덮어쓰지 않습니다.

Catalog, 지원 언어, 생성 설정을 변경한 뒤 실행하세요. 앱 코드는 계속 같은 generated loader 경로를 import하면 됩니다.

### `watch`: 편집 중 자동 생성

```bash
dart run tool/i18n.dart watch
dart run tool/i18n.dart watch --debounce-ms 400
```

`watch`는 시작할 때 한 번 생성하고 이후 `sourcePaths` 아래의 `.dart` 파일 변경을 감시합니다. 기본 250ms 동안 연속 변경을 모으며 각 생성 주기는 새 Dart 프로세스에서 순서대로 실행합니다. 생성 디렉터리, `build/`, `.dart_tool/`은 반복 생성을 막기 위해 제외합니다. 생성에 실패하면 마지막 정상 결과를 보존한 채 계속 감시하므로 다음 수정으로 복구할 수 있습니다. 종료할 때는 `Ctrl+C`를 누릅니다.

성공한 뒤 메시지 문자열만 바뀌었다면 Flutter hot reload를 사용합니다. Locale 구조나 generated import가 바뀌었다면 hot restart를 사용하세요.

### `export`: 번역 전달 파일 생성

```bash
dart run tool/i18n.dart export --locales ko,en --format json
dart run tool/i18n.dart export --locales ko,en --format xlsx --output build/translations.xlsx
dart run tool/i18n.dart export --locales ko,en --format xlsx --split-by-locale
```

`--locales`에는 지원 언어를 쉼표로 구분해 지정하고 `--format`에는 `json` 또는 `xlsx`를 지정합니다. 두 옵션 모두 필수입니다. `--output`을 생략하면 `build/message_i18n/exports/` 아래에 timestamp가 붙은 새 디렉터리를 만듭니다. 하나의 통합 파일을 만들 때 `--output`은 선택한 형식과 같은 확장자를 가져야 합니다. `--split-by-locale`을 사용하면 `--output`은 디렉터리이며 언어별 파일을 생성합니다. 기존 export 대상은 덮어쓰지 않습니다.

### `merge`: 검토 후보 생성

```bash
dart run tool/i18n.dart merge --input build/translations.json
dart run tool/i18n.dart merge \
  --input build/ko.xlsx \
  --input build/en.xlsx \
  --output build/message_i18n/review
```

각 `.json` 또는 `.xlsx` 파일마다 `--input`을 반복합니다. 같은 키와 locale 값이 여러 입력에 있으면 나중 입력값을 사용하고 warning을 출력합니다. 출력 위치는 프로젝트의 `build/` 아래에 있는 새 디렉터리여야 하며 `merged_catalog.dart`와 `key-comparison.json`을 생성합니다.

`merge`는 원본 catalog를 수정하지 않으며 입력에 없는 값을 원본에서 가져와 채우지도 않습니다. 후보 파일, 키 비교 결과, 모든 warning을 검토한 뒤 승인한 변경만 `catalog.dart`에 직접 반영하고 `check`와 `generate`를 다시 실행하세요.

### 도움말, 버전, 종료 코드

```bash
dart run tool/i18n.dart --help
dart run tool/i18n.dart <명령> --help
dart run tool/i18n.dart --version
```

종료 코드 **0**은 성공, **1**은 검증·입력 구조·parse·process·파일 작업 실패, **64**는 잘못된 명령 사용을 뜻합니다. 일반 결과는 stdout, 오류와 merge warning은 stderr로 전달됩니다. `__watch-cycle`은 `watch`가 내부에서 사용하는 명령이므로 직접 실행하지 않습니다.

엄격 검증 코드는 `invalid_locale`, `empty_locales`, `duplicate_locale`, `missing_default`, `invalid_key`, `unsupported_locale`, `empty_translation`, `missing_translation`, `unsupported_placeholder`, `placeholder_mismatch`입니다. 결과는 severity → key → locale → code 순으로 정렬합니다. Const Map의 중복 키와 잘못된 값 타입은 도구 실행 전에 Dart가 거부합니다.

## 번역 작업 흐름

### 1. 검증된 catalog 내보내기

```bash
dart run tool/i18n.dart export --locales ko,en --format json --output build/translations.json
dart run tool/i18n.dart export --locales ko,en --format xlsx --output build/translations.xlsx
dart run tool/i18n.dart export --locales ko,en --format xlsx --split-by-locale
```

기본 출력은 `build/message_i18n/exports/<timestamp>/`입니다. 단일 출력은 형식에 맞는 확장자의 파일, 언어별 분리 출력은 디렉터리입니다. 기존 파일을 덮어쓰지 않으며 자동 할당 디렉터리의 이름이 충돌하면 suffix를 붙입니다.

JSON은 메시지 키 아래에 언어별 값을 둡니다.

```json
{
  "common.save": {"ko": "저장", "en": "Save"},
  "welcome.user": {"ko": "{name}님, 환영합니다.", "en": "Welcome, {name}."}
}
```

XLSX는 `translations`라는 sheet를 사용합니다.

| key | ko | en |
|---|---|---|
| common.save | 저장 | Save |
| welcome.user | {name}님, 환영합니다. | Welcome, {name}. |

첫 header는 정확히 `key`이며 언어 열은 요청한 순서입니다. 설명, 원본 경로, 숨은 metadata 열은 없습니다. 셀은 텍스트로 유지하세요. 숫자와 수식 셀은 거부하며 `=`, `+`, `-`, `@`로 시작하는 값도 export 시 명시적인 텍스트로 저장합니다.

정규화 후 중복된 언어 header나 중복 key row는 구조 오류입니다. 완전히 빈 행은 무시하고, 내용은 있지만 키가 없는 행은 거부합니다. 빈 번역 셀은 빈 문자열로 읽습니다.

### 2. 전달받은 파일 병합

```bash
dart run tool/i18n.dart merge --input build/translations.json --input build/translations.xlsx
```

기본 출력 디렉터리는 `build/message_i18n/merges/<timestamp>/`이며 다음 파일을 생성합니다.

- `merged_catalog.dart`: 독립적인 `mergedCatalog` 후보.
- `key-comparison.json`: 원본 catalog와의 키 차이를 정렬한 보고서.

**Merge는 입력 파일에 들어 있는 값만 합칩니다.** 원본을 수정하거나 입력에 없는 키·번역을 원본에서 보충하지 않습니다. 같은 key·locale이 겹치면 마지막 입력이 우선하며 이전/최종 입력 번호를 warning에 표시합니다. 따라서 영어만 가져오면 원본의 한국어·일본어가 자동으로 복원되지 않습니다.

누락 언어, 빈 값, placeholder 차이, 키 차이는 warning이나 보고서로 전달하며 후보 생성을 막지 않습니다. 후보 생성 성공은 exit 0이지만 엄격 검증 통과를 의미하지 않습니다. 파일 구조 또는 I/O 오류는 exit 1입니다. 출력은 앱의 `build/` 디렉터리 아래에 있어야 합니다.

키 비교는 번역값의 동일성이 아닌 키 집합만 확인합니다. 현재 사람이 읽는 보고서는 다음 한국어 문구를 사용합니다.

```text
원본과 병합본의 키가 일치합니다.
```

차이가 있으면 해당하는 항목을 각각 출력합니다.

```text
원본에만 있는 키는 다음과 같습니다.
- old.key
병합본에만 있는 키는 다음과 같습니다.
- new.key
```

기계가 읽는 보고서는 다음과 같습니다.

```json
{"matched":false,"originalOnly":["old.key"],"mergedOnly":["new.key"]}
```

### 3. 검토 후 반영

warning, 번역값, 키 차이를 검토하고 승인된 내용을 원본 Dart catalog에 직접 반영합니다. 이후 기본 흐름에서는 `dart run build_runner build`를 실행합니다. 기존 CLI 생성 경로에서는 `check`, `generate`, `check --verify-generated`를 사용합니다. 후보를 원본에 자동 적용하는 명령은 제공하지 않습니다.

## 생성 파일과 복구

검증 실패 시 runner가 이전 출력 파일을 삭제하는 동작을 확인했습니다. 원본을 수정한 뒤 다시 생성해야 하며, 실행 중 앱을 실패한 출력 상태에서 reload하지 마세요.

Builder의 `.message_i18n.g.dart`는 build_runner 전용 출력입니다. 수동 파일을 이 경로에 두지 마세요. build는 수정된 출력도 재작성할 수 있습니다. `build --only-check`는 공개 출력 파일을 쓰거나 삭제하지 않고 차이가 있으면 실패합니다. 내부 `.dart_tool` 캐시는 별도로 취급합니다. 검증 실패는 빌드 실패이며, 수정 후 다시 build하거나 watch의 회복을 기다립니다. Builder에 기존 CLI의 rollback 보장을 적용하지 않습니다.

### 기존 CLI 파일 보존


생성 디렉터리는 도구의 출력으로 취급합니다. Manifest에는 schema, catalog fingerprint, locale, 키 개수, 소유 파일 목록이 기록됩니다. 생성된 번역을 직접 수정하지 말고 catalog를 변경한 뒤 다시 생성하세요.

생성 파일을 커밋해 검토·재현에 사용하거나, 분석과 빌드 전에 생성할 수 있습니다. 커밋하는 경우 CI에서 `check --verify-generated`로 원본과의 불일치를 검사할 수 있습니다.

생성은 검증, staging, format, 대상 snapshot 확인 후 소유 파일을 교체합니다. **파일별 rename과 실패 시 rollback** 방식이며 파일 집합 전체의 원자적 교체는 아닙니다. 비소유 파일은 보존하고 stale 삭제는 manifest 소유 파일로 제한합니다. 경로 이탈, symlink, 비생성 파일의 소유권 주장은 거부합니다.

OS 잠금으로 같은 대상에 대한 동시 생성을 막습니다. `.generated.message_i18n.lock` 같은 0-byte sibling guard는 남아 있고 Git에서 제외합니다. 프로세스가 종료되면 OS 잠금은 해제됩니다. 경합을 우회하려고 guard를 삭제하지 마세요. 강제 종료나 전원 손실 후에는 `check --verify-generated`로 확인하고 필요하면 재생성합니다. 모든 갑작스러운 중단에 대한 파일 집합 전체의 복구를 보장하지 않습니다.

## Watch와 hot reload

별도 터미널에서 실행합니다.

```bash
dart run build_runner watch
```

build_runner는 변경된 입력과 의존 파일을 추적합니다. 실패한 빌드에서 진단을 확인하고 원본을 수정하면 감시를 유지한 채 회복할 수 있습니다. Ctrl-C로 종료합니다. 다른 생성기도 같은 watch에서 동작합니다.

생성 성공 후 Flutter hot reload를 직접 실행합니다. 기존 resolver를 갱신하려면 resolver를 보유하는 앱의 `State`에 다음 hook을 추가합니다.

```dart
@override
void reassemble() {
  super.reassemble();
  resolver.reload();
}
```

| 변경 | 개발 중 작업 |
|---|---|
| 기존 번역 문구 | 생성 후 `resolver.reload()`가 연결된 hot reload |
| 새 메시지 키와 사용 코드 | 생성 후 hot reload |
| 지원 언어 목록이나 초기화 구조 | 생성 후 hot restart |

Watcher는 Flutter daemon에 연결하거나 자동 reload를 보내지 않습니다. Reload가 `main`, `initState`, 기존 static 초기화를 다시 실행한다고 가정하지 마세요. [Flutter 공식 hot reload 문서](https://docs.flutter.dev/tools/hot-reload)를 참고하세요.

## 문제 해결

| 증상 | 확인 또는 조치 |
|---|---|
| 번역 대신 키가 표시됨 | 키와 `missing_key` 진단 확인; catalog 변경 후 재생성 |
| `{name}`이 남음 | `format`에 `name` 문자열 인자 전달 |
| 요청한 언어와 실제 언어가 다름 | `selected`, `locale`, 지원 언어와 fallback 순서 확인 |
| 위젯이 이전 언어를 표시함 | `build`/`didChangeDependencies`에서 조회; 하나의 resolver를 공유하고 Scope를 route 위에 배치 |
| Scope 조회 실패 | 하위 context 사용 또는 Scope 위치 조정 |
| Flutter 기본 문구가 맞지 않음 | 소비자 앱의 `flutter_localizations`, delegate, `locale`, `supportedLocales` 설정 확인 |
| Reload 후 수정 내용이 보이지 않음 | 생성 성공을 기다리고 `reassemble`에서 기존 resolver의 `reload` 호출 확인 |
| Merge 성공 후 후보 검증 실패 | 후보 생성 성공과 검증 통과는 다름; warning 해결 후 반영 |
| Excel 셀을 가져올 수 없음 | 텍스트 셀, 정확한 `key` header, `translations` sheet 확인 |
| 생성물 검증 실패 | build 후 결과 검토, build --only-check 재실행; CLI 검사 명령은 기존 출력 전용 |
| 생성 잠금 충돌 | 다른 프로세스의 종료를 기다리거나 중지; guard 삭제 금지 |

## CI 연동

생성 파일을 커밋한다면 의존성 설치 후, build로 고치기 전에 검사합니다.

```bash
dart run build_runner build --only-check
```

생성 파일을 Git에서 제외한다면 먼저 build하고 analyze/test/build를 실행합니다. 그 뒤 only-check는 방금 만든 생성물의 일관성 검사이며 커밋 최신성 검사는 아닙니다. 생성 파일이 없는 상태의 only-check 실패는 정상입니다. 기존 CLI의 check --verify-generated는 기존 다중 파일/manifest 전용입니다.

다른 생성기와 확인하는 기준 조합은 build_runner 2.16.2, build 4.0.11, Freezed 4.0.3, go_router_builder 4.5.2, go_router 18.1.1, json_serializable 6.15.2입니다. 이 공동 fixture는 Dart 3.13과 Flutter 3.47을 사용합니다. Builder 자체의 최소 Dart는 3.11입니다. 의존성 해석과 생성 파일 실행을 함께 검사하세요.

## 지원 범위와 제한

현재 버전은 문자열 key 상수를 생성하지만 placeholder별 타입 함수를 제공하지 않습니다. ICU 복수형·성별, 원격 번역 배포, 번역 웹 UI, 네이티브 리소스 생성, 원본 자동 반영, 지연 언어 다운로드도 제공하지 않습니다. 요청할 언어의 선택과 저장은 앱에서 담당합니다.

## 라이선스

[MIT No Attribution (MIT-0)](LICENSE)을 적용합니다. 저작권 표시 의무 없이 상업적 사용을 포함한 모든 목적으로 사용·수정·배포할 수 있으며, 보증 없이 제공됩니다. 의존 패키지에는 각자의 라이선스가 적용됩니다.

## README 참고 자료

다음 pub.dev 패키지 README의 문서 구성을 참고했습니다. 문서 표현 방식의 참고 자료이며 runtime 의존성 또는 성능 비교 대상이 아닙니다.

| 참고 자료 | 반영한 문서 구성 |
|---|---|
| [Get](https://pub.dev/packages/get) | 언어 선택과 기능별 안내 |
| [Dio](https://pub.dev/packages/dio) | 목차, 빠른 시작, API별 예제 |
| [http](https://pub.dev/packages/http) | 최소 사용 예제에서 소유권·검증 안내로 이어지는 구성 |
| [path_provider](https://pub.dev/packages/path_provider) | 요구사항과 지원 기능 표 |
| [shared_preferences](https://pub.dev/packages/shared_preferences) | API 동작과 제한 사항의 명시 |
| [url_launcher](https://pub.dev/packages/url_launcher) | 완결된 설정 예제와 구성 시 주의점 |

영어판과 한국어판은 동일한 API와 작업 흐름을 설명합니다.
