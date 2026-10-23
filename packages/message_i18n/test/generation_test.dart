import 'dart:convert';
import 'dart:io';
import 'package:message_i18n/message_i18n.dart';
import 'package:message_i18n/src/tool/generation.dart';
import 'package:test/test.dart';

MessageCatalog fixture({bool japanese = true, String value = '저장'}) =>
    MessageCatalog(
      defaultLocale: 'ko',
      supportedLocales: ['ko', 'en', if (japanese) 'ja'],
      messages: {
        'save': LocalizedMessage({
          'ko': value,
          'en': 'Save',
          if (japanese) 'ja': '保存',
        }),
      },
    );
void main() {
  late Directory root;
  late Directory target;
  setUp(() {
    root = Directory(
      Directory.systemTemp
          .createTempSync('generation_')
          .resolveSymbolicLinksSync(),
    );
    target = Directory('${root.path}/공백 generated');
  });
  tearDown(() => root.deleteSync(recursive: true));
  test('invalid source and unowned collisions preserve target', () async {
    await generateCatalog(fixture(), target);
    final before = directorySnapshot(target);
    await expectLater(
      generateCatalog(fixture(value: ''), target),
      throwsFormatException,
    );
    expect(directorySnapshot(target), before);
    File('${target.path}/message_i18n_manifest.json').deleteSync();
    final noManifest = directorySnapshot(target);
    await expectLater(
      generateCatalog(fixture(), target),
      throwsA(isA<FileSystemException>()),
    );
    expect(directorySnapshot(target), noManifest);
  });
  test(
    'path traversal, absolute paths, linked directory and false ownership fail closed',
    () async {
      await generateCatalog(fixture(), target);
      final manifest = File('${target.path}/$manifestName');
      final saved = manifest.readAsStringSync();
      final Object? data = jsonDecode(saved);
      final original = Map<String, Object?>.from(data! as Map);
      for (final path in [
        '../outside.dart',
        '/tmp/outside.dart',
        'nested/name.g.dart',
        'user.txt',
      ]) {
        manifest.writeAsStringSync(
          jsonEncode({
            ...original,
            'ownedFiles': [path],
          }),
        );
        final before = directorySnapshot(target);
        await expectLater(
          generateCatalog(fixture(), target),
          throwsFormatException,
        );
        expect(directorySnapshot(target), before);
      }
      manifest.writeAsStringSync(saved);
      File(
        '${target.path}/messages_en.g.dart',
      ).writeAsStringSync('user content');
      await expectLater(
        generateCatalog(fixture(), target),
        throwsFormatException,
      );
      if (!Platform.isWindows) {
        final link = Link('${root.path}/linked')..createSync(target.path);
        await expectLater(
          generateCatalog(fixture(), Directory(link.path)),
          throwsA(isA<FileSystemException>()),
        );
      }
    },
  );
  test('commit exception rolls back all touched owned files', () async {
    await generateCatalog(fixture(), target);
    File('${target.path}/notes.txt').writeAsStringSync('user bytes');
    final before = directorySnapshot(target);
    await expectLater(
      generateCatalog(
        fixture(value: '변경'),
        target,
        afterWrite: (_) => throw StateError('injected'),
      ),
      throwsStateError,
    );
    expect(directorySnapshot(target), before);
    expect(
      root.listSync().where((f) => f.path.contains('.message_i18n_stage_')),
      isEmpty,
    );
    await generateCatalog(fixture(value: '복구'), target);
    expect(File('${target.path}/notes.txt').readAsStringSync(), 'user bytes');
  });
  test('staging race preserves new user bytes; no owned commit', () async {
    await generateCatalog(fixture(), target);
    final before = File('${target.path}/messages_ko.g.dart').readAsStringSync();
    await expectLater(
      generateCatalog(
        fixture(value: 'change'),
        target,
        beforeCommit: (_) async {
          File(
            '${target.path}/user.txt',
          ).writeAsStringSync('edited during staging');
        },
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(
      File('${target.path}/messages_ko.g.dart').readAsStringSync(),
      before,
    );
    expect(
      File('${target.path}/user.txt').readAsStringSync(),
      'edited during staging',
    );
  });
  test(
    'deterministic output, read-only check and stale removal preserve user files',
    () async {
      await generateCatalog(fixture(), target);
      Directory('${target.path}/notes').createSync();
      File('${target.path}/notes/user.txt').writeAsStringSync('preserve');
      final before = directorySnapshot(target);
      final second = await generateCatalog(fixture(), target);
      expect(second.changed, 0);
      expect(second.created, 0);
      expect(directorySnapshot(target), before);
      await generateCatalog(fixture(), target, verifyOnly: true);
      await expectLater(
        generateCatalog(fixture(value: 'new'), target, verifyOnly: true),
        throwsFormatException,
      );
      expect(directorySnapshot(target), before);
      await generateCatalog(fixture(japanese: false), target);
      expect(File('${target.path}/messages_ja.g.dart').existsSync(), isFalse);
      expect(
        File('${target.path}/notes/user.txt').readAsStringSync(),
        'preserve',
      );
    },
  );
  test(
    'generated output is Dart runnable with literal escapes and no catalog import',
    () async {
      final special =
          'quote " slash \\ dollar \$ new\ncarriage\rtab\t 🌍 {name}';
      await generateCatalog(
        fixture(value: special.replaceAll('{name}', 'name')),
        target,
      );
      File('${root.path}/main.dart').writeAsStringSync(
        "import '공백 generated/messages_ko.g.dart';\nvoid main() { print(loadKoMessages()['save']); }\n",
      );
      final run = await Process.run(Platform.resolvedExecutable, [
        '${root.path}/main.dart',
      ]);
      expect(run.exitCode, 0, reason: '${run.stderr}');
      expect(run.stdout, '${special.replaceAll('{name}', 'name')}\n');
      final loader = File(
        '${target.path}/message_loader.g.dart',
      ).readAsStringSync();
      expect(loader, isNot(contains('catalog.dart')));
      expect(loader, isNot(contains('Map<String, Map')));
    },
  );
  test(
    'formatter failure and concurrent generation preserve output and release guard',
    () async {
      await generateCatalog(fixture(), target);
      final before = directorySnapshot(target);
      await expectLater(
        generateCatalog(
          fixture(),
          target,
          beforeFormat: (stage) async {
            File(
              '${stage.path}/messages_ko.g.dart',
            ).writeAsStringSync('broken Dart {');
          },
        ),
        throwsFormatException,
      );
      expect(directorySnapshot(target), before);
      await generateCatalog(
        fixture(),
        target,
        beforeCommit: (_) async {
          await expectLater(
            generateCatalog(fixture(value: 'competing'), target),
            throwsA(isA<FileSystemException>()),
          );
        },
      );
      expect(directorySnapshot(target), before);
      await generateCatalog(fixture(value: 'after lock'), target);
    },
  );
  test('golden emission is stable and map ordering independent', () {
    final output = emitCatalog(fixture());
    expect(
      output['messages_ko.g.dart'],
      '$generatedMarker\nMap<String, String> loadKoMessages() => <String, String>{\n  "save": "저장",\n};\n',
    );
    final reordered = MessageCatalog(
      defaultLocale: 'ko',
      supportedLocales: ['ko', 'en', 'ja'],
      messages: {
        'save': const LocalizedMessage({'ja': '保存', 'en': 'Save', 'ko': '저장'}),
      },
    );
    expect(emitCatalog(reordered), output);
  });
}
