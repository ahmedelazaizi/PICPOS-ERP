import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/navigation/screen_registry.dart';
import 'package:ural_erp/core/navigation/screen_id.dart';
import 'package:ural_erp/core/config/business_profile.dart';
import 'package:ural_erp/presentation/scale_plu_picpos/screens/scale_plu_picpos_screen.dart';

void main() {
  testWidgets('ScalePluPicposScreen موجودة وقابلة للإنشاء', (t) async {
    expect(const ScalePluPicposScreen(), isA<Widget>());
  });

  test('litePicpos يضمّ scalePlu بينما lite لا يضمّه، والافتراضي (uralcash) لا يضمّه', () {
    expect(ScreenRegistry.litePicpos, contains(ScreenId.scalePlu));
    expect(ScreenRegistry.lite, isNot(contains(ScreenId.scalePlu)));
    // default test brand = uralcash → forProfile(lite) returns the 19-screen lite
    expect(ScreenRegistry.forProfile(BusinessProfile.lite), equals(ScreenRegistry.lite));
    expect(ScreenRegistry.forProfile(BusinessProfile.lite), isNot(contains(ScreenId.scalePlu)));
  });
}
