/// Selects a top-level const `MessageCatalog` for build_runner generation.
///
/// Each source library may contain one annotated catalog. Import the generated
/// standalone library from application code, not the annotated source library.
/// MessageCatalog is defined in the public message_i18n library.
class MessageI18nCatalog {
  /// Marks a catalog for generation.
  const MessageI18nCatalog();
}
