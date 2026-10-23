import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

Future<void> watchCatalog({
  required String projectRoot,
  required List<String> sourcePaths,
  required String generatedDirectory,
  required String entrypoint,
  required int debounceMs,
  required void Function(String) output,
  required void Function(String) error,
}) async {
  final subscriptions = <StreamSubscription<Object?>>[];
  final done = Completer<void>();
  Timer? timer;
  Process? active;
  var running = false;
  var pending = false;
  var stopping = false;
  final excluded = [
    generatedDirectory,
    p.join(projectRoot, 'build'),
    p.join(projectRoot, '.dart_tool'),
  ];

  Future<void> cycle() async {
    if (stopping) return;
    if (running) {
      pending = true;
      return;
    }
    running = true;
    try {
      do {
        pending = false;
        final child = await Process.start(Platform.resolvedExecutable, [
          entrypoint,
          '__watch-cycle',
          '--output',
          generatedDirectory,
        ], workingDirectory: projectRoot);
        active = child;
        output('Generation cycle started.');
        if (stopping) child.kill();
        final streams = [
          child.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .forEach(output),
          child.stderr
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .forEach((line) => error(line.replaceAll(projectRoot, '.'))),
        ];
        final code = await child.exitCode;
        await Future.wait(streams);
        active = null;
        if (code == 0) {
          output(
            'Generated successfully. Run Flutter hot reload; use hot restart if locale structure changed.',
          );
        } else if (!stopping) {
          error(
            'Generation failed (exit $code). Last successful output preserved; watching for recovery.',
          );
        }
      } while (pending && !stopping);
    } catch (exception) {
      error('Watch cycle failed: ${exception.runtimeType}');
    } finally {
      running = false;
      if (stopping && !done.isCompleted) done.complete();
    }
  }

  void stop(ProcessSignal signal) {
    stopping = true;
    timer?.cancel();
    active?.kill(ProcessSignal.sigterm);
    if (!running && !done.isCompleted) done.complete();
  }

  try {
    for (final path in sourcePaths) {
      final watcher = DirectoryWatcher(path);
      subscriptions.add(
        watcher.events.listen((event) {
          final changed = p.normalize(p.absolute(event.path));
          // Staging is a sibling of generated/, often inside sourcePaths.
          // Its Dart files are tool output too, never source changes.
          if (p
              .split(changed)
              .any((part) => part.startsWith('.message_i18n_stage_'))) {
            return;
          }
          if (!changed.endsWith('.dart') ||
              excluded.any(
                (root) => changed == root || p.isWithin(root, changed),
              )) {
            return;
          }
          if (running) {
            pending = true;
            return;
          }
          timer?.cancel();
          timer = Timer(
            Duration(milliseconds: debounceMs),
            () => unawaited(cycle()),
          );
        }, onError: (Object e) => error('Watch error: ${e.runtimeType}')),
      );
      await watcher.ready;
    }
    subscriptions.add(ProcessSignal.sigint.watch().listen(stop));
    if (!Platform.isWindows) {
      subscriptions.add(ProcessSignal.sigterm.watch().listen(stop));
    }
    unawaited(cycle());
    await done.future;
  } finally {
    stopping = true;
    timer?.cancel();
    active?.kill();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }
}
