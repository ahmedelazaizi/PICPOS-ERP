import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/config/brand.dart';
import 'package:picpos_erp/core/navigation/screen_registry.dart';
import 'package:picpos_erp/core/navigation/screen_id.dart';
import 'package:picpos_erp/core/config/business_profile.dart';
import 'package:picpos_erp/presentation/scale_plu_picpos/screens/scale_plu_picpos_screen.dart';

void main() {
  testWidgets('ScalePluPicposScreen موجودة وقابلة للإنشاء', (t) async {
    expect(const ScalePluPicposScreen(), isA<Widget>());
  });

  test('litePicpos يضمّ scalePlu بينما lite لا يضمّه، والافتراضي (uralcash) لا يضمّه', () {
    expect(ScreenRegistry.litePicpos, contains(ScreenId.scalePlu));
    expect(ScreenRegistry.lite, isNot(contains(ScreenId.scalePlu)));
    // forProfile selects the brand-specific scope, then applies feature
    // additions (such as quotations), so compare the invariant under test
    // rather than requiring equality with the unmodified base scope.
    final resolved = ScreenRegistry.forProfile(BusinessProfile.lite);
    expect(resolved.contains(ScreenId.scalePlu), Brand.isPicPos);
  });
}
