import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../model/message_catalog.dart';
import 'validation.dart';
import 'emission.dart';

export 'emission.dart'
    show
        generatedMarker,
        manifestName,
        dartLiteral,
        localeToken,
        factoryName,
        messageKeyIdentifier,
        emitCatalog;

/// Reject links in existing ancestors as well as a linked destination.
void rejectLinks(String path) {
  var cursor = p.normalize(p.absolute(path));
  while (true) {
    if (FileSystemEntity.typeSync(cursor, followLinks: false) ==
        FileSystemEntityType.link) {
      throw FileSystemException(
        'Symbolic links are not allowed in output paths',
        path,
      );
    }
    final parent = p.dirname(cursor);
    if (parent == cursor) break;
    cursor = parent;
  }
}

Map<String, String> directorySnapshot(Directory directory) {
  if (!directory.existsSync()) return {};
  final result = <String, String>{};
  for (final entity in directory.listSync(
    recursive: true,
    followLinks: false,
  )) {
    final relative = p.relative(entity.path, from: directory.path);
    if (entity is Link) {
      throw FileSystemException(
        'Symbolic link inside generated directory',
        relative,
      );
    }
    result[relative] = entity is File
        ? sha256.convert(entity.readAsBytesSync()).toString()
        : '<directory>';
  }
  return result;
}

bool snapshotsEqual(Map<String, String> a, Map<String, String> b) =>
    a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

Set<String> readOwnedFiles(Directory target) {
  final manifest = File(p.join(target.path, manifestName));
  if (!manifest.existsSync()) return {};
  final Object? raw = jsonDecode(manifest.readAsStringSync());
  if (raw is! Map<String, dynamic> ||
      raw['schemaVersion'] != 1 ||
      raw['ownedFiles'] is! List<Object?>) {
    throw const FormatException('Invalid generated manifest');
  }
  final files = raw['ownedFiles'] as List<Object?>;
  final owned = <String>{};
  for (final name in files) {
    if (name is! String ||
        p.isAbsolute(name) ||
        p.basename(name) != name ||
        !RegExp(r'^[a-z0-9_]+\.g\.dart$').hasMatch(name) ||
        !owned.add(name)) {
      throw const FormatException('Unsafe or duplicate manifest path');
    }
    final file = File(p.join(target.path, name));
    if (file.existsSync() &&
        !file.readAsStringSync().startsWith(generatedMarker)) {
      throw const FormatException('Manifest claims a non-generated file');
    }
  }
  return {...owned, manifestName};
}

class GenerationResult {
  const GenerationResult({
    required this.created,
    required this.changed,
    required this.unchanged,
    required this.deleted,
  });
  final int created;
  final int changed;
  final int unchanged;
  final int deleted;
  @override
  String toString() =>
      'created=$created changed=$changed unchanged=$unchanged deleted=$deleted';
}

/// Stages everything, then replaces owned files with rollback on failure.
/// The set is not atomically visible to other processes; each file is complete.
final _activeTargets = <String>{};

Future<GenerationResult> generateCatalog(
  MessageCatalog catalog,
  Directory target, {
  bool verifyOnly = false,
  Future<void> Function(Directory stage)? beforeFormat,
  Future<void> Function(Directory stage)? beforeCommit,
  void Function(int writes)? afterWrite,
}) async {
  // Validate before creating any filesystem artifacts.
  final issues = validateCatalog(catalog);
  if (issues.isNotEmpty) throw FormatException(issues.join('\n'));
  rejectLinks(target.path);
  final identity = p.normalize(p.absolute(target.path));
  if (!_activeTargets.add(identity)) {
    throw const FileSystemException(
      'Generation already active for this target',
    );
  }
  RandomAccessFile? guard;
  var interrupted = false;
  final signals = <StreamSubscription<ProcessSignal>>[];
  if (!verifyOnly) {
    signals.add(ProcessSignal.sigint.watch().listen((_) => interrupted = true));
    if (!Platform.isWindows) {
      signals.add(
        ProcessSignal.sigterm.watch().listen((_) => interrupted = true),
      );
    }
  }
  try {
    if (!verifyOnly) {
      target.parent.createSync(recursive: true);
      final lockFile = File(
        p.join(
          target.parent.path,
          '.${p.basename(target.path)}.message_i18n.lock',
        ),
      );
      rejectLinks(lockFile.path);
      guard = lockFile.openSync(mode: FileMode.append);
      guard.lockSync();
    }
    return await _generateCatalog(
      catalog,
      target,
      verifyOnly: verifyOnly,
      beforeFormat: beforeFormat,
      beforeCommit: (stage) async {
        await beforeCommit?.call(stage);
        if (interrupted) {
          throw const FileSystemException(
            'Generation interrupted before commit',
          );
        }
      },
      afterWrite: afterWrite,
    );
  } finally {
    // Closing releases the OS lock even on failure. Keep the zero-byte inode to
    // avoid unlink/recreate races between processes; this is not a held lock.
    guard?.closeSync();
    for (final signal in signals) {
      await signal.cancel();
    }
    _activeTargets.remove(identity);
  }
}

