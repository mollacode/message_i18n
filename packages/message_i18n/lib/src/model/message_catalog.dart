/// One message and its translations. Canonical sources use const collections.
class LocalizedMessage {
  /// Creates a message whose keys are supported locale names.
  ///
  /// Validation is performed by the authoring tool rather than this model.
  const LocalizedMessage(this.translations);

  /// Translation text keyed by locale name.
  final Map<String, String> translations;
}

/// The single source of truth, imported by the consumer tool, not the app.
class MessageCatalog {
  /// Creates a catalog without normalizing or validating its values.
  ///
  /// Use the authoring tool's `check` command before generating runtime files.
  const MessageCatalog({
    required this.defaultLocale,
    required this.supportedLocales,
    required this.messages,
  });

  /// Locale used when a requested locale cannot be resolved.
  final String defaultLocale;

  /// Locales for which every message must provide a translation.
  final List<String> supportedLocales;

  /// Messages keyed by the stable keys used by application code.
  final Map<String, LocalizedMessage> messages;
}
