import 'dart:async';
import 'dart:convert';
import 'dart:io';

class Rpc {
  Rpc(this.send);
  final void Function(Map<String, Object?>) send;
  var next = 0;
  final pending = <int, Completer<Map<String, dynamic>>>{};
  void receive(Map<String, dynamic> message) {
    final id = message['id'];
    if (id is int) pending.remove(id)?.complete(message);
  }

  Future<Map<String, dynamic>> call(
    String method,
    Map<String, Object?> params,
  ) async {
    final id = ++next;
    final complete = Completer<Map<String, dynamic>>();
    pending[id] = complete;
    send({'id': id, 'method': method, 'params': params});
    final response = await complete.future.timeout(const Duration(seconds: 90));
    if (response.containsKey('error')) {
      throw StateError('$method: ${response['error']}');
    }
    final rawResult = response['result'];
    final result = rawResult is Map<String, dynamic>
        ? rawResult
        : <String, dynamic>{'value': rawResult};
    if (result['code'] is int && result['code'] != 0) {
      throw StateError('$method: $result');
    }
    return result;
  }
}

Future<void> waitUntil(
  bool Function() ready,
  String description, {
  Duration timeout = const Duration(seconds: 90),
}) async {
  final end = DateTime.now().add(timeout);
  while (!ready()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException(description);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

Future<void> main(List<String> arguments) async {
  if (arguments.isNotEmpty &&
      !(arguments.length == 2 && arguments.first == '--device')) {
    stderr.writeln(
      'Usage: dart run tool/hot_reload_probe.dart [--device <device-id>]',
    );
    exitCode = 64;
    return;
  }
  final device = arguments.isEmpty ? 'macos' : arguments[1];
  if (device.trim().isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/hot_reload_probe.dart [--device <device-id>]',
    );
    exitCode = 64;
    return;
  }
  final root = Directory.current.path;
  final example = '$root/example';
  final source = File('$example/lib/i18n/catalog.dart');
  final page = File('$example/lib/message_page.dart');
  final original = source.readAsStringSync();
  final originalPage = page.readAsStringSync();
  Process? flutter;
  Process? watcher;
  WebSocket? socket;
  final subscriptions = <StreamSubscription<Object?>>[];
  final observations = <String, Object?>{'device': device};
  var watchSuccess = 0;
  try {
    watcher = await Process.start(Platform.resolvedExecutable, [
      'run',
      'build_runner',
      'watch',
    ], workingDirectory: example);
    subscriptions.add(
      watcher.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (line.contains('Built with build_runner')) watchSuccess++;
          }),
    );
    subscriptions.add(
      watcher.stderr
          .transform(utf8.decoder)
          .listen((line) => stderr.write(line)),
    );
    await waitUntil(() => watchSuccess > 0, 'initial generation');
    flutter = await Process.start('flutter', [
      'run',
      '--machine',
      '-d',
      device,
      '-t',
      'integration_test/hot_reload_target.dart',
    ], workingDirectory: example);
    final machine = Rpc(
      (message) => flutter!.stdin.writeln(jsonEncode([message])),
    );
    String? uri;
    String? appId;
    subscriptions.add(
      flutter.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (!line.startsWith('[{')) return;
            final Object? decoded = jsonDecode(line);
            if (decoded is! List<Object?>) return;
            for (final raw in decoded) {
              if (raw is! Map<String, dynamic>) continue;
              machine.receive(raw);
              final params = raw['params'];
              if (params is Map<String, dynamic>) {
                if (raw['event'] == 'app.progress' &&
                    params['message'] is String) {
                  stdout.writeln('Flutter: ${params['message']}');
                }
                if (raw['event'] == 'app.start') {
                  appId = params['appId'] as String?;
                }
                if (raw['event'] == 'app.debugPort') {
                  uri = params['wsUri'] as String?;
                }
                if (raw['event'] == 'app.log' && params['error'] == true) {
                  stderr.writeln(params['log']);
                }
              }
            }
          }),
    );
    subscriptions.add(
      flutter.stderr.transform(utf8.decoder).listen(stderr.write),
    );
    await waitUntil(
      () => uri != null && appId != null,
      'Flutter VM service',
      timeout: const Duration(minutes: 5),
    );
    socket = await WebSocket.connect(uri!);
    final vm = Rpc(
      (message) => socket!.add(jsonEncode({'jsonrpc': '2.0', ...message})),
    );
    subscriptions.add(
      socket.listen((Object? raw) {
        if (raw is String) vm.receive(jsonDecode(raw) as Map<String, dynamic>);
      }),
    );
    Future<String> isolate() async {
      final data = await vm.call('getVM', {});
      final entries = data['isolates'] as List<dynamic>;
      return (entries.first as Map<String, dynamic>)['id'] as String;
    }

    var isolateId = await isolate();
    Future<Map<String, dynamic>> snapshot() =>
        vm.call('ext.message_i18n.snapshot', {'isolateId': isolateId});
    await Future<void>.delayed(const Duration(seconds: 2));
    final initial = await snapshot();
    if (initial['save'] != '저장') {
      throw StateError('Initial mounted Text: $initial');
    }
    observations['initial'] = initial;
    source.writeAsStringSync(original.replaceFirst("'저장'", "'저장 hot reload'"));
    var previous = watchSuccess;
    await waitUntil(
      () => watchSuccess > previous,
      'translated source generation',
    );
    await waitUntil(
      () => File(
        '$example/lib/i18n/catalog.message_i18n.g.dart',
      ).readAsStringSync().contains('저장 hot reload'),
      'expected generated translation',
    );
    await machine.call('app.restart', {
      'appId': appId,
      'fullRestart': false,
      'pause': false,
      'reason': 'message_i18n probe',
    });
    await Future<void>.delayed(const Duration(seconds: 2));
    final reloaded = await snapshot();
    if (reloaded['save'] != '저장 hot reload' ||
        reloaded['identity'] != initial['identity']) {
      throw StateError('Reload failed: $reloaded');
    }
    observations['hotReload'] = reloaded;
    stdout.writeln(
      'PASS: mounted Text changed after watch + hot reload; resolver identity preserved.',
    );
    await vm.call('ext.message_i18n.select', {
      'isolateId': isolateId,
      'locale': 'en',
    });
    final withKey = source.readAsStringSync().replaceFirst(
      'messages: {',
      "messages: {\n    'hot.added': LocalizedMessage({'ko':'추가','en':'Added','ja':'追加'}),",
    );
    source.writeAsStringSync(withKey.replaceFirst("'Save'", "'Save reloaded'"));
    page.writeAsStringSync(
      originalPage.replaceFirst(
        'children: [',
        "children: [\n          Text(context.tr('hot.added')),",
      ),
    );
    previous = watchSuccess;
    await waitUntil(() => watchSuccess > previous, 'new key generation');
    await machine.call('app.restart', {
      'appId': appId,
      'fullRestart': false,
      'pause': false,
      'reason': 'new key probe',
    });
    await Future<void>.delayed(const Duration(seconds: 2));
    final newKey = await snapshot();
    if (newKey['save'] != 'Save reloaded' ||
        newKey['selected'] != 'en' ||
        !(newKey['texts'] as List<dynamic>).contains('Added') ||
        newKey['identity'] != initial['identity']) {
      throw StateError('New key reload failed: $newKey');
    }
    observations['newKeyAndSelection'] = newKey;
    stdout.writeln(
      'PASS: new key and usage hot reload; selected locale and resolver preserved.',
    );
    var expanded = source.readAsStringSync().replaceFirst(
      "['ko', 'en', 'ja']",
      "['ko', 'en', 'ja', 'fr']",
    );
    // Clone the existing Japanese value, preserving placeholder parity.
    expanded = expanded.replaceAllMapped(
      RegExp(r"'ja':\s*('[^']*')"),
      (m) => "'ja': ${m[1]}, 'fr': ${m[1]}",
    );
    source.writeAsStringSync(expanded);
    previous = watchSuccess;
    await waitUntil(
      () => watchSuccess > previous,
      'locale structure generation',
    );
    await machine.call('app.restart', {
      'appId': appId,
      'fullRestart': true,
      'pause': false,
      'reason': 'locale structure probe',
    });
    await Future<void>.delayed(const Duration(seconds: 2));
    isolateId = await isolate();
    final restarted = await snapshot();
    if (!(restarted['supported'] as List<dynamic>).contains('fr')) {
      throw StateError('Restart metadata failed: $restarted');
    }
    observations['hotRestart'] = restarted;
    stdout.writeln(
      'PASS: supported locale structure visible after hot restart.',
    );
    await machine.call('app.stop', {'appId': appId});
  } finally {
    await socket?.close();
    watcher?.kill(ProcessSignal.sigterm);
    flutter?.kill(ProcessSignal.sigterm);
    for (final process in [watcher, flutter]) {
      if (process != null) {
        await process.exitCode.timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            process.kill(ProcessSignal.sigkill);
            return -1;
          },
        );
      }
    }
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    source.writeAsStringSync(original);
    page.writeAsStringSync(originalPage);
    final restored = await Process.run(Platform.resolvedExecutable, [
      'run',
      'build_runner',
      'build',
    ], workingDirectory: example);
    if (restored.exitCode != 0) {
      throw StateError('Restore generation failed: ${restored.stderr}');
    }
    final safeDevice = device.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final outputName = device == 'macos'
        ? 'hot_reload.json'
        : 'hot_reload_$safeDevice.json';
    final output = File('$root/build/verification/$outputName')
      ..parent.createSync(recursive: true);
    output.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(observations)}\n',
    );
  }
}
