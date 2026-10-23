// F-PLU-3 (MED-3, R1) — ExecTaskA is ANSI, so a UTF-8 temp path with non-ASCII
// characters (Arabic Windows username in %TEMP%) can't be opened and PLU
// upload/verify silently fails. The staging logic keys off isAsciiPath.
//
// This verifies the detection; the copy-into-ASCII-dir + actual ExecTaskA
// behaviour NEEDS ON-DEVICE VERIFICATION on an Arabic-Windows install (R1).

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/aclas_sdk_ffi.dart';

void main() {
  test('isAsciiPath flags Arabic-username temp paths (F-PLU-3)', () {
    expect(AclasSDK.isAsciiPath(r'C:\Users\ahmed\AppData\Local\Temp\plu.csv'),
        isTrue);
    expect(AclasSDK.isAsciiPath(r'C:\ProgramData\UralCash\scale_tmp\plu.tmp'),
        isTrue);
    // Arabic username → non-ASCII → must be staged before ExecTaskA.
    expect(
        AclasSDK.isAsciiPath('C:\\Users\\أحمد\\AppData\\Local\\Temp\\plu.csv'),
        isFalse);
  });
}
