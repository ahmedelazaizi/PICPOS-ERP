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
import 'package:picpos_erp/domain/models/app_close_cart_gate.dart';

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

  group('shouldBlockNavigationAwayFromPos (قرار 2026-10-30)', () {
    test('شريط مخفي + بيع نشط + سلة ممتلئة ⇒ منع', () {
      expect(
        shouldBlockNavigationAwayFromPos(
          tabsBarVisible: false,
          activeIsPos: true,
          saleCartItemCount: 2,
        ),
        isTrue,
      );
    });

    test('شريط مخفي + سلة فارغة ⇒ مسموح', () {
      expect(
        shouldBlockNavigationAwayFromPos(
          tabsBarVisible: false,
          activeIsPos: true,
          saleCartItemCount: 0,
        ),
        isFalse,
      );
    });

    test('شريط ظاهر + سلة ممتلئة ⇒ مسموح (السلوك القائم)', () {
      expect(
        shouldBlockNavigationAwayFromPos(
          tabsBarVisible: true,
          activeIsPos: true,
          saleCartItemCount: 5,
        ),
        isFalse,
      );
    });

    test('شريط مخفي + التاب النشط ليس البيع ⇒ مسموح', () {
      expect(
        shouldBlockNavigationAwayFromPos(
          tabsBarVisible: false,
          activeIsPos: false,
          saleCartItemCount: 5,
        ),
        isFalse,
      );
    });
  });

  group('shouldBlockLogoutForCart', () {
    test('سلة فارغة ⇒ الخروج مسموح', () {
      expect(shouldBlockLogoutForCart(0), isFalse);
    });

    test('سلة ممتلئة ⇒ الخروج ممنوع', () {
      expect(shouldBlockLogoutForCart(3), isTrue);
    });
  });
}
