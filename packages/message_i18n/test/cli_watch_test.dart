import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:message_i18n/src/tool/exchange.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late File catalog;
  String source(String value) =>
      '''import 'package:message_i18n/message_i18n.dart';
const appCatalog = MessageCatalog(defaultLocale: 'ko', supportedLocales: ['ko','en'], messages: {'save': LocalizedMessage({'ko': '$value', 'en': 'Save'})});
''';
  Future<ProcessResult> cli(List<String> args, {String? cwd}) => Process.run(
    Platform.resolvedExecutable,
    [p.join(root.path, 'tool/i18n.dart'), ...args],
    workingDirectory: cwd ?? root.path,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  setUpAll(() async {
    root = Directory(
      Directory.systemTemp
          .createTempSync('consumer space 한글_')
          .resolveSymbolicLinksSync(),
    );
    Directory('${root.path}/lib/i18n').createSync(recursive: true);
    Directory('${root.path}/tool').createSync();
    final packageRoot = Directory.current.absolute.path.replaceAll('\\', '/');
    File('${root.path}/pubspec.yaml').writeAsStringSync(
      'name: fixture_consumer\nenvironment:\n  sdk: ">=3.11.0 <4.0.0"\ndependencies:\n  message_i18n:\n    path: ${jsonEncode(packageRoot)}\n',
    );
    catalog = File('${root.path}/lib/i18n/catalog.dart')
      ..writeAsStringSync(source('저장'));
    File('${root.path}/tool/i18n.dart').writeAsStringSync(
      '''import 'package:message_i18n/message_i18n_tool.dart';
import '../lib/i18n/catalog.dart';
Future<void> main(List<String> args) => MessageI18nTool(catalog: appCatalog, sourcePaths: ['lib/i18n'], generatedDirectory: 'lib/i18n/generated', watchEntrypoint: 'tool/i18n.dart').run(args);
''',
    );
    final get = await Process.run(
      Platform.resolvedExecutable,
      ['pub', 'get', '--offline'],
      workingDirectory: root.path,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    expect(get.exitCode, 0, reason: '${get.stderr}');
  });
  tearDownAll(() => root.deleteSync(recursive: true));
  test('bad arguments fail before any outputs', () async {
    for (final args in <List<String>>[
      [],
      ['unknown'],
      ['export'],
      ['merge'],
      ['watch', '--debounce-ms', '-1'],
      ['watch', '--debounce-ms', 'bad'],
      ['generate', '--unknown'],
    ]) {
      final result = await cli(args);
      expect(result.exitCode, 64, reason: '$args: ${result.stderr}');
    }
    expect(Directory('${root.path}/build').existsSync(), isFalse);
    expect((await cli(['--help'])).exitCode, 0);
    expect((await cli(['--version'])).stdout, contains('0.1.0'));
    expect((await cli(['check'], cwd: '${root.path}/lib')).exitCode, 1);
  });
  test(
    'full CLI flow, strict failures and permissive merge preserve source',
    () async {
      final originalHash = sha256.convert(catalog.readAsBytesSync());
      expect((await cli(['check'])).exitCode, 0);
      expect((await cli(['generate'])).exitCode, 0);
      expect((await cli(['check', '--verify-generated'])).exitCode, 0);
      final generated = File(
        '${root.path}/lib/i18n/generated/messages_ko.g.dart',
      );
      final hash = sha256.convert(generated.readAsBytesSync());
      catalog.writeAsStringSync(source(''));
      expect((await cli(['generate'])).exitCode, 1);
      expect(sha256.convert(generated.readAsBytesSync()), hash);
      catalog.writeAsStringSync(
        source('저장').replaceFirst("'save'", "'App.Title'"),
      );
      final uppercase = await cli(['generate']);
      expect(uppercase.exitCode, 1);
      expect(uppercase.stderr, contains('invalid_key'));
      expect(uppercase.stderr, contains(r'^[a-z][a-z0-9]*'));
      expect(sha256.convert(generated.readAsBytesSync()), hash);
      catalog.writeAsStringSync(source('저장'));
      for (final format in ['json', 'xlsx']) {
        final result = await cli([
          'export',
          '--locales',
          'ko,en',
          '--format',
          format,
          '--output',
          'build/translations.$format',
        ]);
        expect(result.exitCode, 0, reason: '${result.stderr}');
      }
      expect(
        (await cli([
          'export',
          '--locales',
          'ko,en',
          '--format',
          'xlsx',
          '--split-by-locale',
          '--output',
          'build/split',
        ])).exitCode,
        0,
      );
      expect(File('${root.path}/build/split/ko.xlsx').existsSync(), isTrue);
      expect(
        (await cli(['export', '--locales', 'fr', '--format', 'json'])).exitCode,
        1,
      );
      final matrix = readExchange(File('${root.path}/build/translations.xlsx'));
      for (final locale in ['ko', 'en']) {
        final split = readExchange(
          File('${root.path}/build/split/$locale.xlsx'),
        );
        expect(split.locales, [locale]);
        expect(split.messages, {
          for (final e in matrix.messages.entries)
            e.key: {locale: e.value[locale]!},
        });
      }
      final merged = await cli([
        'merge',
        '--input',
        'build/translations.json',
        '--input',
        'build/translations.xlsx',
      ]);
      expect(merged.exitCode, 0, reason: '${merged.stderr}');
      expect(merged.stdout, contains('원본과 병합본의 키가 일치합니다.'));
      File(
        '${root.path}/build/incomplete.json',
      ).writeAsStringSync('{"new":{"en":"{name}"}}');
      final mismatch = await cli(['merge', '--input', 'build/incomplete.json']);
      expect(mismatch.exitCode, 0);
      expect(mismatch.stdout, contains('원본에만 있는 키는 다음과 같습니다.'));
      expect(mismatch.stdout, contains('병합본에만 있는 키는 다음과 같습니다.'));
      File('${root.path}/build/broken.json').writeAsStringSync('{');
      expect(
        (await cli(['merge', '--input', 'build/broken.json'])).exitCode,
        1,
      );
      expect(
        (await cli([
          'merge',
          '--input',
          'build/translations.json',
          '--output',
          'outside',
        ])).exitCode,
        1,
      );
      expect(sha256.convert(catalog.readAsBytesSync()), originalHash);
      File('${root.path}/lib/main.dart').writeAsStringSync(
        "import 'i18n/generated/message_loader.g.dart';\nvoid main() { print(createMessageResolver(selected: 'en-US').text('save')); }\n",
      );
      final run = await Process.run(
        Platform.resolvedExecutable,
        ['run', 'lib/main.dart'],
        workingDirectory: root.path,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      expect(run.exitCode, 0, reason: '${run.stderr}');
      expect((run.stdout as String).replaceAll('\r\n', '\n'), 'Save\n');
      final analyze = await Process.run(
        Platform.resolvedExecutable,
        ['analyze', '--fatal-infos', '--fatal-warnings'],
        workingDirectory: root.path,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      expect(
        analyze.exitCode,
        0,
        reason: '${analyze.stdout}\n${analyze.stderr}',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test(
    'watch fresh source, 20 edits, syntax failure, recovery, no recursive loop and termination',
    () async {
      final watch = await Process.start(Platform.resolvedExecutable, [
        'tool/i18n.dart',
        'watch',
        '--debounce-ms',
        '40',
      ], workingDirectory: root.path);
      final stdoutLines = <String>[];
      final stderrLines = <String>[];
      final subscriptions = [
        watch.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(stdoutLines.add),
        watch.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(stderrLines.add),
      ];
      Future<void> until(bool Function() condition) async {
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        while (!condition()) {
          if (DateTime.now().isAfter(deadline)) {
            fail('watch timeout: $stdoutLines\n$stderrLines');
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }

      int successes() => stdoutLines
          .where((s) => s.startsWith('Generated successfully'))
          .length;
      final generated = File(
        '${root.path}/lib/i18n/generated/messages_ko.g.dart',
      );
      try {
        await until(() => successes() >= 1);
        await Future<void>.delayed(const Duration(seconds: 4));
        expect(
          successes(),
          1,
          reason: 'staging output must not trigger another generation',
        );
        for (var i = 0; i < 20; i++) {
          catalog.writeAsStringSync(source('수정$i'));
          await Future<void>.delayed(const Duration(milliseconds: 8));
        }
        await until(() => generated.readAsStringSync().contains('수정19'));
        await until(() => successes() >= 2);
        final saved = generated.readAsStringSync();
        catalog.writeAsStringSync('broken Dart {');
        await until(
          () => stderrLines.any((s) => s.contains('Generation failed')),
        );
        expect(generated.readAsStringSync(), saved);
        catalog.writeAsStringSync(source('복구'));
        await until(() => generated.readAsStringSync().contains('복구'));
        await Future<void>.delayed(const Duration(seconds: 4));
        final count = successes();
        generated.writeAsStringSync(generated.readAsStringSync());
        await Future<void>.delayed(const Duration(seconds: 4));
        expect(successes(), count);
      } finally {
        watch.kill(
          Platform.isWindows ? ProcessSignal.sigint : ProcessSignal.sigterm,
        );
        await watch.exitCode.timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            watch.kill(ProcessSignal.sigkill);
            return -1;
          },
        );
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
        catalog.writeAsStringSync(source('저장'));
      }
      expect((await cli(['generate'])).exitCode, 0);
      expect((await cli(['check', '--verify-generated'])).exitCode, 0);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test(
    'SIGTERM during active child leaves no live child and generation recovers',
    () async {
      if (Platform.isWindows) {
        return; // Windows signal behavior is a separate CI boundary.
      }
      final process = await Process.start(Platform.resolvedExecutable, [
        'tool/i18n.dart',
        'watch',
      ], workingDirectory: root.path);
      final started = Completer<void>();
      final out = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (line == 'Generation cycle started.' && !started.isCompleted) {
              started.complete();
            }
          });
      final errors = process.stderr.drain<void>();
      try {
        await started.future.timeout(const Duration(seconds: 20));
        final children = await Process.run('pgrep', ['-P', '${process.pid}']);
        final pids = (children.stdout as String)
            .trim()
            .split(RegExp(r'\s+'))
            .where((s) => int.tryParse(s) != null)
            .toList();
        expect(pids, isNotEmpty);
        process.kill(ProcessSignal.sigterm);
        await process.exitCode.timeout(const Duration(seconds: 10));
        for (final pid in pids) {
          final check = await Process.run('ps', ['-p', pid, '-o', 'stat=']);
          expect(
            (check.stdout as String).trim(),
            isEmpty,
            reason: 'orphan child $pid',
          );
        }
        expect((await cli(['generate'])).exitCode, 0);
        expect((await cli(['check', '--verify-generated'])).exitCode, 0);
      } finally {
        process.kill();
        await out.cancel();
        await errors;
      }
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
