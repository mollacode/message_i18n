import 'package:flutter/widgets.dart';
import 'package:message_i18n/message_i18n.dart';
import 'message_i18n_scope.dart';

/// Message lookup and locale commands for contexts below [MessageI18nScope].
extension MessageI18nContext on BuildContext {
  /// Returns the resolver and subscribes this context to message changes.
  MessageResolver get i18n => MessageI18nScope.of(this);

  /// Returns the active translation for [key] and subscribes to changes.
  String tr(String key) => i18n.text(key);

  /// Formats [key] with named [arguments] and subscribes to changes.
  String format(String key, Map<String, String> arguments) =>
      i18n.format(key, arguments);

  /// Selects [locale] without subscribing the calling context.
  void updateLocale(String locale) =>
      MessageI18nScope.read(this).select(locale);

  /// Reloads the current selection without subscribing the calling context.
  void reloadMessages() => MessageI18nScope.read(this).reload();
}
