// test/unit/app_close_cart_gate_test.dart
//
// إغلاقُ البرنامج والسلّةُ عامرة — طلبُ مالكٍ 2026-08-17.
//
// ── البلاغ ────────────────────────────────────────────────────────────────
// «عند وجود اصناف بالسلة وعمل اغلاق، السيستم يقدر يعمل اغلاق وهذا خطأ — لا
// بد ان يطلب حذف الاصناف من السلة قبل الاغلاق.»
//
// ── ليه دالّةٌ خالصة لا اختبارُ ودجت ─────────────────────────────────────
// `onWindowClose` يحتاج `windowManager` (لا يُبنى في اختبارات الوحدة)،
// ومخارجُ الإغلاق الأخرى تحتاج `BuildContext`/`Ref`. القرارُ نفسُه — امنع
// أم لا — مُستخرَجٌ هنا بلا أيٍّ منها، فهو قابلٌ للاختبار مباشرةً.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/app_close_cart_gate.dart';

void main() {
  group('shouldBlockAppCloseForCart', () {
    test('سلّةٌ فارغةٌ (صفر أصناف) ⇒ لا مانع من الإغلاق', () {
      expect(shouldBlockAppCloseForCart(0), isFalse);
    });

    test('صنفٌ واحدٌ في السلّة ⇒ امنع الإغلاق', () {
      expect(shouldBlockAppCloseForCart(1), isTrue);
    });

    test('عدّة أصنافٍ في السلّة ⇒ امنع الإغلاق', () {
      expect(shouldBlockAppCloseForCart(7), isTrue);
    });
  });
}
