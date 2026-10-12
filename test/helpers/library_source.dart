import 'dart:io';

/// Source of one Dart library that is split across `part` files.
///
/// Returns the main file followed by every file it lists in a `part '...';`
/// directive (resolved relative to the main file, in directive order), joined
/// by a newline. Source-grep tests that used to read the monolithic file read
/// this concatenation instead, so they keep seeing every member body.
String readLibrarySource(String mainPath) {
  final main = File(mainPath);
  final dir = main.parent.path;
  final text = main.readAsStringSync();
  final parts = RegExp(r'''^part\s+['"]([^'"]+)['"]\s*;''', multiLine: true)
      .allMatches(text)
      .map((m) => '$dir/${m.group(1)}');
  return [text, ...parts.map((p) => File(p).readAsStringSync())].join('\n');
}
