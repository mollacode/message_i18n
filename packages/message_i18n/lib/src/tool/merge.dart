import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../model/message_catalog.dart';
import '../runtime/locale_normalizer.dart';
import 'exchange.dart';
import 'generation.dart';
import 'validation.dart';

class KeyComparison {
  KeyComparison(Iterable<String> original, Iterable<String> merged)
    : originalOnly = original.toSet().difference(merged.toSet()).toList()
        ..sort(),
      mergedOnly = merged.toSet().difference(original.toSet()).toList()..sort();
  final List<String> originalOnly;
  final List<String> mergedOnly;
  bool get matched => originalOnly.isEmpty && mergedOnly.isEmpty;
  Map<String, Object> toJson() => {
    'matched': matched,
    'originalOnly': originalOnly,
    'mergedOnly': mergedOnly,
  };
  String report() => matched
      ? '원본과 병합본의 키가 일치합니다.'
      : [
          if (originalOnly.isNotEmpty)
            '원본에만 있는 키는 다음과 같습니다.\n${originalOnly.map((k) => '- $k').join('\n')}',
          if (mergedOnly.isNotEmpty)
            '병합본에만 있는 키는 다음과 같습니다.\n${mergedOnly.map((k) => '- $k').join('\n')}',
        ].join('\n');
}

class MergeResult {
  const MergeResult(this.candidate, this.comparison, this.warnings);
  final MessageCatalog candidate;
  final KeyComparison comparison;
  final List<String> warnings;
}

MergeResult mergeDocuments(
  MessageCatalog original,
  List<ExchangeDocument> documents,
) {
  final data = <String, Map<String, String>>{};
  final origins = <String, Map<String, int>>{};
  final warnings = <String>[];
  final importedLocales = <String>{};
  for (var index = 0; index < documents.length; index++) {
    final document = documents[index];
    importedLocales.addAll(document.locales);
    for (final entry in document.messages.entries) {
      final values = data.putIfAbsent(entry.key, () => {});
      final positions = origins.putIfAbsent(entry.key, () => {});
      for (final translation in entry.value.entries) {
        final previous = positions[translation.key];
        if (previous != null) {
          warnings.add(
            'duplicate_value key=${entry.key} locale=${translation.key} input=${previous + 1}->${index + 1}',
          );
        }
        values[translation.key] = translation.value;
        positions[translation.key] = index;
      }
    }
  }
  final sourceLocales = original.supportedLocales.map(normalizeLocale).toList();
  final candidate = MessageCatalog(
    defaultLocale: normalizeLocale(original.defaultLocale),
    supportedLocales: [
      ...sourceLocales,
      ...importedLocales.difference(sourceLocales.toSet()).toList()..sort(),
    ],
    messages: {
      for (final key in data.keys.toList()..sort())
        key: LocalizedMessage(data[key]!),
    },
  );
  warnings.addAll(
    validateCatalog(candidate).map((issue) => 'candidate ${issue.toString()}'),
  );
  return MergeResult(
    candidate,
    KeyComparison(original.messages.keys, data.keys),
    warnings,
  );
}

String emitCandidate(MessageCatalog candidate) =>
    '''// Review candidate only. Original source was not changed.
import 'package:message_i18n/message_i18n.dart';

const mergedCatalog = MessageCatalog(
  defaultLocale: ${dartLiteral(candidate.defaultLocale)},
  supportedLocales: [${candidate.supportedLocales.map(dartLiteral).join(', ')}],
  messages: {
${candidate.messages.entries.map((e) => '    ${dartLiteral(e.key)}: LocalizedMessage({${(e.value.translations.keys.toList()..sort()).map((l) => '${dartLiteral(l)}: ${dartLiteral(e.value.translations[l]!)}').join(', ')}}),').join('\n')}
  },
);
''';

Directory uniqueOutputDirectory(String base) {
  rejectLinks(base);
  Directory(p.dirname(base)).createSync(recursive: true);
  var suffix = 0;
  while (true) {
    final candidate = suffix == 0 ? base : '$base-$suffix';
    suffix++;
    final reservation = File(
      p.join(p.dirname(candidate), '.${p.basename(candidate)}.reservation'),
    );
    try {
      reservation.createSync(exclusive: true);
    } on FileSystemException {
      if (FileSystemEntity.typeSync(reservation.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        continue;
      }
      rethrow;
    }
    try {
      if (FileSystemEntity.typeSync(candidate, followLinks: false) !=
          FileSystemEntityType.notFound) {
        continue;
      }
      return Directory(candidate)..createSync();
    } finally {
      reservation.deleteSync();
    }
  }
}

void requireBuildOutput(String projectRoot, String output) {
  final build = p.normalize(p.join(projectRoot, 'build'));
  final target = p.normalize(p.absolute(output));
  rejectLinks(target);
  if (!p.isWithin(build, target)) {
    throw const FormatException(
      'Merge output must be a new directory inside project build/',
    );
  }
}

Future<Directory> writeMerge(
  MergeResult result,
  String projectRoot,
  String output,
) async {
  requireBuildOutput(projectRoot, output);
  final directory = uniqueOutputDirectory(output);
  try {
    final candidate = File(p.join(directory.path, 'merged_catalog.dart'))
      ..writeAsStringSync(emitCandidate(result.candidate));
    final format = await Process.run(Platform.resolvedExecutable, [
      'format',
      '--language-version=3.11',
      '--page-width=80',
      candidate.path,
    ]);
    if (format.exitCode != 0) {
      throw const FormatException('Candidate formatting failed');
    }
    File(p.join(directory.path, 'key-comparison.json')).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(result.comparison.toJson())}\n',
    );
    return directory;
  } catch (_) {
    directory.deleteSync(recursive: true);
    rethrow;
  }
}
