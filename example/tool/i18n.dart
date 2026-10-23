import 'package:message_i18n/message_i18n_tool.dart';
import 'package:message_i18n_example/i18n/catalog.dart';

Future<void> main(List<String> args) => MessageI18nTool(
  catalog: appCatalog,
  sourcePaths: const ['lib/i18n'],
  generatedDirectory: 'lib/i18n/generated',
  watchEntrypoint: 'tool/i18n.dart',
).run(args);
