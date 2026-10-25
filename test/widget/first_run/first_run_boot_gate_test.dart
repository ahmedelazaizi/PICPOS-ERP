// Boot gate (A1): the provisioning gate wraps `MaterialApp.home` BEFORE the login.
// The behavioural tests are in provisioning_gate_before_login_test.dart; this file
// guards the wiring in main.dart and the first-run sources.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('main.dart: ProvisioningGate wraps the login/app choice; no old gate, '
      'no legacy wizard', () {
    final src = File('lib/main.dart').readAsStringSync();
    expect(src, contains('ProvisioningGate('));
    expect(src.contains('_SetupGate'), isFalse);
    expect(src.contains('SetupWizardScreen'), isFalse);
    // setup runs BEFORE the login: the gate is the root, the login is its child
    expect(
      RegExp(r'ProvisioningGate\(\s*child:\s*isAuthenticated\s*\?\s*const MainScreen\(\)\s*:\s*const LoginScreen\(\)')
          .hasMatch(src),
      isTrue,
    );
  });

    test('المعالج الجديد لا يفتح المعالج القديم لأي مسار (مقر/فرع/مرآة)', () {
    for (final f in Directory('lib/presentation/screens/first_run')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final s = f.readAsStringSync();
      expect(s.contains('SetupWizardScreen'), isFalse, reason: f.path);
      expect(s.contains('setup_wizard_screen.dart'), isFalse, reason: f.path);
      expect(s.contains('_legacy'), isFalse, reason: f.path);
    }
  });

  test('ملفات المعالج الجديد بلا أي ذكر لعلامة أخرى', () {
    for (final root in ['lib/presentation/screens/first_run', 'lib/services/setup', 'lib/domain/models/first_run']) {
      for (final f in Directory(root).listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final s = f.readAsStringSync().toLowerCase();
        expect(s.contains('uralcash'), isFalse, reason: f.path);
        expect(s.contains('ural-erp'), isFalse, reason: f.path);
        expect(f.lengthSync(), lessThan(30720), reason: f.path);
      }
    }
  });
}
