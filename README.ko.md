# message_i18n

[English](https://github.com/mollacode/message_i18n/blob/main/README.md) | **한국어**

Dart와 Flutter에서 사용할 수 있는 메시지 중심 다국어 라이브러리입니다. 한 메시지의 모든 번역을 const Dart catalog에 모아 작성하고, 앱에서는 생성된 독립 runtime을 사용합니다. 번역 담당자와는 JSON이나 Excel 파일을 주고받을 수 있습니다.

```dart
// 메시지 하나의 번역을 함께 작성합니다.
'common.save': LocalizedMessage({'ko': '저장', 'en': 'Save', 'ja': '保存'})

// Flutter에서 번역을 조회합니다.
Text(context.tr(MessageKeys.commonSave));
Text(context.format(MessageKeys.welcomeUser, {'name': 'Dart'}));
Text(context.tr('common.save')); // 문자열 key도 지원합니다.

// 구독 중인 위젯의 언어를 변경합니다.
context.updateLocale('en-US');
```

순수 Dart runtime과 작성 도구가 필요하면 `message_i18n`을 사용하세요. Flutter 연동에는 `message_i18n_flutter`를 함께 추가합니다. 두 패키지 모두 네이티브 플랫폼 코드를 포함하지 않습니다.

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

한 메시지의 번역과 placeholder를 한곳에 모아 두면 언어별 표현을 훨씬 쉽게 비교할 수 있습니다. 파일을 언어마다 오갈 필요 없이 하나의 메시지 키 아래에서 모든 번역을 검토할 수 있습니다.

- **단일 원본:** const Dart catalog가 기준이며 JSON/XLSX는 교환 형식입니다.
- **생성 전 검증:** 번역 누락, 빈 값, 잘못된 locale, placeholder 불일치를 검사합니다.
- **작성 도구와 runtime 분리:** 앱은 generated loader를, 작성 도구는 catalog를 import합니다.
- **명확한 소유권:** 앱이 resolver를 소유하고 Flutter scope 또는 기존 DI 도구와 공유합니다.
- **검토 가능한 번역 반영:** merge는 원본을 수정하지 않고 후보와 키 비교 보고서를 생성합니다.
- **간결한 Flutter API:** `context.tr`, `context.format`, `context.updateLocale`, `context.reloadMessages`를 제공합니다.

번역 원본은 코드에서 관리하고, 번역 담당자는 스프레드시트로 작업하는 팀에 잘 맞습니다. 메시지 키는 문자열로 유지됩니다. 현재 버전은 placeholder별 타입 함수나 ICU 복수형 규칙을 생성하지 않습니다.

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

core는 Flutter 없이 동작하고 Flutter 어댑터는 이 core에만 의존합니다. Riverpod과 GetX는 선택 사항입니다. 작성용 CLI는 파일 시스템과 프로세스 API가 있는 개발 환경에서 실행하세요. 앱은 CLI 대신 생성된 runtime loader를 사용합니다.

## 빠른 시작

처음 적용할 때는 `build_runner` 방식을 권장합니다. 앱에서 다른 생성기를 사용하고 있어도 하나의 build 또는 watch 명령으로 함께 실행할 수 있습니다. 별도의 검증·내보내기·병합 작업이 필요할 때는 선택적으로 `MessageI18nTool`을 사용하세요.

### 1. 패키지 설치

Dart 앱이라면 `dart pub add message_i18n`을 실행합니다. Flutter 앱에는 `flutter pub add message_i18n message_i18n_flutter`를 사용하세요. 이어서 앱의 `pubspec.yaml`에 다음 개발 의존성을 추가하고 `dart pub get` 또는 `flutter pub get`을 실행합니다.

```yaml
dev_dependencies:
  message_i18n_builder: ^0.1.0
  build_runner: '>=2.16.2 <2.17.0'
```

Builder는 build 4 계열을 지원합니다. go_router_builder와 함께 검증한 기준 버전은 build_runner 2.16.2입니다. 여러 생성기를 한꺼번에 올릴 때는 build 메이저 버전 제약이 맞는지 먼저 확인하세요.

Flutter 기본 위젯도 지역화하려면 다음 SDK 의존성을 추가하세요.

```yaml
dependencies:
  flutter_localizations:
    sdk: flutter
```

### 2. 원본 catalog 작성

`lib/i18n/catalog.dart` 같은 파일에 catalog를 작성합니다. 경로와 파일명은 원하는 대로 정할 수 있습니다. 이 작성용 파일은 앱 runtime에서 import하지 말고, 입력 library마다 top-level const catalog 하나에 annotation을 붙이세요.

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

지원하는 모든 언어에 비어 있지 않은 번역을 넣고, 기본 언어도 지원 목록에 포함하세요. 한 메시지에서 사용하는 placeholder 이름은 언어가 달라도 같아야 합니다. Builder는 import한 const와 const Map spread도 정적으로 읽습니다.

#### 메시지 key 규칙

Catalog key는 메시지를 조회할 때 그대로 사용하는 값입니다. 다음 규칙에 맞춰 작성하세요.

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

유효하지 않거나 같은 멤버명으로 충돌하는 key는 catalog에서 직접 고친 뒤 다시 build하세요. Validator가 key를 대신 바꾸지는 않습니다. 기존 key의 이름을 바꿀 때는 raw string으로 참조한 곳도 함께 수정해야 합니다. Generated member는 다음 build에서 갱신됩니다. 사용 방법은 [생성된 메시지 key 상수](#생성된-메시지-key-상수)에서 이어서 설명합니다.

#### Placeholder와 format parameter 규칙

값을 치환할 곳에는 `{identifier}`를 씁니다. Identifier는 `[A-Za-z_][A-Za-z0-9_]*` 형식이어야 합니다. 영문자나 밑줄로 시작하고, 그 뒤에는 영문자·숫자·밑줄을 사용할 수 있습니다. 대소문자를 구분하며, message key의 소문자 규칙은 적용되지 않으므로 `{userName}`도 유효합니다.

같은 메시지의 번역에서는 언어가 달라도 placeholder 이름 집합이 같아야 합니다. 배치 순서와 반복 횟수는 언어마다 달라도 됩니다.

Placeholder 이름과 정확히 일치하는 key를 가진 `Map<String, String>`을 전달합니다.

```dart
final text = messages.format(
  MessageKeys.welcomeUser,
  {'name': 'Dart'},
);
// 위 catalog의 영어 결과: Welcome, Dart.
```

필요한 인자가 없으면 placeholder를 결과에 그대로 남기고 `missing_argument` 진단을 보냅니다. 사용되지 않은 인자는 무시하면서 `extra_argument`를 보냅니다. 숫자나 날짜처럼 문자열이 아닌 값은 앱에서 변환한 뒤 전달하세요.

`{0}` 같은 위치 기반 placeholder, 비어 있거나 짝이 맞지 않는 중괄호, 중첩 중괄호와 ICU plural/select/gender 문법은 검증에서 거부됩니다. 현재 버전은 중괄호 escape 문법을 제공하지 않습니다.

### 3. 검증과 최초 생성

앱 프로젝트 루트에서 다음 명령을 실행하세요. 별도의 `tool/i18n.dart` 진입점은 필요하지 않습니다.

```bash
dart run build_runner build
```

이 명령은 catalog를 검증하고 `lib/i18n/catalog.message_i18n.g.dart`를 독립된 runtime library로 만듭니다. 원본에 `part`로 연결하지 말고 직접 import하세요.

출력 파일명은 원본을 기준으로 정해집니다. 예를 들어 `lib/i18n/account.dart`를 만들면 `lib/i18n/account.message_i18n.g.dart`가 생성됩니다. 원본의 이름이나 위치를 바꾸더라도 그에 맞는 generated 파일을 import하면 됩니다.

### 생성되는 runtime 항목

Annotation을 붙인 catalog마다 독립된 library 하나가 생성됩니다. 위 예제에서 만들어지는 항목은 다음과 같습니다.

| 생성 항목 | 역할 | 간단한 예제 |
|---|---|---|
| `supportedMessageLocales` | Catalog의 `supportedLocales`에서 가져온 `List<String>`입니다. Flutter 앱의 지원 locale을 설정할 때 사용합니다. | `messageLocales(supportedMessageLocales)` |
| `defaultMessageLocale` | Catalog의 `defaultLocale`입니다. 요청 locale을 찾을 수 없으면 generated locale 판정에서 이 값을 사용합니다. | `createMessageResolver(selected: defaultMessageLocale)` |
| `resolveGeneratedLocale(requested)` | 요청 locale을 generated 지원 locale과 기본 locale에 맞춰 결정합니다. | `resolveGeneratedLocale('en-US') // 'en'` |
| `loadGeneratedMessages(requested)` | Locale을 결정하고 해당 locale 이름과 메시지 Map을 `GeneratedLocaleMessages`로 반환합니다. | `loadGeneratedMessages('ko-KR').messages` |
| `createMessageResolver(...)` | Generated loader를 사용하는 앱 소유 `MessageResolver`를 만듭니다. 선택적인 `onDiagnostic` callback으로 runtime 진단을 받을 수 있습니다. | `createMessageResolver(selected: 'ko-KR')` |
| `MessageKeys` | Catalog key마다 `static const String` 하나를 제공합니다. 값은 원본 key 문자열 그대로입니다. | `messages.text(MessageKeys.commonSave)` |
| `load<Locale>Messages()` | 지원 locale 하나의 generated message Map을 반환합니다. `loadEnMessages()`, `loadKoMessages()`처럼 locale마다 하나씩 생성됩니다. | `loadKoMessages()[MessageKeys.commonSave]` |

일반적인 앱에서는 `createMessageResolver`, `MessageKeys`, `supportedMessageLocales`만으로 충분합니다. Locale 판정 함수와 loader 함수는 직접 연동하거나 진단·테스트가 필요할 때 사용하세요. 보통의 메시지 조회는 `MessageResolver`를 거칩니다.

Generated library를 prefix와 함께 import했다면 그 안의 모든 항목에도 같은 prefix를 붙입니다.

```dart
import 'i18n/catalog.message_i18n.g.dart' as appI18n;

final messages = appI18n.createMessageResolver(selected: 'en-US');
final locales = appI18n.supportedMessageLocales;
final saved = messages.text(appI18n.MessageKeys.commonSave);
```

원본 catalog별 runtime library는 계속 따로 존재합니다. Import prefix는 이름만 구분할 뿐 catalog나 resolver를 하나로 합치지 않습니다.

### 4. 생성된 runtime 사용

파일이 생성되면 `lib/main.dart` 같은 runtime 코드에서 import해 사용합니다. Flutter 연결 방법은 다음 절에서 설명합니다.

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

Runtime library를 만들 때 `MessageKeys`도 함께 생성됩니다. 각 field는 catalog에 쓴 key를 그대로 값으로 가지는 `static const String`입니다.

```dart
abstract final class MessageKeys {
  static const String actionReload = 'action.reload';
  static const String commonSave = 'common.save';
  static const String languageEnglish = 'language.english';
  static const String welcomeUser = 'welcome.user';
}
```

두 형식을 모두 지원합니다.

| 형식 | 사용 시점 |
|---|---|
| `context.tr(MessageKeys.commonSave)` | Compile 시점에 key를 알 수 있을 때 사용합니다. 생성 멤버의 오타·삭제·이름 변경은 compile error가 됩니다. |
| `context.tr('common.save')` | 동적 key 또는 점진적 전환에 사용합니다. 없는 key는 기존 runtime diagnostic으로 보고합니다. |

Builder는 원본 key가 앞에서 설명한 문법에 맞는지 먼저 확인한 다음, 점·하이픈·밑줄로 나뉜 구간을 lowerCamelCase로 바꿉니다. 컴파일 가능한 이름을 만들기 위해 접두사나 접미사, 번호, hash, 별칭을 덧붙이지는 않습니다. 서로 다른 key가 같은 멤버명이 되거나 결과가 Dart 예약어 또는 상속된 `Object` member이면 생성을 중단합니다.

```text
a.a, a_a, a-a  -> MessageKeys.aA  -> build 실패
class           -> MessageKeys.class -> build 실패
123.title       -> invalid_key -> 상수 생성 전 build 실패
```

이 오류는 catalog의 key를 고친 뒤 다시 build해서 해결합니다. 실패한 build는 일부만 들어 있는 `MessageKeys`를 남기지 않습니다. 상수는 첫 build가 성공하면 생기고, 이후에는 build나 watch가 catalog 변경을 처리할 때마다 갱신됩니다. key를 삭제하거나 이름을 바꾸면 기존 멤버 참조가 analyze 또는 compile 단계에서 오류로 드러납니다.

Generated catalog library마다 별도의 `MessageKeys`가 생깁니다. 여러 catalog를 함께 사용한다면 import prefix로 구분하고, key와 resolver도 같은 generated library에서 가져오세요.

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

개발하는 동안에는 watch 명령 하나만 실행해 두면 됩니다. Freezed, 라우터, JSON처럼 앱에 등록된 다른 Builder도 입력이 바뀔 때 같은 watcher에서 함께 실행됩니다.

```bash
dart run build_runner watch
```

## Flutter 설정

Flutter runtime 코드에서도 원본 catalog 대신 generated library를 import합니다. 아래의 `supportedMessageLocales`는 catalog의 `supportedLocales`에서 만들어진 값입니다. `defaultMessageLocale`을 비롯한 나머지 선언은 [생성되는 runtime 항목](#생성되는-runtime-항목)에서 확인할 수 있습니다. `MessageI18nTool`과 원본 catalog는 개발 코드에만 두세요. 자세한 작성 과정은 [개발용 catalog와 코드 생성](#개발용-catalog와-코드-생성)에서 설명합니다. `lib/main.dart` 전체 구성은 다음과 같습니다.

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

`MessageI18nScope`는 `MaterialApp`보다 위에 두세요. 그래야 route, 중첩 Navigator, dialog, bottom sheet, overlay가 같은 resolver를 사용할 수 있습니다. Scope보다 위에서 만들어진 context로는 접근할 수 없습니다.

`flutter_localizations`와 delegate는 앱에서 직접 설정해야 합니다. message_i18n이 앱의 메시지를 번역해도 Material과 Cupertino의 기본 문구까지 자동으로 설정하지는 않습니다. Locale 문자열을 Flutter `Locale`로 바꿀 때는 `messageLocale`이 script와 country 정보를 보존합니다.

번역 문자열은 `build`에서 읽거나 `didChangeDependencies`에서 다시 계산하세요. `initState`에서 한 번만 저장해 둔 문자열은 locale이 바뀌어도 달라지지 않습니다.

## Runtime API와 locale 동작

| Dart resolver | Flutter API | 동작 |
|---|---|---|
| `text(key)` | `context.tr(key)` | 메시지 조회 |
| `format(key, arguments)` | `context.format(key, arguments)` | 이름 기반 문자열 인자 치환 |
| `select(locale)` | `context.updateLocale(locale)` | 언어를 로드하고 listener에 알림 |
| `reload()` | `context.reloadMessages()` | 마지막 요청 언어를 다시 로드하고 알림 |
| `locale` / `selected` | `context.i18n.locale` / `.selected` | 실제 선택 언어 / 원래 요청값 |
| `addListener` / `removeListener` | Scope가 구독 관리 | Flutter 밖에서 변경 구독 |

`tr`, `format`, `context.i18n`을 호출한 위젯은 resolver 변경을 구독합니다. 반면 `updateLocale`과 `reloadMessages`는 구독 없이 resolver를 읽습니다. 직접 접근할 때는 `MessageI18nScope.of`가 구독하고 `read`는 구독하지 않습니다. `maybeOf`를 사용하면 Scope가 없는 경우도 처리할 수 있습니다.

### Locale 선택

Locale은 2~3자리 영문 language code에 선택적인 4자리 script와 2자리 영문 또는 3자리 숫자 region을 붙일 수 있습니다.

| 입력 | 정규화 |
|---|---|
| `en_US` | `en-US` |
| `zh_hant_tw` | `zh-Hant-TW` |
| `ko-KR` | `ko-KR` |

먼저 locale 전체가 지원되는지 확인하고, 일치하지 않으면 뒤쪽 subtag를 하나씩 제거합니다. 끝까지 찾지 못하면 catalog의 기본 언어를 사용합니다. 예를 들어 `zh-Hant-TW → zh-Hant → zh → default` 순서에서 처음 지원되는 항목을 선택합니다. Variant나 extension을 넣었거나 subtag 순서가 잘못되면 fallback하지 않고 `FormatException`을 던집니다.

Resolver는 현재 선택된 메시지 Map 하나만 가지고 있으며 select나 reload가 성공하면 이를 교체합니다. 메시지별 fallback Map이나 전체 locale Map cache는 두지 않습니다. 다만 다른 언어 문자열이 앱 바이너리나 VM heap의 다른 곳에도 전혀 없다는 뜻은 아닙니다.

### Placeholder와 진단

Placeholder는 `[A-Za-z_][A-Za-z0-9_]*`에 맞는 `{identifier}` 형식만 사용할 수 있고, 인자는 `Map<String, String>`으로 전달합니다. 중괄호 escape, 중첩 표현, ICU plural/select/gender와 숫자·날짜 자동 형식 지정은 지원하지 않습니다.

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

진단에는 code, key, locale이 함께 들어갑니다. 엄격한 catalog 검증은 번역 문제를 생성 전에 찾아냅니다. `MessageResolver.fromLoader`는 loader를 직접 연결하거나 테스트 fake를 만들 때 쓰는 저수준 API입니다. 일반 앱에서는 generated factory를 사용하세요.

## 상태 관리와 소유권

앱 전체에서 쓰는 resolver에는 소유자 하나와 UI 알림 방식 하나만 두세요. 아래의 기본 Scope, Riverpod, GetX는 서로 다른 선택지입니다. Riverpod이나 GetX가 resolver를 소유한다면 다시 `MessageI18nScope`로 감싸지 않습니다.

아래 예제는 Flutter 3.47.7, flutter_riverpod 3.4.3, get 4.7.3에서 검증했습니다. Riverpod과 GetX는 앱에서 필요할 때만 추가하며 message_i18n 패키지 자체는 어느 쪽에도 의존하지 않습니다.

### 기본 MessageI18nScope

별도의 상태 관리 도구를 쓰지 않는다면 composition root에서 resolver를 하나 만들고 `MaterialApp` 위의 `MessageI18nScope`에 전달합니다. Scope는 전달받은 resolver를 구독할 뿐 직접 만들거나 dispose하지 않습니다. 위젯에서는 [Flutter 설정](#flutter-설정)의 `context.tr`, `context.format`, `context.updateLocale`, `context.reloadMessages`를 사용할 수 있습니다.

이 context 확장은 상위에 `MessageI18nScope`가 있을 때만 동작합니다. Riverpod과 GetX 방식은 같은 작업을 provider나 controller를 통해 수행하므로 확장을 사용하지 않습니다.

### Riverpod

앱에 `flutter_riverpod`을 추가하고 root를 `ProviderScope`로 감쌉니다. `NotifierProvider`가 generated resolver 하나를 소유하고 변경이 성공할 때마다 새 state wrapper와 revision을 발행합니다. 그러면 `MaterialApp.locale`과 메시지 위젯이 함께 다시 빌드됩니다. Locale 변경과 reload는 notifier를 통해 호출하세요. Resolver를 직접 바꾸면 Riverpod이 새 state를 발행할 기회를 잃습니다.

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

`select`나 `reload`가 성공하면 `MessagesState`는 같은 resolver를 새 state 객체로 감싸서 발행합니다. 이 wrapper와 revision은 UI 갱신을 알리는 값이며 과거 번역의 snapshot이 아닙니다. 이전 wrapper도 공유 중인 mutable resolver를 통해 현재 locale을 읽습니다. Locale 로드가 실패하면 새 state를 발행하지 않으므로 이전 locale이 계속 적용됩니다.

### GetX

앱에 `get`을 추가하고 `GetMaterialApp`을 root로 사용합니다. `runApp` 전에 permanent controller 하나를 등록하고, root `GetBuilder`가 controller를 구독해 `GetMaterialApp.locale`과 메시지 위젯을 함께 다시 빌드하게 합니다.

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

Controller는 `Get.locale`을 resolver의 실제 locale과 맞춘 뒤 `update()` 한 번으로 root `GetMaterialApp`과 메시지 `GetBuilder`를 함께 다시 빌드합니다. 이 예제는 get 4.7.3에서 비동기 전체 앱 reassemble을 수행하는 `Get.updateLocale`을 사용하지 않으므로 widget test frame과 아래 hot reload hook이 충돌하지 않습니다. message_i18n은 GetX `translations`를 등록하거나 `String.tr` 확장을 추가하지 않습니다. message_i18n의 메시지는 controller의 `text`와 `format`으로 조회하세요.

## 개발용 catalog와 코드 생성

`message_i18n_builder`는 annotation이 붙은 const 값을 정적으로 읽어 검사하므로 앱이나 `MessageI18nTool`을 실행하지 않습니다. Locale별 factory와 loader는 한 파일에 생성되며, runtime은 그중 현재 locale의 메시지 Map만 보관합니다.

### Builder 경로와 파일명

| 변경 | 함께 바꿀 항목 |
|---|---|
| `catalog.dart` → `messages.dart` | 앱 import를 `messages.message_i18n.g.dart`로 변경 |
| catalog 디렉터리 이동 | 앱 generated import 및 설정했다면 generate_for 수정 |
| catalog 변수명 변경 | annotation 유지; 생성 loader API는 동일 |
| lib 밖의 입력 사용 | build target sources와 generate_for에 포함 |

Builder는 기본적으로 `lib/` 아래의 Dart 파일을 읽고 generated 파일은 건너뜁니다. Library마다 catalog 하나에 annotation을 붙이세요. 여러 generated library를 함께 import할 때는 각각 prefix를 지정합니다. 출력은 원본 옆에 고정 suffix로 생성되며 CLI의 `generatedDirectory`, `sourcePaths`, `watchEntrypoint` 설정과는 관계가 없습니다.

Builder가 읽을 파일을 제한하려면 앱의 `build.yaml`을 설정합니다.

```yaml
targets:
  $default:
    builders:
      message_i18n_builder:
        generate_for:
          - lib/localization/messages.dart
```

### 선택적인 CLI와 기존 프로젝트

아래 설정은 catalog만 검사하거나 JSON/XLSX를 내보내고 병합할 때, 또는 기존 CLI 생성을 유지할 때만 필요합니다. 일반적인 Builder 흐름에서는 만들지 않아도 됩니다. 기존 프로젝트를 옮길 때는 annotation과 개발 의존성을 추가하고 build한 뒤 앱의 generated import를 바꾸세요. 더 이상 쓰지 않는 이전 generated 디렉터리는 직접 정리해야 합니다. Builder watcher와 CLI watcher를 동시에 실행해서는 안 됩니다.

선택적인 CLI를 사용하려면 `tool/i18n.dart`를 만듭니다.

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

`your_app`은 앱의 `pubspec.yaml`에 선언된 `name` 값으로 바꾸세요.

### 기존 CLI 설정 상세

`MessageI18nTool`은 선택적인 작성용 CLI의 진입점입니다. Const `MessageCatalog`를 전달하면 번역을 검증하고 생성하거나, 변경을 감시하고, 번역 파일을 내보내고 병합할 수 있습니다. 개발자나 CI가 tool entrypoint를 호출할 때만 실행되며 앱을 시작할 때는 동작하지 않습니다.

#### 개발 주기

```text
최초 설정:  catalog 파일 + tool entrypoint + 최초 generate
반복 작업:  catalog 수정 → generate 또는 catalog 수정 → watch 자동 생성
앱 runtime: generated loader → resolver → Dart 또는 Flutter UI
CI:         check --verify-generated
번역 교환:  export → 외부 편집 → merge 후보 → 사람 검토 → catalog 반영
```

Catalog 파일과 tool entrypoint는 보통 처음에 한 번만 만듭니다. 다만 catalog는 계속 관리해야 하는 번역 원본입니다. 메시지나 locale을 수정할 때마다 `generate`를 실행하거나, `watch`를 켜 두어 자동으로 다시 생성하세요.

#### 도구 설정값

| 인자 | 역할 |
|---|---|
| `catalog` | Tool entrypoint가 이미 import한 기준 `MessageCatalog` 객체입니다. 파일 경로가 아닙니다. |
| `sourcePaths` | `watch`가 `.dart` 변경을 감시할 프로젝트 내부의 기존 디렉터리입니다. Catalog 객체를 자동 탐색하지 않습니다. |
| `generatedDirectory` | 언어별 파일, loader, manifest를 저장하는 프로젝트 내부의 전용 디렉터리입니다. 직접 작성한 파일을 넣지 마세요. |
| `watchEntrypoint` | Watch의 각 생성 주기마다 새 프로세스로 실행할 프로젝트 상대 경로의 Dart 진입점입니다. 현재 CLI는 모든 공개 명령을 실행하기 전에도 이 파일이 존재하는지 검사합니다. |
| `projectRoot` | 상대 경로 해석과 파일 안전 검사의 기준 디렉터리입니다. 기본값은 현재 디렉터리입니다. |

#### 경로와 파일명 변경

`lib/i18n/catalog.dart`, `tool/i18n.dart`, `lib/i18n/generated/`은 예시 경로일 뿐입니다. Dart import, 도구 설정, 실행 명령과 runtime import가 실제 위치를 일관되게 가리키면 원하는 구조를 사용할 수 있습니다.

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

명령을 실행할 때도 실제 진입점 경로를 사용합니다.

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

직접 `generate`를 실행하면 `sourcePaths` 밖의 catalog도 Dart import를 통해 읽을 수 있습니다. 하지만 `watch`는 설정한 디렉터리 안의 변경만 감지합니다. 상대 경로는 모두 `projectRoot`에서 시작하며, generated 출력은 프로젝트 안의 전용 디렉터리에 두어야 도구가 안전하게 관리할 수 있습니다.

#### 직접 생성 또는 watch

Catalog 변경 뒤 직접 생성하려면 다음 명령을 실행합니다.

```bash
dart run tool/i18n.dart generate
```

편집 중 자동 생성하려면 다음 명령을 실행해 둡니다.

```bash
dart run tool/i18n.dart watch
```

`watch`는 시작할 때 한 번 생성한 뒤 `sourcePaths` 아래의 `.dart` 파일을 계속 감시합니다. Runtime 코드는 이 경우에도 generated loader만 import하며 작성용 catalog나 tool entrypoint를 사용하지 않습니다.

## CLI 명령

CLI 명령은 `pubspec.yaml`과 설정한 tool entrypoint가 있는 앱 프로젝트 루트에서 실행하세요.

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

`check`는 locale 식별자, 기본 언어와 지원 언어의 관계, 메시지 키, 누락되거나 빈 번역, placeholder 문법과 언어별 일치 여부를 확인합니다. 생성 파일을 쓰지는 않습니다. CI에서 `--verify-generated`를 붙이면 임시 디렉터리에 예상 결과를 만든 뒤 `generatedDirectory`의 도구 소유 파일과 비교합니다. 생성물이 없거나 원본과 맞지 않거나 직접 수정된 경우 명령이 실패합니다.

### `generate`: runtime 파일 생성

```bash
dart run tool/i18n.dart generate
dart run tool/i18n.dart generate --output lib/i18n/generated
```

`generate`는 catalog를 검증하고 locale별 Dart 메시지 파일과 `message_loader.g.dart`, `message_i18n_manifest.json`을 만듭니다. `--output`을 지정하면 이번 실행에만 `generatedDirectory`를 바꿀 수 있습니다. 대상은 프로젝트 안의 전용 디렉터리여야 합니다. 파일을 staging 영역에서 모두 만들고 format한 다음 기존 출력과 교체합니다. 오래된 파일은 manifest에 소유권이 기록된 경우에만 삭제하며 다른 파일은 덮어쓰지 않습니다.

Catalog 내용이나 지원 locale, 생성 설정을 바꾼 뒤에는 `generate`를 다시 실행하세요. 앱 코드는 기존 generated loader 경로를 계속 import하면 됩니다.

### `watch`: 편집 중 자동 생성

```bash
dart run tool/i18n.dart watch
dart run tool/i18n.dart watch --debounce-ms 400
```

`watch`는 시작과 함께 한 번 생성한 뒤 `sourcePaths` 아래의 `.dart` 파일을 감시합니다. 기본적으로 250ms 안에 들어온 연속 변경을 묶고, 각 생성 주기를 새 Dart 프로세스에서 하나씩 실행합니다. 생성 디렉터리와 `build/`, `.dart_tool/`은 반복 실행을 막기 위해 감시하지 않습니다. 한 번 실패해도 마지막 정상 출력은 남겨 둔 채 다음 변경을 기다립니다. 종료하려면 `Ctrl+C`를 누르세요.

생성이 끝난 뒤 메시지 문구만 바뀌었다면 hot reload로 반영할 수 있습니다. Locale 구조나 generated import를 바꿨다면 hot restart가 필요합니다.

### `export`: 번역 전달 파일 생성

```bash
dart run tool/i18n.dart export --locales ko,en --format json
dart run tool/i18n.dart export --locales ko,en --format xlsx --output build/translations.xlsx
dart run tool/i18n.dart export --locales ko,en --format xlsx --split-by-locale
```

`--locales`와 `--format`은 반드시 지정해야 합니다. Locale은 쉼표로 구분하고 형식은 `json` 또는 `xlsx` 중 하나를 선택하세요. `--output`을 생략하면 `build/message_i18n/exports/` 아래에 timestamp로 이름을 붙인 디렉터리가 생깁니다. 모든 언어를 한 파일로 내보낼 때는 형식에 맞는 확장자를 지정합니다. `--split-by-locale`을 쓸 때는 디렉터리를 지정하면 됩니다. 기존 대상은 덮어쓰지 않습니다.

### `merge`: 검토 후보 생성

```bash
dart run tool/i18n.dart merge --input build/translations.json
dart run tool/i18n.dart merge \
  --input build/ko.xlsx \
  --input build/en.xlsx \
  --output build/message_i18n/review
```

병합할 `.json` 또는 `.xlsx` 파일마다 `--input`을 하나씩 붙입니다. 여러 파일에 같은 key와 locale이 있으면 마지막 입력값을 사용하고 warning을 출력합니다. 출력 경로는 프로젝트의 `build/` 아래에 새 디렉터리로 지정하세요. 그 안에 `merged_catalog.dart`와 `key-comparison.json`이 생성됩니다.

`merge`는 원본 catalog를 건드리지 않고, 입력 파일에 빠진 값을 원본에서 가져와 채우지도 않습니다. 후보 파일과 키 비교 결과, warning을 검토한 다음 승인한 내용만 `catalog.dart`에 직접 옮기세요. 마지막으로 `check`와 `generate`를 다시 실행합니다.

### 도움말, 버전, 종료 코드

```bash
dart run tool/i18n.dart --help
dart run tool/i18n.dart <명령> --help
dart run tool/i18n.dart --version
```

종료 코드 **0**은 성공입니다. **1**은 검증, 잘못된 입력 구조, parse, process 또는 파일 작업 오류에 사용하고, **64**는 명령 사용법이 잘못됐다는 뜻입니다. 일반 결과는 stdout으로, 오류와 merge warning은 stderr로 보냅니다. `__watch-cycle`은 watcher 내부 명령이므로 직접 호출하지 마세요.

엄격 검증에서는 `invalid_locale`, `empty_locales`, `duplicate_locale`, `missing_default`, `invalid_key`, `unsupported_locale`, `empty_translation`, `missing_translation`, `unsupported_placeholder`, `placeholder_mismatch`를 보고할 수 있습니다. 결과는 severity, key, locale, code 순으로 정렬합니다. Const Map의 중복 key와 맞지 않는 값 타입은 도구가 실행되기 전에 Dart에서 오류가 납니다.

## 번역 작업 흐름

### 1. 검증된 catalog 내보내기

```bash
dart run tool/i18n.dart export --locales ko,en --format json --output build/translations.json
dart run tool/i18n.dart export --locales ko,en --format xlsx --output build/translations.xlsx
dart run tool/i18n.dart export --locales ko,en --format xlsx --split-by-locale
```

출력 경로를 생략하면 `build/message_i18n/exports/<timestamp>/` 아래에 저장됩니다. 통합 출력은 형식에 맞는 확장자의 파일이고, locale별 분리 출력은 디렉터리입니다. 기존 파일은 그대로 두며 자동으로 정한 디렉터리 이름이 겹치면 suffix를 붙입니다.

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

첫 header는 정확히 `key`여야 하고, 그 뒤에 요청한 순서대로 locale 열이 옵니다. 설명이나 원본 경로, 숨은 metadata 열은 사용하지 않습니다. 모든 셀은 텍스트로 유지하세요. 숫자와 수식 셀은 import할 수 없으며, `=`, `+`, `-`, `@`로 시작하는 값은 export할 때도 명시적인 텍스트로 저장합니다.

Locale을 정규화했을 때 같은 header가 생기거나 key row가 중복되면 구조 오류입니다. 완전히 빈 행은 건너뛰지만 다른 내용이 있으면서 key만 없는 행은 거부합니다. 비어 있는 번역 셀은 빈 문자열로 읽습니다.

### 2. 전달받은 파일 병합

```bash
dart run tool/i18n.dart merge --input build/translations.json --input build/translations.xlsx
```

기본 출력 디렉터리는 `build/message_i18n/merges/<timestamp>/`이며 다음 파일을 생성합니다.

- `merged_catalog.dart`: 독립적인 `mergedCatalog` 후보.
- `key-comparison.json`: 원본 catalog와의 키 차이를 정렬한 보고서.

**Merge는 전달한 파일의 값만 사용합니다.** 원본 catalog를 수정하지 않으며 입력에 없는 key나 번역을 원본에서 채우지도 않습니다. 같은 key와 locale이 겹치면 마지막 입력을 사용하고, warning에 이전 입력과 최종 입력 번호를 표시합니다. 영어 파일만 병합했다면 원본의 한국어와 일본어가 자동으로 따라오지 않습니다.

누락된 언어와 빈 값, placeholder 차이, key 차이는 warning이나 보고서에 남지만 후보 파일은 만들 수 있습니다. Exit 0은 후보 생성에 성공했다는 뜻일 뿐 엄격 검증까지 통과했다는 뜻은 아닙니다. 파일 구조와 I/O 오류는 exit 1을 반환합니다. 병합 결과는 앱의 `build/` 디렉터리 아래에만 쓸 수 있습니다.

키 비교에서는 번역 문구가 같은지 확인하지 않고 어떤 key가 있는지만 비교합니다. 사람이 읽는 보고서는 현재 다음과 같이 한국어로 출력됩니다.

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

같은 결과를 기계가 읽을 수 있는 형식으로도 제공합니다.

```json
{"matched":false,"originalOnly":["old.key"],"mergedOnly":["new.key"]}
```

### 3. 검토 후 반영

Warning과 번역 문구, key 차이를 확인한 뒤 승인한 내용만 원본 Dart catalog에 직접 반영하세요. 기본 Builder 흐름에서는 이어서 `dart run build_runner build`를 실행합니다. 기존 CLI로 생성한다면 `check`, `generate`, `check --verify-generated` 순서로 확인하세요. 후보를 원본에 자동으로 적용하는 명령은 없습니다.

## 생성 파일과 복구

Build가 실패하면 build_runner가 이전 출력 파일을 지울 수 있습니다. Catalog를 고치고 생성이 다시 성공할 때까지 앱을 reload하지 마세요.

`.message_i18n.g.dart` 경로는 build_runner만 사용해야 합니다. 직접 만든 파일을 두거나 생성물을 수정해도 다음 build에서 교체될 수 있습니다. `build --only-check`는 공개 출력 파일을 쓰거나 지우지 않고 차이만 보고합니다. 내부 `.dart_tool` cache의 변경은 별개입니다. Catalog 검증에 실패했다면 원본을 고쳐 다시 build하거나 watch가 재시도하도록 두세요. Builder 출력에는 기존 CLI의 rollback 보장이 적용되지 않습니다.

### 기존 CLI 파일 보존


Generated 디렉터리는 도구가 소유하는 출력 영역입니다. Manifest에는 schema, catalog fingerprint, locale, key 개수와 소유 파일 목록이 들어갑니다. 번역을 바꿀 때는 생성 파일을 직접 고치지 말고 catalog를 수정한 뒤 다시 생성하세요.

생성 파일을 커밋해 변경 내용을 검토하고 같은 결과를 재현할 수도 있고, analyze와 build 전에 매번 생성할 수도 있습니다. 커밋하는 방식을 택했다면 CI에서 `check --verify-generated`를 실행해 원본과 어긋난 파일을 찾으세요.

CLI는 catalog를 검증한 뒤 완성된 파일을 staging 영역에서 만들고 format하며, 대상이 그사이 바뀌지 않았는지 확인한 다음 소유 파일을 교체합니다. 교체 방식은 **파일별 rename과 실패 시 rollback**이며 파일 집합 전체를 한 번에 바꾸지는 않습니다. Manifest에 없는 파일은 보존하고 오래된 파일도 manifest가 소유한 경우에만 삭제합니다. 경로 이탈과 symlink, 관련 없는 파일의 소유권을 가져오는 시도는 거부됩니다.

같은 위치에 두 프로세스가 동시에 생성하지 못하도록 OS lock을 사용합니다. `.generated.message_i18n.lock` 같은 0-byte guard 파일은 출력 옆에 남아 Git에서 제외되지만, 실제 lock은 프로세스가 끝날 때 해제됩니다. 경합을 피하려고 guard 파일을 지우지 마세요. 강제 종료나 전원 손실이 있었다면 `check --verify-generated`로 확인하고 필요할 때 다시 생성합니다. 갑작스러운 모든 중단에서 파일 집합 전체를 복구한다고 보장할 수는 없습니다.

## Watch와 hot reload

별도 터미널에서 실행합니다.

```bash
dart run build_runner watch
```

build_runner는 입력 파일과 그 의존성이 바뀌는지 추적합니다. 실패 메시지를 확인해 원본을 고치면 watcher를 끄지 않아도 다음 변경에서 다시 시도합니다. 종료할 때는 Ctrl-C를 누르세요. 등록된 다른 Builder도 같은 watch 프로세스를 사용합니다.

생성이 성공해도 Flutter 앱이 자동으로 reload되지는 않습니다. Root owner는 hot reload 과정에서 Flutter가 `reassemble()`을 호출할 때 기존 resolver를 다시 불러와야 합니다. [Flutter 설정](#flutter-설정)의 `AppRoot`는 다음과 같이 직접 처리합니다.

```dart
@override
void reassemble() {
  super.reassemble();
  _resolver.reload();
}
```

Riverpod 예제는 `RiverpodApp.reassemble()`에서 `ref.read(messagesProvider.notifier).reload()`를 호출합니다. GetX 예제는 `GetXApp.reassemble()`에서 `Get.find<MessagesController>().reload()`를 호출합니다. 각 hook은 평소 UI 갱신을 발행하는 같은 owner를 통과합니다.

| 변경 | 개발 중 작업 |
|---|---|
| 기존 번역 문구 | 생성 후 owner의 `_resolver.reload()` hook이 연결된 hot reload |
| 새 메시지 키와 사용 코드 | 생성 후 hot reload |
| 지원 언어 목록이나 초기화 구조 | 생성 후 hot restart |

Watcher는 Flutter daemon과 연결하지 않으므로 reload를 요청할 수 없습니다. Hot reload를 해도 `main`, `initState`, 이미 실행된 static 초기화는 다시 실행되지 않습니다. 자세한 동작은 [Flutter 공식 hot reload 문서](https://docs.flutter.dev/tools/hot-reload)를 참고하세요.

## 문제 해결

| 증상 | 확인 또는 조치 |
|---|---|
| 번역 대신 키가 표시됨 | 키와 `missing_key` 진단 확인; catalog 변경 후 재생성 |
| `{name}`이 남음 | `format`에 `name` 문자열 인자 전달 |
| 요청한 언어와 실제 언어가 다름 | `selected`, `locale`, 지원 언어와 fallback 순서 확인 |
| 위젯이 이전 언어를 표시함 | Rebuild 중 번역을 읽고 resolver 하나를 공유하세요. 기본 방식은 Scope를 route 위에 두고, Riverpod·GetX 방식은 모든 route와 dialog가 같은 provider/controller를 구독해야 합니다. |
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

생성 파일을 Git에서 제외한다면 먼저 생성한 뒤 앱을 analyze, test, build하세요. 그다음 실행하는 only-check는 방금 만든 결과가 맞는지만 확인하며 커밋된 파일의 최신성을 검사하지는 않습니다. 출력 파일이 없을 때 only-check가 실패하는 것은 정상입니다. 기존 CLI의 `check --verify-generated`는 CLI가 만드는 다중 파일과 manifest만 검사합니다.

함께 검증한 버전은 build_runner 2.16.2, build 4.0.11, Freezed 4.0.3, go_router_builder 4.5.2, go_router 18.1.1, json_serializable 6.15.2이며 Dart 3.13과 Flutter 3.47을 사용했습니다. Builder 자체는 Dart 3.11부터 지원합니다. 다른 조합을 사용한다면 의존성이 정상적으로 해석되는지와 생성 코드가 실제로 실행되는지를 모두 확인하세요.

## 지원 범위와 제한

현재 버전은 메시지 key의 String 상수까지 생성하며 placeholder별 타입 함수는 만들지 않습니다. ICU 복수형·성별, 원격 번역 배포, 번역용 웹 UI, 네이티브 리소스 생성, 원본 자동 반영과 locale 지연 다운로드도 지원 범위에 포함되지 않습니다. 사용자가 선택한 locale을 저장하고 다시 불러오는 일은 앱이 담당합니다.

## 라이선스

message_i18n은 [MIT No Attribution (MIT-0)](LICENSE) 라이선스를 사용합니다. 저작권자를 표시하지 않아도 상업적 사용을 포함한 모든 목적으로 사용·수정·배포할 수 있습니다. 소프트웨어는 보증 없이 제공되며 의존 패키지에는 각 패키지의 라이선스가 적용됩니다.

## README 참고 자료

문서 구성은 다음과 같은 pub.dev 주요 패키지의 README를 참고했습니다. 표현과 구성만 참고했으며 runtime 의존성이나 성능 비교 대상은 아닙니다.

| 참고 자료 | 반영한 문서 구성 |
|---|---|
| [Get](https://pub.dev/packages/get) | 언어 선택과 기능별 안내 |
| [Dio](https://pub.dev/packages/dio) | 목차, 빠른 시작, API별 예제 |
| [http](https://pub.dev/packages/http) | 최소 사용 예제에서 소유권·검증 안내로 이어지는 구성 |
| [path_provider](https://pub.dev/packages/path_provider) | 요구사항과 지원 기능 표 |
| [shared_preferences](https://pub.dev/packages/shared_preferences) | API 동작과 제한 사항의 명시 |
| [url_launcher](https://pub.dev/packages/url_launcher) | 완결된 설정 예제와 구성 시 주의점 |

영어판과 한국어판은 동일한 API와 작업 흐름을 설명합니다.
