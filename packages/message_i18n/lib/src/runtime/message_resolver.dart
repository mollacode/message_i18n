import 'message_formatter.dart';

/// A resolved locale and the messages loaded for that locale only.
class GeneratedLocaleMessages {
  /// Creates locale data and prevents later mutation through [messages].
  GeneratedLocaleMessages(this.locale, Map<String, String> messages)
    : messages = Map.unmodifiable(messages);

  /// Canonical locale selected by the loader.
  final String locale;

  /// Unmodifiable messages for [locale].
  final Map<String, String> messages;
}

/// Loads one resolved locale for a requested locale string.
typedef MessageLoader =
    GeneratedLocaleMessages Function(String requestedLocale);

/// Listens for successful message selection or reload operations.
typedef MessageListener = void Function();

/// App-owned resolver; no global singleton, locale cache or Flutter dependency.
class MessageResolver {
  /// Creates a resolver and synchronously loads [selected].
  ///
  /// The application owns this resolver and should share the same instance with
  /// all consumers that need coordinated locale changes. Loader failures leave
  /// construction unsuccessful instead of creating a partially initialized
  /// resolver.
  MessageResolver.fromLoader({
    required String selected,
    required MessageLoader loader,
    this.onDiagnostic,
  }) : _selected = selected,
       _loader = loader,
       _current = loader(selected);

  String _selected;
  final MessageLoader _loader;
  GeneratedLocaleMessages _current;

  /// Optional receiver for missing keys and formatting argument problems.
  final MessageDiagnosticCallback? onDiagnostic;
  final Set<MessageListener> _listeners = {};

  /// Canonical locale currently loaded by the resolver.
  String get locale => _current.locale;

  /// Most recent locale string requested by the caller.
  String get selected => _selected;

  /// Returns the active translation for [key].
  ///
  /// A missing key emits a `missing_key` diagnostic and returns [key].
  String text(String key) {
    final value = _current.messages[key];
    if (value != null) return value;
    _diagnose('missing_key', key);
    return key;
  }

  /// Formats the active translation for [key] with named [arguments].
  ///
  /// Missing and extra arguments emit diagnostics. Missing placeholders remain
  /// in the returned text, and unsupported placeholder syntax returns the
  /// untranslated active value after emitting a diagnostic.
  String format(String key, Map<String, String> arguments) {
    final value = text(key);
    Set<String> names;
    try {
      names = placeholderNames(value);
    } on FormatException {
      _diagnose('unsupported_placeholder', key);
      return value;
    }
    if (names.difference(arguments.keys.toSet()).isNotEmpty) {
      _diagnose('missing_argument', key);
    }
    if (arguments.keys.toSet().difference(names).isNotEmpty) {
      _diagnose('extra_argument', key);
    }
    return formatMessage(value, arguments);
  }

  /// Loads [requestedLocale], replaces the current messages, and notifies listeners.
  ///
  /// Loading completes before any state is changed, so a loader exception keeps
  /// the previous selection and message map intact.
  void select(String requestedLocale) {
    // Load first so failures cannot partially change selection or active data.
    final next = _loader(requestedLocale);
    _selected = requestedLocale;
    _current = next;
    _notify();
  }

  /// Reloads the most recently requested locale and notifies listeners.
  ///
  /// This supports regenerated message files during development without
  /// requiring the caller to track the previous request.
  void reload() {
    _current = _loader(_selected);
    _notify();
  }

  /// Registers [listener] once, using callback identity to prevent duplicates.
  void addListener(MessageListener listener) => _listeners.add(listener);

  /// Stops notifying [listener] if it is currently registered.
  void removeListener(MessageListener listener) => _listeners.remove(listener);

  void _notify() {
    for (final listener in List<MessageListener>.of(_listeners)) {
      listener();
    }
  }

  void _diagnose(String code, String key) => onDiagnostic?.call(
    MessageDiagnostic(code: code, key: key, locale: locale),
  );
}
