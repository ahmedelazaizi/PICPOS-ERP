import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _roots = <String>[
  'lib/presentation/reports_picpos',
  'lib/presentation/picpos_shell',
  'lib/presentation/screens/stock_movements_screen.dart',
  'lib/presentation/inventory_picpos/widgets/stock_movements_table_picpos.dart',
  'lib/presentation/widgets/searchable_dropdown.dart',
];

final _literal = RegExp(
  r'Colors\.(?:grey|white54|black54|black87)\b|'
  r'AppColors\.(?:textMuted|textSecondary)\b',
);

Iterable<File> _files() sync* {
  for (final root in _roots) {
    final entity = FileSystemEntity.typeSync(root) == FileSystemEntityType.file
        ? File(root)
        : Directory(root);
    if (entity is File) {
      yield entity;
      continue;
    }
    if (entity is Directory && entity.existsSync()) {
      for (final child in entity.listSync(recursive: true)) {
        if (child is File && child.path.endsWith('.dart')) yield child;
      }
    }
  }
}

String _relative(File file) => file.path.replaceAll(r'\', '/');

bool _isTextContext(List<String> lines, int index) {
  final start = index > 5 ? index - 5 : 0;
  final end = index + 4 < lines.length ? index + 4 : lines.length;
  return lines.sublist(start, end).join('\n').contains('TextStyle');
}

void main() {
  test('report text colors use PicPos theme tokens', () {
    final offenders = <String>[];
    for (final file in _files()) {
      final relative = _relative(file);
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!_literal.hasMatch(lines[i]) || !_isTextContext(lines, i)) continue;
        offenders.add('$relative:${i + 1}');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Use context.picposText/Muted/Secondary or a semantic token: $offenders',
    );
  });
}
