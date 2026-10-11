// E-02 المرحلة أ: LegacyDeviceSeed — نقلٌ حرفيٌّ لاشتقاق SecurityService.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/services/legacy_device_seed.dart';

void main() {
  tearDown(() {
    // لا نلمس المزوّد الافتراضي إلا عبر الاختبار نفسه.
  });

  test("ذهبي: deviceId='ABC' ⇒ sha256('ABC:UralCash_Security_Pepper_v2')", () {
    final expected =
        sha256.convert(utf8.encode('ABC:UralCash_Security_Pepper_v2')).toString();
    expect(LegacyDeviceSeed.deriveFor('ABC'), expected);
    expect(expected.length, 64);
  });

  test('derive() يستعمل مزوّد المعرّف؛ null/فارغ/استثناء ⇒ null بلا توليد', () async {
    final original = LegacyDeviceSeed.deviceIdProvider;
    addTearDown(() => LegacyDeviceSeed.deviceIdProvider = original);

    LegacyDeviceSeed.deviceIdProvider = () async => 'ABC';
    expect(await LegacyDeviceSeed.derive(), LegacyDeviceSeed.deriveFor('ABC'));

    LegacyDeviceSeed.deviceIdProvider = () async => null;
    expect(await LegacyDeviceSeed.derive(), isNull);
    LegacyDeviceSeed.deviceIdProvider = () async => '';
    expect(await LegacyDeviceSeed.derive(), isNull);
    LegacyDeviceSeed.deviceIdProvider = () async => throw StateError('plugin');
    expect(await LegacyDeviceSeed.derive(), isNull);
  });
}
