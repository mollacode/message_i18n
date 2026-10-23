import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../model/message_catalog.dart';
import '../runtime/locale_normalizer.dart';
import 'exchange.dart';
import 'generation.dart';
import 'merge.dart';
import 'validation.dart';
import 'watch.dart';

/// Consumer-owned entrypoint supplies a Dart catalog directly.
class MessageI18nTool {
  /// Creates the command runner used by a consumer's `tool/i18n.dart` file.
  ///
  /// Relative paths are resolved from [projectRoot], which defaults to the
  /// current directory. [sourcePaths] must remain inside the project and
  /// [generatedDirectory] must be a separate directory owned by the tool.
  MessageI18nTool({
    required this.catalog,
    required this.sourcePaths,
    required this.generatedDirectory,
    required this.watchEntrypoint,
    String? projectRoot,
  }) : projectRoot = p.normalize(
         p.absolute(projectRoot ?? Directory.current.path),
       );

  /// Canonical Dart catalog used by authoring commands.
  final MessageCatalog catalog;

  /// Project-relative directories watched for canonical source changes.
  final List<String> sourcePaths;

  /// Project-relative directory owned by generated runtime files.
  final String generatedDirectory;

  /// Project-relative Dart entrypoint launched for fresh watch cycles.
  final String watchEntrypoint;

  /// Absolute normalized root used to resolve and constrain file operations.
  final String projectRoot;

  /// Executes [args] and assigns the resulting command status to [exitCode].
  Future<void> run(List<String> args) async {
    exitCode = await execute(args);
  }

  /// Executes one command and returns its process-style exit code.
  ///
  /// Optional [output] and [error] callbacks make command results observable in
  /// tests and embedding tools. Usage errors return 64; catalog, process, and
  /// filesystem failures return 1.
  Future<int> execute(
    List<String> arguments, {
    void Function(String)? output,
    void Function(String)? error,
  }) async {
    final void Function(String) out =
        output ?? (message) => stdout.writeln(message);
    final void Function(String) err =
        error ?? (message) => stderr.writeln(message);
    final parser = _parser();
    ArgResults parsed;
    try {
      parsed = parser.parse(arguments);
      if (parsed.flag('help')) {
        out(_usage(parser));
        return 0;
      }
      if (parsed.flag('version')) {
        out('message_i18n 0.1.0');
        return 0;
      }
      final command = parsed.command;
      if (command == null || command.rest.isNotEmpty) {
        throw const _UsageException(
          'A command is required; positional arguments are not accepted',
        );
      }
      if (command.flag('help')) {
        out(parser.commands[command.name]!.usage);
        return 0;
      }
      if (!File(p.join(projectRoot, 'pubspec.yaml')).existsSync() ||
          !File(_path(watchEntrypoint)).existsSync()) {
        throw const FormatException(
          'Run from the consumer project root (pubspec.yaml and tool entrypoint required)',
        );
      }
      switch (command.name) {
        case 'check':
          _requireValid();
          if (command.flag('verify-generated')) {
            await generateCatalog(
              catalog,
              Directory(_path(generatedDirectory)),
              verifyOnly: true,
            );
          }
          out('Catalog check passed.');
        case 'generate':
        case '__watch-cycle':
          final target = _path(command.option('output') ?? generatedDirectory);
          if (!p.isWithin(projectRoot, target) ||
              sourcePaths.any((s) => _path(s) == target)) {
            throw const FormatException(
              'Generated output must be a dedicated directory inside the project',
            );
          }
          final result = await generateCatalog(catalog, Directory(target));
          out(
            'Generated ${catalog.supportedLocales.length} locales, ${catalog.messages.length} keys: $result (${p.relative(target, from: projectRoot)})',
          );
        case 'watch':
          final debounce = int.tryParse(command.option('debounce-ms')!);
          if (debounce == null || debounce < 0) {
            throw const _UsageException(
              'debounce-ms must be a nonnegative integer',
            );
          }
          final paths = sourcePaths.map(_path).toList();
          if (paths.isEmpty ||
              paths.any(
                (s) =>
                    !Directory(s).existsSync() || !p.isWithin(projectRoot, s),
              )) {
            throw const FormatException(
              'sourcePaths must be existing project directories',
            );
          }
          for (final path in paths) {
            rejectLinks(path);
          }
          await watchCatalog(
            projectRoot: projectRoot,
            sourcePaths: paths,
            generatedDirectory: _path(generatedDirectory),
            entrypoint: _path(watchEntrypoint),
            debounceMs: debounce,
            output: out,
            error: err,
          );
        case 'export':
          final rawLocales = command.option('locales');
          final format = command.option('format');
          if (rawLocales == null || format == null) {
            throw const _UsageException(
              'export requires --locales and --format json|xlsx',
            );
          }
          _requireValid();
          final locales = rawLocales
              .split(',')
              .map(normalizeLocale)
              .toSet()
              .toList();
          final normalized = normalizeCatalog(catalog);
          final unknown = locales
              .where((l) => !normalized.supportedLocales.contains(l))
              .toList();
          if (unknown.isNotEmpty) {
            throw FormatException(
              'Unknown export locales: ${unknown.join(', ')}',
            );
          }
          final split = command.flag('split-by-locale');
          final requestedOutput = command.option('output');
          if (requestedOutput != null &&
              ((split && p.extension(requestedOutput).isNotEmpty) ||
                  (!split && p.extension(requestedOutput) != '.$format'))) {
            throw const _UsageException(
              'output must be a directory for split export, or a matching file extension',
            );
          }
          final document = selectTranslations(normalized, locales);
          if (split || requestedOutput == null) {
            final directory = uniqueOutputDirectory(
              _path(
                requestedOutput ?? 'build/message_i18n/exports/${_timestamp()}',
              ),
            );
            try {
              if (split) {
                for (final locale in locales) {
                  _writeExchange(
                    File(p.join(directory.path, '$locale.$format')),
                    selectTranslations(normalized, [locale]),
                    format,
                  );
                }
              } else {
                _writeExchange(
                  File(p.join(directory.path, 'translations.$format')),
                  document,
                  format,
                );
              }
              out('Exported ${p.relative(directory.path, from: projectRoot)}');
            } catch (_) {
              directory.deleteSync(recursive: true);
              rethrow;
            }
          } else {
            final file = File(_path(requestedOutput));
            _writeExchange(file, document, format);
            out('Exported ${p.relative(file.path, from: projectRoot)}');
          }
        case 'merge':
          final inputs = command.multiOption('input');
          if (inputs.isEmpty) {
            throw const _UsageException('merge requires at least one --input');
          }
          final result = mergeDocuments(
            catalog,
            inputs.map((f) => readExchange(File(_path(f)))).toList(),
          );
          final directory = await writeMerge(
            result,
            projectRoot,
            _path(
              command.option('output') ??
                  'build/message_i18n/merges/${_timestamp()}',
            ),
          );
          for (final warning in result.warnings) {
            err('warning $warning');
          }
          out(result.comparison.report());
          out('Candidate: ${p.relative(directory.path, from: projectRoot)}');
      }
      return 0;
    } on ArgParserException catch (exception) {
      err(exception.message);
      err(_usage(parser));
      return 64;
    } on _UsageException catch (exception) {
      err(exception.message);
      err(_usage(parser));
      return 64;
    } on FormatException catch (exception) {
      err(exception.message);
      return 1;
    } on FileSystemException catch (exception) {
      err('File operation failed: ${exception.message}');
      return 1;
    } on ProcessException {
      err('Could not start Dart process');
      return 1;
    }
  }

