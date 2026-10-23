import 'package:message_i18n/message_i18n.dart';

import 'words.dart';

@MessageI18nCatalog()
const catalog = MessageCatalog(
  defaultLocale: 'en',
  supportedLocales: ['en', 'ko'],
  messages: {
    'save': LocalizedMessage({'en': saveWord, 'ko': '저장'}),
  },
);
