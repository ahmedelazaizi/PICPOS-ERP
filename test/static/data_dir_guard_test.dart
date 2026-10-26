// Guard: persistent locations must go through DataDir (PICPOS_DATA_DIR lab
// isolation). Direct path_provider directory calls anywhere else in lib/ fail.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files allowed to call path_provider directory APIs directly.
const _allow = <String>{
  'lib/core/config/data_dir.dart',
};

final _banned = RegExp(
  r'getApplication(Documents|Support|Cache)Directory|getLibraryDirectory|'
  r'getTemporaryDirectory|getDownloadsDirectory|getExternalStorage',
);

void main() {
  test('no direct path_provider directory calls outside DataDir', () {
    final bad = <String>[];
    for (final e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final rel = e.path.replaceAll('\\', '/');
      if (_allow.contains(rel)) continue;
      final lines = e.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i].trimLeft();
        if (l.startsWith('//')) continue;
        if (_banned.hasMatch(l)) bad.add('$rel:${i + 1}: ${l.trim()}');
      }
    }
    expect(bad, isEmpty,
        reason: 'Use DataDir.documents()/support() (lib/core/config/'
            'data_dir.dart) so PICPOS_DATA_DIR isolation stays complete:\n'
            '${bad.join('\n')}');
  });

  test('the only importers of path_provider are on the allowlist', () {
    final bad = <String>[];
    for (final e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final rel = e.path.replaceAll('\\', '/');
      if (_allow.contains(rel)) continue;
      if (e.readAsStringSync().contains("package:path_provider/")) bad.add(rel);
    }
    expect(bad, isEmpty, reason: bad.join('\n'));
  });
}
