import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:dart_style/dart_style.dart';
import 'package:message_i18n/message_i18n.dart';
import 'package:message_i18n/message_i18n_codegen.dart';

class CatalogBuilder implements Builder {
  @override
  final buildExtensions = const {
    '.dart': ['.message_i18n.g.dart'],
  };

  @override
  Future<void> build(BuildStep step) async {
    if (!await step.resolver.isLibrary(step.inputId)) return;
    final library = await step.inputLibrary;
    for (final fragment in library.fragments) {
      final node = await step.resolver.astNodeFor(fragment, resolve: true);
      node?.accept(_AnnotationTargets());
    }
    final marked = <Element>[];
    void visit(Element element) {
      // Synthetic accessors carry the variable's annotations too.
      if (element is PropertyAccessorElement) return;
      final annotations = element.metadata.annotations.where((annotation) {
        final value = annotation.computeConstantValue();
        return value != null &&
            _isCore(value, 'MessageI18nCatalog', 'message_i18n_catalog.dart');
      }).toList();
      if (annotations.length > 1) {
        throw FormatException(
          'Duplicate MessageI18nCatalog annotation: ${element.name}',
        );
      }
      if (annotations.isNotEmpty) marked.add(element);
      for (final child in element.children) {
        visit(child);
      }
    }

    visit(library);
    if (marked.isEmpty) return;
    if (marked.length != 1 || marked.single is! TopLevelVariableElement) {
      throw const FormatException(
        'Use MessageI18nCatalog on exactly one top-level const catalog per library.',
      );
    }
    // Reject constant-expression errors before their values lose information
    // (for example duplicate map keys), including imported consumer constants.
    await for (final dependency in step.resolver.libraries) {
      if (dependency != library &&
          !dependency.uri.toString().startsWith(
            'package:${step.inputId.package}/',
          ) &&
          !dependency.uri.toString().startsWith(
            'asset:${step.inputId.package}/',
          )) {
        continue;
      }
      final resolved = await dependency.session.getResolvedLibraryByElement(
        dependency,
      );
      if (resolved is! ResolvedLibraryResult) {
        throw FormatException(
          'Could not resolve catalog dependency: ${dependency.uri}',
        );
      }
      final errors = resolved.units
          .expand((unit) => unit.diagnostics)
          .where((error) => error.diagnosticCode.severity.name == 'ERROR');
      if (errors.isNotEmpty) {
        throw FormatException(
          '${dependency.uri}: ${errors.map((e) => e.message).join('\n')}',
        );
      }
    }
    final variable = marked.single as TopLevelVariableElement;
    final value = variable.computeConstantValue();
    if (!variable.isConst ||
        value == null ||
        !value.hasKnownValue ||
        !_isCore(value, 'MessageCatalog', 'message_catalog.dart')) {
      throw FormatException(
        '${variable.name}: expected a resolvable const MessageCatalog.',
      );
    }
    String string(DartObject? object, String field) {
      final result = object?.toStringValue();
      if (result == null) {
        throw FormatException('${variable.name}: invalid $field');
      }
      return result;
    }

    final locales = value.getField('supportedLocales')?.toListValue();
    final messages = value.getField('messages')?.toMapValue();
    if (locales == null || messages == null) {
      throw FormatException('${variable.name}: invalid catalog collections');
    }
    final catalogMessages = <String, LocalizedMessage>{};
    for (final entry in messages.entries) {
      final key = string(entry.key, 'message key');
      final message = entry.value;
      if (message == null ||
          !_isCore(message, 'LocalizedMessage', 'message_catalog.dart')) {
        throw FormatException('$key: expected LocalizedMessage');
      }
      final translations = message.getField('translations')?.toMapValue();
      if (translations == null) {
        throw FormatException('$key: invalid translations');
      }
      catalogMessages[key] = LocalizedMessage({
        for (final translation in translations.entries)
          string(translation.key, 'locale'): string(
            translation.value,
            'translation',
          ),
      });
    }
    final catalog = MessageCatalog(
      defaultLocale: string(value.getField('defaultLocale'), 'defaultLocale'),
      supportedLocales: [
        for (final locale in locales) string(locale, 'supportedLocales'),
      ],
      messages: catalogMessages,
    );
    final issues = validateCatalog(catalog);
    if (issues.isNotEmpty) {
      throw FormatException('${variable.name}:\n${issues.join('\n')}');
    }
    final output = DartFormatter(
      languageVersion: DartFormatter.latestLanguageVersion,
    ).format(emitStandaloneCatalog(catalog));
    await step.writeAsString(step.allowedOutputs.single, output);
  }
}

bool _isCore(DartObject value, String name, String file) {
  final type = value.type;
  return type is InterfaceType &&
      type.element.name == name &&
      type.element.library.uri.toString() ==
          'package:message_i18n/src/model/$file';
}

class _AnnotationTargets extends RecursiveAstVisitor<void> {
  @override
  void visitAnnotation(Annotation node) {
    final value = node.elementAnnotation?.computeConstantValue();
    if (value != null &&
        _isCore(value, 'MessageI18nCatalog', 'message_i18n_catalog.dart') &&
        node.parent is! TopLevelVariableDeclaration) {
      throw const FormatException(
        'MessageI18nCatalog requires a top-level const variable.',
      );
    }
    super.visitAnnotation(node);
  }
}
