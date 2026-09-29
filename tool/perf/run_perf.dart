import 'dart:io';

Future<void> main(List<String> args) async {
  final full = args.contains('--full');
  final flutter = Platform.environment['FLUTTER_BIN'] ??
      r'D:\Cash\develop\flutter\bin\flutter.bat';
  final environment = Map<String, String>.from(Platform.environment)
    ..['PERF_PROFILE'] = full ? 'full' : 'smoke';
  final process = await Process.start(
    flutter,
    ['test', '--tags', 'perf', 'test/perf/erp_load_bench_test.dart'],
    environment: environment,
    mode: ProcessStartMode.inheritStdio,
  );
  exitCode = await process.exitCode;
}
