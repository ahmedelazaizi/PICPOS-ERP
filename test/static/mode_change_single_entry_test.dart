// A1 (adoption contract §C.7-6): one entry to commit / change the mode.
//
//  * `NetworkService.setMode(.., db:)` (the DB-writing form) is called only by
//    the committer that `ModeActivator` wraps, by NetworkService itself, and by
//    the LEGACY sites listed below (documented debt: none may be added).
//  * the first-run flow, the developer tools and the network settings never call
//    it - the mode changes through "re-provision this device" only.
//  * `DeploymentModeCommitter(` is constructed only by `ModeActivator`.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _norm(String p) => p.replaceAll('\\', '/');

Iterable<File> _libFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

List<String> _hits(RegExp re, {Set<String> allowed = const {}}) {
  final out = <String>[];
  for (final f in _libFiles()) {
    final path = _norm(f.path);
    if (allowed.contains(path)) continue;
    final lines = f.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final t = lines[i].trimLeft();
      if (t.startsWith('//')) continue;
      if (re.hasMatch(lines[i])) out.add('$path:${i + 1}');
    }
  }
  return out;
}

void main() {
  // receiver.setMode(<NetworkMode value>...) - not themeMode / industryMode.
  final setMode = RegExp(
      r'(\bns|\b_ns|NetworkService\.instance|\bnetworkService)\.setMode\(');

  test('setMode() is called only from the committer / NetworkService / the '
      'listed legacy sites', () {
    const allowed = {
      'lib/services/network_service.dart',
      // ModeActivator's delegate (writes the record in the same transaction)
      'lib/services/deployment/deployment_mode_committer.dart',
      // pre-commit first sync: IN-MEMORY only (no db: argument)
      'lib/services/setup/client_link_service.dart',
      // ── legacy debt (not part of the first-run flow; do NOT add to this list)
      // (main_desktop.dart and database_settings_widget.dart now go through
      //  ModeActivator - they were removed from this list, do not re-add them)
      'lib/data/repositories/sync_repository_impl.dart', // no UI caller left
      'lib/core/config/business_profile_provider.dart', // changeMode: no caller
    };
    expect(_hits(setMode, allowed: allowed), isEmpty,
        reason: 'a new setMode() caller bypasses ModeActivator + the device '
            'record; route through ModeActivator.commit / re-provisioning');
  });

  test('the client link step never writes network_mode to the DB', () {
    final src = File('lib/services/setup/client_link_service.dart')
        .readAsStringSync();
    final calls = RegExp(r'\.setMode\(([^)]*)\)').allMatches(src);
    for (final m in calls) {
      expect(m.group(1), isNot(contains('db')),
          reason: 'the mode is committed only by ModeActivator');
    }
  });

  test('first-run, developer tools and network settings never change the mode '
      'directly', () {
    final roots = [
      'lib/presentation/screens/first_run',
      'lib/presentation/screens/developer_tools_screen.dart',
      'lib/presentation/screens/settings/network_mode_settings.dart',
      'lib/presentation/settings_picpos/screens/network_mode_settings_picpos.dart',
      'lib/presentation/settings_picpos/screens/device_reprovision_tile.dart',
    ];
    for (final r in roots) {
      final files = FileSystemEntity.isDirectorySync(r)
          ? Directory(r).listSync(recursive: true).whereType<File>()
          : [File(r)];
      for (final f in files.where((f) => f.path.endsWith('.dart'))) {
        final s = f.readAsStringSync();
        expect(RegExp(r'\.setMode\(\s*(mode|NetworkMode)').hasMatch(s) ||
            s.contains('DeploymentModeCommitter('), isFalse,
            reason: _norm(f.path));
      }
    }
  });

  test('DeploymentModeCommitter is constructed only by ModeActivator '
      '(and itself)', () {
    expect(
      _hits(RegExp(r'DeploymentModeCommitter\('), allowed: {
        'lib/services/deployment/deployment_mode_committer.dart',
        'lib/services/deployment/mode_activator.dart',
      }),
      isEmpty,
    );
  });
}
