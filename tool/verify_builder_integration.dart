import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Runs real builders in an isolated consumer; never edits the checked-in fixture.
Future<void> main() async {
  final root = Directory.current.absolute.path.replaceAll('\\', '/');
  final fixture = Directory('$root/tool/fixtures/build_runner_consumer');
  final temp = Directory.systemTemp.createTempSync('message_i18n_builders_');
  Process? watcher;
  final subscriptions = <StreamSubscription<String>>[];
  final logs = <String>[];
  var successes = 0;
  var failures = 0;
  File file(String path) => File('${temp.path}/$path');
  void require(bool value, String message) {
    if (!value) throw StateError(message);
  }

  Future<void> command(
    String executable,
    List<String> args, {
    bool fails = false,
  }) async {
    final process = await Process.start(
      executable,
      args,
      workingDirectory: temp.path,
      runInShell: Platform.isWindows,
    );
    final out = process.stdout.transform(utf8.decoder).join();
    final err = process.stderr.transform(utf8.decoder).join();
    final code = await process.exitCode.timeout(
      const Duration(minutes: 5),
      onTimeout: () {
        process.kill();
        throw TimeoutException('$executable $args');
      },
    );
    final output = '${await out}${await err}';
    require(
      fails ? code != 0 : code == 0,
      '$executable $args exit $code\n$output',
    );
    stdout.writeln('PASS ${args.join(' ')} (exit $code)');
  }

  Future<void> build({bool check = false, bool fails = false}) => command(
    Platform.resolvedExecutable,
    ['run', 'build_runner', 'build', if (check) '--only-check'],
    fails: fails,
  );
  Future<void> until(bool Function() done, String label) async {
    final deadline = DateTime.now().add(const Duration(minutes: 2));
    while (!done()) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('$label\n${logs.join('\n')}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  bool contains(String path, String text) =>
      file(path).existsSync() && file(path).readAsStringSync().contains(text);
  const generated = 'lib/catalog.message_i18n.g.dart';
  try {
    for (final entity in fixture.listSync(recursive: true)) {
      if (entity is! File) continue;
      final relative = entity.path
          .substring(fixture.path.length + 1)
          .replaceAll('\\', '/');
      if (!(relative == 'pubspec.yaml' ||
          relative == 'analysis_options.yaml' ||
          relative.startsWith('lib/') ||
          relative.startsWith('test/'))) {
        continue;
      }
      if (relative.endsWith('.g.dart') || relative.endsWith('.freezed.dart')) {
        continue;
      }
      file(relative).parent.createSync(recursive: true);
      file(relative).writeAsStringSync(
        entity.readAsStringSync().replaceAll(
          '../../../packages/',
          '$root/packages/',
        ),
      );
    }
    file('untouched.txt').writeAsStringSync('user owned');
    await command('flutter', ['pub', 'get']);
    await build(check: true, fails: true);
    require(!file(generated).existsSync(), 'only-check wrote missing output');
    await build();
    await command('flutter', ['test']);
    await command('flutter', ['analyze', '--fatal-infos']);
    await build(check: true);
    final normal = file(generated).readAsStringSync();
    file(generated).writeAsStringSync('$normal\n// manual change\n');
    final modified = file(generated).readAsStringSync();
    await build(check: true, fails: true);
    require(
      file(generated).readAsStringSync() == modified,
      'only-check overwrote modified file',
    );
    await build();
    require(
      file(generated).readAsStringSync() == normal,
      'build did not repair output',
    );
    final catalog = file('lib/catalog.dart').readAsStringSync();
    file('lib/catalog.dart').writeAsStringSync(
      catalog.replaceFirst(
        'messages: {',
        "messages: {\n    'a.a': LocalizedMessage({'en': 'A', 'ko': '가'}),\n    'a_a': LocalizedMessage({'en': 'B', 'ko': '나'}),",
      ),
    );
    await build(check: true, fails: true);
    require(
      file(generated).readAsStringSync() == normal,
      'collision only-check changed generated output',
    );
    file('lib/catalog.dart').writeAsStringSync(catalog);
    final words = file('lib/words.dart').readAsStringSync();
    final models = file('lib/models.dart').readAsStringSync();
    final routes = file('lib/routes.dart').readAsStringSync();
    file(
      'lib/words.dart',
    ).writeAsStringSync(words.replaceFirst('Save', 'Stale'));
    await build(check: true, fails: true);
    require(
      file(generated).readAsStringSync() == normal,
      'only-check wrote stale output',
    );
    watcher = await Process.start(Platform.resolvedExecutable, [
      'run',
      'build_runner',
      'watch',
    ], workingDirectory: temp.path);
    void line(String value) {
      logs.add(value);
      if (value.contains('Built with build_runner')) successes++;
      if (value.contains('Failed to build')) failures++;
    }

    subscriptions.add(
      watcher.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(line),
    );
    subscriptions.add(
      watcher.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(line),
    );
    await until(
      () => successes > 0 && contains(generated, 'Stale'),
      'initial watch',
    );
    for (var i = 0; i < 10; i++) {
      file(
        'lib/words.dart',
      ).writeAsStringSync(words.replaceFirst('Save', 'Changed$i'));
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    await until(
      () => contains(generated, 'Changed9'),
      'imported const rapid edits',
    );
    final collisionFailures = failures;
    file('lib/catalog.dart').writeAsStringSync(
      catalog.replaceFirst(
        'messages: {',
        "messages: {\n    'a.a': LocalizedMessage({'en': 'A', 'ko': '가'}),\n    'a_a': LocalizedMessage({'en': 'B', 'ko': '나'}),",
      ),
    );
    await until(
      () => failures > collisionFailures,
      'MessageKeys identifier collision',
    );
    require(
      logs.any((line) => line.contains('MessageKeys.aA')),
      'collision diagnostic did not name MessageKeys.aA',
    );
    file('lib/catalog.dart').writeAsStringSync(catalog);
    await until(
      () =>
          contains(generated, 'Changed9') &&
          contains(generated, 'class MessageKeys'),
      'MessageKeys collision recovery',
    );
    final beforeFailure = failures;
    file(
      'lib/catalog.dart',
    ).writeAsStringSync(catalog.replaceFirst("'ko': '저장'", "'ko': ''"));
    await until(() => failures > beforeFailure, 'validation failure');
    stdout.writeln(
      'OBSERVED failed watch output exists: ${file(generated).existsSync()}',
    );
    require(
      file('untouched.txt').readAsStringSync() == 'user owned',
      'user file modified',
    );
    file('lib/catalog.dart').writeAsStringSync(catalog);
    file(
      'lib/words.dart',
    ).writeAsStringSync(words.replaceFirst('Save', 'Recovered'));
    file('lib/models.dart').writeAsStringSync(
      models.replaceFirst(
        'required String name',
        'required String name, @Default(7) int age',
      ),
    );
    file(
      'lib/routes.dart',
    ).writeAsStringSync(routes.replaceFirst("path: '/'", "path: '/next'"));
    await until(
      () =>
          contains(generated, 'Recovered') &&
          contains('lib/models.g.dart', "'age'") &&
          contains('lib/models.freezed.dart', 'int get age') &&
          contains('lib/routes.g.dart', '/next'),
      'all builders recover',
    );
    final syntaxFailures = failures;
    file('lib/catalog.dart').writeAsStringSync('this is invalid Dart');
    await until(() => failures > syntaxFailures, 'syntax failure');
    file('lib/catalog.dart').writeAsStringSync(catalog);
    file('lib/words.dart').writeAsStringSync(words);
    file('lib/models.dart').writeAsStringSync(models);
    file('lib/routes.dart').writeAsStringSync(routes);
    await until(
      () =>
          contains(generated, '"Save"') &&
          !contains('lib/models.g.dart', "'age'") &&
          !contains('lib/routes.g.dart', '/next'),
      'restore all inputs',
    );
    watcher.kill(ProcessSignal.sigint);
    await watcher.exitCode.timeout(const Duration(seconds: 30));
    watcher = null;
    await build(check: true);
    file(
      'lib/catalog.dart',
    ).writeAsStringSync(catalog.replaceFirst('@MessageI18nCatalog()', ''));
    await build();
    require(!file(generated).existsSync(), 'annotation removal left output');
    file('lib/catalog.dart').writeAsStringSync(catalog);
    await build();
    file(generated).deleteSync();
    await build(check: true, fails: true);
    require(
      !file(generated).existsSync(),
      'only-check recreated deleted output',
    );
    await build();
    await command('flutter', ['test']);
    await build(check: true);

    // Moving a source changes its declared output; independent catalogs coexist.
    final smoke = file('test/smoke_test.dart').readAsStringSync();
    file('lib/catalog.dart').renameSync(file('lib/renamed.dart').path);
    file('test/smoke_test.dart').writeAsStringSync(
      smoke.replaceAll(
        'catalog.message_i18n.g.dart',
        'renamed.message_i18n.g.dart',
      ),
    );
    file('lib/second.dart').writeAsStringSync(catalog);
    await build();
    require(!file(generated).existsSync(), 'move left obsolete output');
    require(
      file('lib/renamed.message_i18n.g.dart').existsSync(),
      'move lost output',
    );
    require(
      file('lib/second.message_i18n.g.dart').existsSync(),
      'second library lost output',
    );
    await command('flutter', ['test']);
    file('build.yaml').writeAsStringSync(r"""
targets:
  $default:
    builders:
      message_i18n_builder:
        generate_for:
          - lib/renamed.dart
""");
    await build();
    require(
      !file('lib/second.message_i18n.g.dart').existsSync(),
      'generate_for ignored',
    );
    require(
      file('lib/models.g.dart').existsSync(),
      'generate_for affected other builder',
    );
    file('lib/second.dart').deleteSync();
    file('build.yaml').deleteSync();
    file('lib/renamed.dart').renameSync(file('lib/catalog.dart').path);
    file('test/smoke_test.dart').writeAsStringSync(smoke);
    await build();
    require(
      !file('lib/renamed.message_i18n.g.dart').existsSync(),
      'restore left moved output',
    );

    // Restart watch and interrupt while an input change is pending. A subsequent
    // build must reconcile the cache and output without touching user files.
    final restarted = await Process.start(Platform.resolvedExecutable, [
      'run',
      'build_runner',
      'watch',
    ], workingDirectory: temp.path);
    watcher = restarted;
    var restartedReady = false;
    subscriptions.add(
      restarted.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((value) {
            logs.add(value);
            if (value.contains('Built with build_runner')) {
              restartedReady = true;
            }
          }),
    );
    subscriptions.add(
      restarted.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(logs.add),
    );
    await until(() => restartedReady, 'watch restart');
    file(
      'lib/words.dart',
    ).writeAsStringSync(words.replaceFirst('Save', 'Interrupted'));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    restarted.kill(ProcessSignal.sigint);
    await restarted.exitCode.timeout(const Duration(seconds: 30));
    watcher = null;
    await build();
    require(
      contains(generated, 'Interrupted'),
      'interrupted watch did not recover',
    );
    file('lib/words.dart').writeAsStringSync(words);
    await build();
    await command('flutter', ['test']);
    await build(check: true);
    require(
      file('untouched.txt').readAsStringSync() == 'user owned',
      'user file changed',
    );
    stdout.writeln(
      'PASS: four real builders, read-only checks, watch errors/recovery, lifecycle and runtime.',
    );
  } finally {
    if (watcher != null) {
      watcher.kill();
      await watcher.exitCode.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          watcher!.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
    }
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    temp.deleteSync(recursive: true);
  }
}