  void _requireValid() {
    final issues = validateCatalog(catalog);
    if (issues.isNotEmpty) throw FormatException(issues.join('\n'));
  }

  String _path(String value) =>
      p.normalize(p.absolute(p.join(projectRoot, value)));

  void _writeExchange(File file, ExchangeDocument document, String format) {
    rejectLinks(file.path);
    if (file.existsSync()) {
      throw const FileSystemException('Export destination already exists');
    }
    final bytes = format == 'json' ? null : encodeXlsx(document);
    file.parent.createSync(recursive: true);
    if (bytes == null) {
      file.writeAsStringSync(encodeJson(document));
    } else {
      file.writeAsBytesSync(bytes);
    }
  }
}

String _timestamp() =>
    DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');

class _UsageException implements Exception {
  const _UsageException(this.message);
  final String message;
}

ArgParser _parser() {
  final root = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addFlag('version', negatable: false);
  for (final name in [
    'check',
    'generate',
    '__watch-cycle',
    'watch',
    'export',
    'merge',
  ]) {
    final command = root.addCommand(name)
      ..addFlag('help', abbr: 'h', negatable: false);
    switch (name) {
      case 'check':
        command.addFlag('verify-generated', negatable: false);
      case 'generate':
      case '__watch-cycle':
        command.addOption('output');
      case 'watch':
        command.addOption('debounce-ms', defaultsTo: '250');
      case 'export':
        command
          ..addOption('locales')
          ..addOption('format', allowed: ['json', 'xlsx'])
          ..addOption('output')
          ..addFlag('split-by-locale', negatable: false);
      case 'merge':
        command
          ..addMultiOption('input', splitCommas: false)
          ..addOption('output');
    }
  }
  return root;
}

String _usage(ArgParser parser) =>
    'dart run tool/i18n.dart <check|generate|watch|export|merge> [options]\n${parser.usage}';