Future<GenerationResult> _generateCatalog(
  MessageCatalog catalog,
  Directory target, {
  bool verifyOnly = false,
  Future<void> Function(Directory stage)? beforeFormat,
  Future<void> Function(Directory stage)? beforeCommit,
  void Function(int writes)? afterWrite,
}) async {
  final outputs = emitCatalog(catalog);
  rejectLinks(target.path);
  final existed = target.existsSync();
  final before = directorySnapshot(target);
  final owned = readOwnedFiles(target);
  for (final name in outputs.keys) {
    if (before.containsKey(name) && !owned.contains(name)) {
      throw FileSystemException('Refusing to overwrite an unowned file', name);
    }
  }
  // System temporary storage for read-only verification; sibling staging for writes.
  final parent = verifyOnly ? Directory.systemTemp : target.parent;
  if (!parent.existsSync()) parent.createSync(recursive: true);
  final stage = parent.createTempSync('.message_i18n_stage_');
  try {
    for (final e in outputs.entries) {
      File(p.join(stage.path, e.key)).writeAsStringSync(e.value);
    }
    await beforeFormat?.call(stage);
    final dartFiles = outputs.keys
        .where((n) => n.endsWith('.dart'))
        .map((n) => p.join(stage.path, n))
        .toList();
    final formatted = await Process.run(Platform.resolvedExecutable, [
      'format',
      '--language-version=3.11',
      '--page-width=80',
      ...dartFiles,
    ]);
    if (formatted.exitCode != 0) {
      throw const FormatException('Generated source formatting failed');
    }
    final prepared = {
      for (final name in outputs.keys)
        name: File(p.join(stage.path, name)).readAsBytesSync(),
    };
    final stale = owned.difference(outputs.keys.toSet());
    final created = prepared.keys.where((n) => !before.containsKey(n)).length;
    final unchanged = prepared.entries
        .where((e) => before[e.key] == sha256.convert(e.value).toString())
        .length;
    final result = GenerationResult(
      created: created,
      changed: prepared.length - created - unchanged,
      unchanged: unchanged,
      deleted: stale.length,
    );
    if (verifyOnly) {
      if (created != 0 || result.changed != 0 || stale.isNotEmpty) {
        throw const FormatException('Generated files are stale; run generate');
      }
      return result;
    }
    await beforeCommit?.call(stage);
    if (!snapshotsEqual(before, directorySnapshot(target))) {
      throw const FileSystemException(
        'Generated directory changed during staging',
      );
    }
    final backup = <String, List<int>>{
      for (final name in owned)
        if (File(p.join(target.path, name)).existsSync())
          name: File(p.join(target.path, name)).readAsBytesSync(),
    };
    final touched = <String>[];
    target.createSync(recursive: true);
    try {
      // Manifest last; stale deletion happens only after all outputs are ready.
      for (final e in prepared.entries) {
        if (before[e.key] == sha256.convert(e.value).toString()) continue;
        final path = p.join(target.path, e.key);
        touched.add(e.key);
        File(p.join(stage.path, e.key)).renameSync(path);
        afterWrite?.call(touched.length);
      }
      for (final name in stale) {
        touched.add(name);
        final file = File(p.join(target.path, name));
        if (file.existsSync()) file.deleteSync();
      }
    } catch (_) {
      for (final name in touched.reversed) {
        final file = File(p.join(target.path, name));
        final bytes = backup[name];
        if (bytes != null) {
          file.writeAsBytesSync(bytes, flush: true);
        } else if (file.existsSync()) {
          file.deleteSync();
        }
      }
      if (!existed && target.existsSync() && target.listSync().isEmpty) {
        target.deleteSync();
      }
      rethrow;
    }
    return result;
  } finally {
    if (stage.existsSync()) stage.deleteSync(recursive: true);
  }
}
