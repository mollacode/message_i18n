import 'dart:io';

Future<void> main(List<String> arguments) async {
  if (arguments.any((a) => a != '--build')) {
    stderr.writeln('Usage: dart run tool/verify.dart [--build]');
    exitCode = 64;
    return;
  }
  final root = Directory.current.path;
  final commands = <(String, List<String>, String)>[
    ('dart', ['pub', 'get'], '.'),
    ('dart', ['pub', 'get'], 'packages/message_i18n'),
    ('dart', ['pub', 'get'], 'packages/message_i18n_builder'),
    (
      'dart',
      ['analyze', '--fatal-infos', '--fatal-warnings'],
      'packages/message_i18n_builder',
    ),
    ('dart', ['test'], 'packages/message_i18n_builder'),
    ('flutter', ['pub', 'get'], 'packages/message_i18n_flutter'),
    ('flutter', ['pub', 'get'], 'example'),
    ('flutter', ['pub', 'get'], 'tool/fixtures/build_runner_consumer'),
    (
      'dart',
      ['run', 'build_runner', 'build'],
      'tool/fixtures/build_runner_consumer',
    ),
    ('dart', ['run', 'build_runner', 'build'], 'example'),
    ('dart', ['format', '--output=none', '--set-exit-if-changed', '.'], '.'),
    ('dart', ['analyze', '--fatal-infos', '--fatal-warnings'], '.'),
    (
      'dart',
      ['analyze', '--fatal-infos', '--fatal-warnings'],
      'packages/message_i18n',
    ),
    ('dart', ['test'], 'packages/message_i18n'),
    (
      'flutter',
      ['analyze', '--fatal-infos', '--fatal-warnings'],
      'packages/message_i18n_flutter',
    ),
    ('flutter', ['test'], 'packages/message_i18n_flutter'),
    ('dart', ['run', 'build_runner', 'build', '--only-check'], 'example'),
    ('flutter', ['analyze', '--fatal-infos', '--fatal-warnings'], 'example'),
    ('flutter', ['test'], 'example'),
    if (arguments.contains('--build'))
      (
        'flutter',
        [
          'build',
          Platform.isMacOS
              ? 'macos'
              : Platform.isWindows
              ? 'windows'
              : Platform.isLinux
              ? 'linux'
              : 'web',
          '--debug',
        ],
        'example',
      ),
    if (arguments.contains('--build') && Platform.isLinux)
      ('flutter', ['build', 'web', '--debug'], 'example'),
  ];
  verifyBoundaries(root);
  for (final command in commands) {
    stdout.writeln(
      'VERIFY ${command.$3}: ${command.$1} ${command.$2.join(' ')}',
    );
    final process = await Process.start(
      command.$1,
      command.$2,
      workingDirectory: '$root/${command.$3}',
      mode: ProcessStartMode.inheritStdio,
      runInShell: Platform.isWindows,
    );
    final code = await process.exitCode;
    if (code != 0) {
      exitCode = code;
      return;
    }
  }
  stdout.writeln(
    'PASS: repository verification. Actual VM reload is a separate probe.',
  );
}

void verifyBoundaries(String root) {
  for (final package in ['message_i18n', 'message_i18n_flutter']) {
    final spec = File(
      '$root/packages/$package/pubspec.yaml',
    ).readAsStringSync();
    final dependencies = spec
        .split('dev_dependencies:')
        .first
        .split('dependencies:')
        .last;
    if (RegExp(
      r'^  (get|riverpod|flutter_riverpod|provider):',
      multiLine: true,
    ).hasMatch(dependencies)) {
      throw StateError('State manager runtime dependency in $package');
    }
    if (package == 'message_i18n' &&
        RegExp(r'^  flutter:', multiLine: true).hasMatch(spec)) {
      throw StateError('Core requires Flutter SDK');
    }
  }
  final core = Directory('$root/packages/message_i18n/lib');
  for (final file
      in core
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
    final source = file.readAsStringSync();
    if (source.contains('package:flutter') ||
        source.contains('dart:ui') ||
        source.contains('package:message_i18n_flutter')) {
      throw StateError('Core Flutter dependency: ${file.path}');
    }
  }
  for (final base in [
    'packages/message_i18n/lib',
    'packages/message_i18n_flutter/lib',
  ]) {
    for (final file
        in Directory('$root/$base')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      if (RegExp(
        r"package:(get|riverpod|flutter_riverpod|provider)/",
      ).hasMatch(file.readAsStringSync())) {
        throw StateError('Runtime state-manager dependency: ${file.path}');
      }
    }
  }
  for (final file
      in Directory('$root/example/lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
    if (RegExp(r"import .*catalog\.dart").hasMatch(file.readAsStringSync())) {
      throw StateError('Runtime catalog import: ${file.path}');
    }
  }
  final barrel = File(
    '$root/packages/message_i18n/lib/message_i18n.dart',
  ).readAsStringSync();
  if (barrel.contains('src/tool/')) {
    throw StateError('Runtime barrel exposes tools');
  }
  stdout.writeln('PASS: package/import boundaries');
}
