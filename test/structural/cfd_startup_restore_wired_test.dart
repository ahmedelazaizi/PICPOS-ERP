// INT-09 — the desktop start-up restores the saved CFD settings.
//
// Structural (the desktop `initPlatform` drives window_manager and cannot run
// in a unit test): the call must be a real statement in `main_desktop.dart`,
// not a mention in a comment. Behaviour is measured in
// test/unit/cfd_startup_restore_test.dart.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('main_desktop.dart calls CfdService.instance.restoreAtStartup()', () {
    final lines = File('lib/main_desktop.dart').readAsLinesSync();
    final called = lines.any((l) {
      final t = l.trimLeft();
      return !t.startsWith('//') &&
          l.contains('CfdService.instance.restoreAtStartup(');
    });
    expect(called, isTrue,
        reason: 'without it the saved CFD display config is not in force '
            'after a restart until someone opens the settings screen');
  });
}
