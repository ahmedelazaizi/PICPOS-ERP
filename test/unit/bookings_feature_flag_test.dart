import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/config/feature_dependency_graph.dart';
import 'package:ural_erp/core/config/feature_key.dart';
import 'package:ural_erp/core/config/feature_policy.dart';

void main() {
  test('الحجوزاتُ لا تُجبر على وحدة الطاولات', () {
    // صالونٌ أو عيادةٌ لا طاولاتِ فيها. وبقاءُ التبعيّة يعني أنّ فتحَ
    // الحجوزات على PicPos-lite يُشغّل وحدةَ الطاولات قسراً على كلّ تنصيب.
    expect(
      FeatureDependencyGraph.requires[FeatureKey.posReservations],
      anyOf(isNull, isEmpty),
    );
  });

  test('litePicpos تفتح الحجوزات و lite لا تُمَسّ', () {
    expect(FeaturePolicy.litePicpos.reservationsEnabled, isTrue);
    // UralCash-lite مطروحةٌ وقد تكون منصَّبةً عند عميل.
    expect(FeaturePolicy.lite.reservationsEnabled, isFalse);
    // ولا تُفتح الطاولاتُ تبعاً لذلك.
    expect(FeaturePolicy.litePicpos.tablesEnabled, isFalse);
  });
}
