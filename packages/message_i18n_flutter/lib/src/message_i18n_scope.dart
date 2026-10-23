import 'package:flutter/widgets.dart';
import 'package:message_i18n/message_i18n.dart';

/// Non-owning bridge; place above MaterialApp and all Navigators.
class MessageI18nScope extends StatefulWidget {
  /// Exposes an app-owned [resolver] to [child] and its descendants.
  ///
  /// The scope subscribes to the resolver but never creates or disposes it.
  const MessageI18nScope({
    super.key,
    required this.resolver,
    required this.child,
  });

  /// Resolver owned by the surrounding application.
  final MessageResolver resolver;

  /// Widget subtree that can access [resolver].
  final Widget child;

  /// Returns the resolver and subscribes [context], or returns `null` without a scope.
  static MessageResolver? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_MessageState>()?.resolver;

  /// Returns the resolver and subscribes [context].
  ///
  /// Throws [FlutterError] when no ancestor [MessageI18nScope] exists.
  static MessageResolver of(BuildContext context) =>
      maybeOf(context) ??
      (throw FlutterError(
        'MessageI18nScope is missing. Place it above MaterialApp.',
      ));

  /// Non-listening lookup for event handlers.
  ///
  /// Throws [FlutterError] when no ancestor [MessageI18nScope] exists.
  static MessageResolver read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_MessageState>()?.resolver ??
      (throw FlutterError(
        'MessageI18nScope is missing. Place it above MaterialApp.',
      ));

  /// Creates the state that manages the resolver listener subscription.
  @override
  State<MessageI18nScope> createState() => _MessageI18nScopeState();
}

class _MessageI18nScopeState extends State<MessageI18nScope> {
  var _version = 0;
  @override
  void initState() {
    super.initState();
    widget.resolver.addListener(_changed);
  }

  void _changed() => setState(() => _version++);
  @override
  void didUpdateWidget(MessageI18nScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.resolver, widget.resolver)) {
      oldWidget.resolver.removeListener(_changed);
      widget.resolver.addListener(_changed);
      _version++;
    }
  }

  @override
  void dispose() {
    widget.resolver.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _MessageState(
    resolver: widget.resolver,
    version: _version,
    child: widget.child,
  );
}

class _MessageState extends InheritedWidget {
  const _MessageState({
    required this.resolver,
    required this.version,
    required super.child,
  });
  final MessageResolver resolver;
  final int version;
  @override
  bool updateShouldNotify(_MessageState oldWidget) =>
      version != oldWidget.version || !identical(resolver, oldWidget.resolver);
}
