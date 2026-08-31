// Spec 029 / US1 — Postgres integration test orchestrator.
//
// Usage: `dart run scripts/run_pg_tests.dart`  (or `melos test:pg`)
//
// Boots a `postgres:16-alpine` container via Docker on a free port, waits
// for it to accept connections, sets `PG_TEST_DSN`, runs `flutter test
// test/integration_pg/ --tags pg`, and tears down the container in
// try/finally regardless of test outcome.
//
// Exit codes:
//   0 — tests passed
//   1 — Docker missing OR Postgres failed to start in time
//   N — flutter test exit code (passes through)
//
// Per spec FR-005, missing Docker exits with an actionable message rather
// than silently skipping.

import 'dart:async';
import 'dart:io';

const _imageTag = 'postgres:16-alpine';
const _readyTimeout = Duration(seconds: 30);
const _pollInterval = Duration(milliseconds: 500);

Future<void> main() async {
  final stopwatch = Stopwatch()..start();
  await _ensureDockerAvailable();

  final containerName =
      'ural-pg-test-${DateTime.now().microsecondsSinceEpoch}';
  String? containerId;
  // يُخرَج به بعد `finally` — انظر التعليقَ عند إسناده.
  var exitCodeToReport = 0;

  try {
    print('[PG-RUNNER] Starting $_imageTag as $containerName ...');
    final runResult = await Process.run(
      'docker',
      [
        'run',
        '-d',
        '--rm',
        '--name', containerName,
        '-e', 'POSTGRES_PASSWORD=postgres',
        '-e', 'POSTGRES_USER=postgres',
        '-e', 'POSTGRES_DB=postgres',
        '-p', '0:5432',
        _imageTag,
      ],
    );
    if (runResult.exitCode != 0) {
      stderr.writeln('[PG-RUNNER] docker run failed:');
      stderr.writeln(runResult.stderr);
      exit(1);
    }
    containerId = (runResult.stdout as String).trim();
    print('[PG-RUNNER] Container id: $containerId');

    final hostPort = await _resolveHostPort(containerName);
    print('[PG-RUNNER] Host port: $hostPort');

    await _waitForReady(containerName, hostPort);
    print('[PG-RUNNER] Postgres ready in ${stopwatch.elapsed.inSeconds}s');

    final dsn = 'postgres://postgres:postgres@localhost:$hostPort/postgres';
    final testProcess = await Process.start(
      'flutter',
      [
        'test',
        'test/integration_pg/',
        '--tags', 'pg',
        '--run-skipped', // dart_test.yaml marks `pg` skip by default
        // ⚠️ **متسلسلٌ إلزاماً.** المِرفقُ (`_support/pg_fixture.dart`) يُسقط
        // مخطَّطَ `public` ويعيد إنشاءه عند بدء كلِّ ملفّ، وكلُّ الملفّات
        // تتشارك **قاعدةً واحدة**. فالتوازي يجعل ملفّاً يمحو جداولَ ملفٍّ
        // آخرَ وهو يعمل، والعَرَضُ `42P06: schema "public" already exists`
        // يتبعه `LateInitializationError: 'fx'` في `tearDownAll`.
        //
        // مقيسٌ 2026-08-31: بالتوازي ‏٢١ ✓ / ٣ ✗، وبالتسلسل ‏٤٦ ✓ / ٠ ✗ —
        // على نفس الكود بلا تغييرِ سطرٍ واحد.
        '--concurrency=1',
      ],
      runInShell: true,
      environment: {'PG_TEST_DSN': dsn},
      mode: ProcessStartMode.inheritStdio,
    );
    final testExit = await testProcess.exitCode;
    print(
      '[PG-RUNNER] flutter test exited $testExit in '
      '${stopwatch.elapsed.inSeconds}s',
    );
    // ⚠️ `exit()` هنا كان **يُسرِّب الحاوية**: في Dart يُنهي العمليّةَ فوراً
    // ولا يُشغّل `finally`، فالحاويةُ تبقى تعمل بعد كلّ تشغيلٍ — ناجحاً كان أم
    // فاشلاً. والرمزُ يُخزَّن ليخرج **بعد** التنظيف.
    exitCodeToReport = testExit;
  } finally {
    if (containerId != null) {
      print('[PG-RUNNER] Stopping container $containerName ...');
      await Process.run('docker', ['stop', containerName]);
    }
  }
  exit(exitCodeToReport);
}

Future<void> _ensureDockerAvailable() async {
  try {
    final result = await Process.run(
      'docker',
      ['version', '--format', '{{.Server.Version}}'],
    );
    if (result.exitCode != 0) {
      stderr.writeln(
        '[PG-RUNNER] docker is installed but the daemon is not running. '
        'Start Docker Desktop and retry.',
      );
      exit(1);
    }
  } on ProcessException {
    stderr.writeln(
      '[PG-RUNNER] docker not found — install Docker Desktop or run on CI. '
      'See test/integration_pg/README.md for the runner contract.',
    );
    exit(1);
  }
}

Future<int> _resolveHostPort(String containerName) async {
  final result = await Process.run(
    'docker',
    ['port', containerName, '5432/tcp'],
  );
  if (result.exitCode != 0) {
    stderr.writeln('[PG-RUNNER] docker port failed: ${result.stderr}');
    exit(1);
  }
  final firstLine = (result.stdout as String).split('\n').first.trim();
  final colon = firstLine.lastIndexOf(':');
  if (colon < 0) {
    stderr.writeln('[PG-RUNNER] unexpected docker port output: $firstLine');
    exit(1);
  }
  return int.parse(firstLine.substring(colon + 1));
}

Future<void> _waitForReady(String containerName, int port) async {
  final deadline = DateTime.now().add(_readyTimeout);
  while (DateTime.now().isBefore(deadline)) {
    try {
      final socket = await Socket.connect(
        'localhost',
        port,
        timeout: const Duration(seconds: 2),
      );
      await socket.close();
      // TCP port is open. Postgres may still be initializing internally —
      // confirm with `pg_isready` inside the container.
      final ready = await Process.run(
        'docker',
        ['exec', containerName, 'pg_isready', '-U', 'postgres'],
      );
      if (ready.exitCode == 0) {
        return;
      }
    } catch (_) {
      // Not ready yet.
    }
    await Future<void>.delayed(_pollInterval);
  }
  stderr.writeln(
    '[PG-RUNNER] Postgres did not accept connections within '
    '${_readyTimeout.inSeconds}s on localhost:$port',
  );
  exit(1);
}
