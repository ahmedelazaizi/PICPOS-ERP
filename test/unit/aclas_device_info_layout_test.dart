// F-PLU-2 (HIGH-2, R1) — TASSDKDeviceInfo is documented as 256 bytes packed,
// but without @Packed(1) Dart FFI uses natural alignment: the Uint64
// `printerDot` forces 8-byte alignment, padding the struct to 264 bytes. Every
// field after the padding (pluStorage, hotKeyCount, ...) is then read from the
// wrong offset. This asserts the layout matches the documented 256-byte size.
//
// NEEDS ON-DEVICE CONFIRMATION against the Aclas SDK header (#pragma pack) /
// real hardware (R1): if the native struct were naturally aligned, @Packed
// would be wrong. The comment + exact 256-byte packed sum are strong evidence
// for pack(1), and this test locks that layout.

import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/aclas_sdk_ffi.dart';

void main() {
  test('TASSDKDeviceInfo packs to the documented 256 bytes (F-PLU-2)', () {
    expect(sizeOf<TASSDKDeviceInfo>(), 256);
  });
}
