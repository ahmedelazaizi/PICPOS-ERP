import 'dart:io';

void main() async {
  print('Running flutter test test/integration...');
  final result = await Process.run(
    'flutter.bat', 
    ['test', 'test/integration', '--machine'],
  );
  
  final outLines = result.stdout.toString().split('\n');
  final errLines = result.stderr.toString().split('\n');
  
  final file = File('test_parsed.log');
  final sink = file.openWrite();
  sink.writeln('=== STDOUT ===');
  for (final l in outLines) {
    if (l.contains('"error"') || l.contains('"failure"')) {
      sink.writeln(l);
    }
  }
  sink.writeln('=== STDERR ===');
  for (final l in errLines) {
    sink.writeln(l);
  }
  await sink.close();
  print('Done. Check test_parsed.log');
}
