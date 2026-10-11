import 'dart:io';

/// Source of `ApiDataHandler`, which is split across several files of one
/// Dart library: `api_data_handler.dart` (class + FK helpers) and the
/// `part` files under `lib/services/api/data/` (route extensions).
///
/// Source-grep tests that used to read `api_data_handler.dart` alone read
/// this concatenation instead, so they keep seeing every handler body.
String readApiDataHandlerSource() {
  final parts = Directory('lib/services/api/data')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .map((f) => f.path)
      .toList()
    ..sort();
  return [
    'lib/services/api/api_data_handler.dart',
    ...parts,
  ].map((p) => File(p).readAsStringSync()).join('\n');
}