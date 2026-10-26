// Gate G-2 (CI side): built release APKs must be PicPos-only and com.picpos.*.
// Paths: PICPOS_APK_PATHS (';' separated) or mobile_*/build/app/outputs/
// flutter-apk/app-release.apk. SKIPPED with an explicit message when none
// exists (PICPOS_REQUIRE_APK=1 turns that into a failure). The signer check
// needs apksigner, so it lives in tool/ci/scan_apk.ps1, not here.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/ci/apk_scan.dart';

void main() {
  final forced = Platform.environment['PICPOS_APK_PATHS'];
  final apks = <String>[
    if (forced != null && forced.isNotEmpty)
      ...forced.split(';').where((s) => s.trim().isNotEmpty)
    else
      for (final m in ['mobile', 'mobile_admin', 'mobile_pos', 'mobile_warehouse'])
        '$m/build/app/outputs/flutter-apk/app-release.apk',
  ].where((p) => File(p).existsSync()).toList();
  final require = Platform.environment['PICPOS_REQUIRE_APK'] == '1';

  test('built APKs carry no forbidden brand and a com.picpos id', () {
    if (apks.isEmpty) {
      expect(require, isFalse,
          reason: 'PICPOS_REQUIRE_APK=1 but no APK was found');
      // ignore: avoid_print
      print('apk guard: SKIPPED - no built APK (set PICPOS_APK_PATHS).');
      return;
    }
    for (final apk in apks) {
      final r = scanApkBytes(apk, File(apk).readAsBytesSync());
      expect(r.problems, isEmpty, reason: apk);
    }
  });
}
