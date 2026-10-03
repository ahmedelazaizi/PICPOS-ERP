// Structural guards for the app's lib/ (port of the desktop
// test/structural/dark_mode_guard_test.dart, stricter because this code is
// new): every colour comes from the theme or picpos_ui tokens, so light and
// dark both work. A deliberate exception needs `// dark-ok: <reason>` on or
// just above the line. Also checks that every `t('key')` used exists in the
// string table.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_admin/l10n/strings.dart';

final _colorLiteral = RegExp(r'\bColors\.(?!transparent\b)\w+|\bColor\(0x|\bColor\.fromA?RGBO?\(');

Iterable<File> _dartFiles(String root) =>
    Directory(root).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

void main() {
  test('no hard-coded colours (Colors.white/black/teal…, Color(0x…)) in lib/', () {
    final offenders = <String>[];
    for (final f in _dartFiles('lib')) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//') || !_colorLiteral.hasMatch(lines[i])) continue;
        final marked = lines[i].contains('dark-ok:') || (i > 0 && lines[i - 1].contains('dark-ok:'));
        if (!marked) offenders.add('${f.path}:${i + 1}: ${lines[i].trim()}');
      }
    }
    expect(offenders, isEmpty, reason: 'Use Theme.of(context).colorScheme or picpos_ui getters:\n${offenders.join('\n')}');
  });

  test('the guard detects literals (self-check)', () {
    for (final bad in ['color: Colors.white,', 'Colors.teal.shade200', 'Color(0xFFFFFFFF)', 'Color.fromARGB(1,2,3,4)']) {
      expect(_colorLiteral.hasMatch(bad), isTrue, reason: bad);
    }
    expect(_colorLiteral.hasMatch('Colors.transparent'), isFalse);
  });

  test("every t('key') used in lib/ exists in the string table", () {
    final used = RegExp(r"""\bt\('(\w+)'""");
    final missing = <String>{};
    for (final f in _dartFiles('lib')) {
      for (final m in used.allMatches(f.readAsStringSync())) {
        if (!S.table.entries.containsKey(m[1])) missing.add('${f.path}: ${m[1]}');
      }
    }
    expect(missing, isEmpty);
  });
}
