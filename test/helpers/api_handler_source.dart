import 'dart:io';

/// Source of `ApiHandler`, which is split across several files of one Dart
/// library: `api_handler.dart` (class, fields, `buildRouter`) and the `part`
/// files under `lib/services/api/routes/` (route registration and handlers).
///
/// Source-grep tests that used to read `api_handler.dart` alone read this
/// concatenation instead, so they keep seeing every route and handler body.
String readApiHandlerSource() {
  final parts = Directory('lib/services/api/routes')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .map((f) => f.path)
      .toList()
    ..sort();
  return [
    'lib/services/api/api_handler.dart',
    ...parts,
  ].map((p) => File(p).readAsStringSync()).join('\n');
}