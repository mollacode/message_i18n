import 'package:message_i18n/message_i18n.dart';

@MessageI18nCatalog()
const appCatalog = MessageCatalog(
  defaultLocale: 'ko',
  supportedLocales: ['ko', 'en', 'ja'],
  messages: {
    'app.title': LocalizedMessage({
      'ko': '메시지 다국어 예제',
      'en': 'Message translations',
      'ja': 'メッセージ翻訳',
    }),
    'common.save': LocalizedMessage({'ko': '저장', 'en': 'Save', 'ja': '保存'}),
    'welcome.user': LocalizedMessage({
      'ko': '{name}님, 환영합니다.',
      'en': 'Welcome, {name}.',
      'ja': '{name}さん、ようこそ。',
    }),
    'action.next': LocalizedMessage({
      'ko': '다음 화면',
      'en': 'Next screen',
      'ja': '次の画面',
    }),
    'action.dialog': LocalizedMessage({
      'ko': '대화상자',
      'en': 'Dialog',
      'ja': 'ダイアログ',
    }),
    'action.reload': LocalizedMessage({
      'ko': '번역 다시 읽기',
      'en': 'Reload messages',
      'ja': '翻訳を再読込',
    }),
    'sample.multiline': LocalizedMessage({
      'ko': '첫 줄 🌍\n두 번째 줄',
      'en': 'First line 🌍\nSecond line',
      'ja': '一行目 🌍\n二行目',
    }),
  },
);
