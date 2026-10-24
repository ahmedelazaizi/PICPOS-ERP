// Contract guard for the distribution findings REL-002 / REL-003 / REL-004.
//
// A text-level guard: it fails when someone re-introduces a debug-key fallback
// in an Android app, drops the installer's mandatory pre-upgrade backup, or
// removes the CI signing gates. It does not build anything.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  const apps = ['mobile', 'mobile_pos', 'mobile_admin'];

  group('REL-004 Android release signing is fail-closed in all apps', () {
    for (final app in apps) {
      final gradle = _read('$app/android/app/build.gradle.kts');

      test('$app: validateReleaseSigning is wired to the release tasks', () {
        expect(gradle, contains('validateReleaseSigning'));
        expect(gradle, contains('check(hasUploadKey)'));
        expect(gradle, contains('name.startsWith("assemble")'));
        expect(gradle, contains('name.startsWith("bundle")'));
      });

      test('$app: never signs release with the debug key', () {
        expect(gradle.contains('getByName("debug")'), isFalse,
            reason: 'debug signing fallback re-introduced in $app');
        expect(gradle, contains('keystoreProperties.getProperty("storeFile")'));
      });

      test('$app: key.properties is git-ignored and a secret-free template exists',
          () {
        final example = _read('$app/android/key.properties.example');
        expect(example, contains('storePassword=<'));
        expect(example, contains('keyPassword=<'));
        expect(example, isNot(matches(RegExp(r'Password=(?!<)\S'))),
            reason: 'the template must not contain real passwords');
      });
    }

    for (final app in apps) {
      test('$app: release/profile Android config is HTTPS-only (SEC-007)', () {
        final main = _read('$app/android/app/src/main/AndroidManifest.xml');
        expect(main, contains('android:usesCleartextTraffic="false"'));
        expect(main, contains('@xml/network_security_config'));
        final nsc = _read('$app/android/app/src/main/res/xml/network_security_config.xml');
        expect(nsc, contains('<base-config cleartextTrafficPermitted="false" />'));
        expect(nsc.contains('cleartextTrafficPermitted="true"'), isFalse);
        // cleartext may exist only in the debug source set
        final profile = File('$app/android/app/src/profile/AndroidManifest.xml');
        expect(profile.readAsStringSync().contains('usesCleartextTraffic="true"'), isFalse);
      });
    }

    test('root .gitignore covers keystores, key.properties and pfx files', () {
      final ignore = _read('.gitignore');
      for (final pattern in ['*.jks', '*.keystore', 'key.properties', '*.pfx']) {
        expect(RegExp('^${RegExp.escape(pattern)}\$', multiLine: true)
            .hasMatch(ignore), isTrue, reason: '$pattern missing in .gitignore');
      }
    });

    test('keystore generator refuses to write inside the repo', () {
      final script = _read('tool/gen_android_keystore.ps1');
      expect(script, contains('Refusing to write keystores inside the repository'));
      expect(script, contains("[string]\$OutDir = 'D:\\keys'"));
      expect(script, contains('key.properties.example'));
    });
  });

  group('REL-002 Windows signing', () {
    test('self-signed generator is clearly labelled and stays out of the repo',
        () {
      final script = _read('tool/gen_selfsigned_codesign.ps1');
      expect(script, contains('INTERNAL TESTING ONLY'));
      expect(script, contains('SELF-SIGNED TEST'));
      expect(script, contains('Refusing to write key material inside the repository'));
    });

    test('CI fails release tags without a signing identity unless ALLOW_UNSIGNED',
        () {
      final ci = _read('.github/workflows/ci.yml');
      expect(ci, contains('allow_unsigned'));
      expect(ci, contains("ALLOW_UNSIGNED: \${{ inputs.allow_unsigned"));
      expect(ci, contains('PICPOS_SIGN_PFX_BASE64'));
      expect(ci, contains('PICPOS_SIGN_THUMBPRINT'));
      expect(ci, contains('Release tag without a code-signing identity'));
    });

    test('CI Android job proves fail-closed and rejects debug-signed APKs', () {
      final ci = _read('.github/workflows/ci.yml');
      expect(ci, contains('android-release:'));
      expect(ci, contains('Fail-closed proof'));
      expect(ci, contains('Android Debug'));
      expect(ci, contains('ANDROID_KEYSTORE_BASE64'));
      expect(ci, contains('needs: [build-windows, android-release]'));
    });

    test('CI builds PicPos only and runs the structural guards + brand scan', () {
      final ci = _read('.github/workflows/ci.yml');
      expect(ci, contains('build_picpos.bat'));
      expect(ci, isNot(contains('build_release.bat')));
      expect(ci, contains('APP_BRAND=picpos'));
      expect(ci, contains('brand_artifact_guard_test.dart'));
      expect(ci, contains('flutter test test/structural test/static'));
      expect(ci, contains('flutter analyze lib/'));
      expect(Directory('.github/workflows').listSync().whereType<File>()
          .where((f) => f.path.endsWith('.yml') || f.path.endsWith('.yaml'))
          .length, 1, reason: 'a second workflow must be reviewed for brand scope');
    });

    test('RELEASE=1 installer build fails without an identity', () {
      final bat = _read('build_installer_picpos.bat');
      expect(bat, contains('"%RELEASE%"=="1"'));
      expect(bat, contains('ALLOW_UNSIGNED'));
    });
  });

  group('REL-003 installer takes a mandatory pre-upgrade database backup', () {
    final include = _read('installer/preupgrade_backup.isi');

    test('the include aborts on failure and keeps copies outside the rotation',
        () {
      expect(include, contains('function PreUpgradeBackup(): String;'));
      expect(include, contains(r"\backups\pre-upgrade"));
      expect(include, contains('FileCopy(Src, Dst, False)'));
      expect(include, contains('FileSize64'));
      expect(include, contains('picpos_*.db'));
      expect(include, contains('The upgrade was stopped and nothing was changed.'));
    });

    for (final iss in ['installer/setup_picpos.iss', 'installer/setup.iss']) {
      test('$iss runs it from PrepareToInstall', () {
        final text = _read(iss);
        expect(text, contains('#include "preupgrade_backup.isi"'));
        expect(text, contains('function PrepareToInstall(var NeedsRestart: Boolean): String;'));
        expect(text, contains('Result := PreUpgradeBackup();'));
      });
    }
  });
}
