import 'package:message_i18n/message_i18n.dart';

// Put this in lib/catalog.dart in a consumer with message_i18n_builder.
// Run dart run build_runner build, then import catalog.message_i18n.g.dart.
@MessageI18nCatalog()
const catalog = MessageCatalog(
  defaultLocale: 'en',
  supportedLocales: ['en', 'ko'],
  messages: {
    'save': LocalizedMessage({'en': 'Save', 'ko': '저장'}),
  },
);
