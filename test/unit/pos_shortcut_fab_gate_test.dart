// test/unit/pos_shortcut_fab_gate_test.dart
//
// زرٌّ عائمٌ دائمٌ للعودة إلى «البيع السريع» — طلبُ مالكٍ 2026-08-17.
//
// ── البلاغ ────────────────────────────────────────────────────────────────
// «عند التعامل بحساب الكاشير… يكون فى زر جانبي للتوجيه الى نقطة البيع
// مباشرة بدلا من الاختيار من القائمة». وقرارُ المالك في الموضع: زرٌّ عائمٌ
// دائمٌ يظهر في كلّ الشاشات ما دام المستخدمُ يملك صلاحيةَ نقطة البيع،
// ويعمل في وضع الكاشير حيث تختفي القائمةُ الجانبية.
//
// ── ليه دالّةٌ خالصة لا اختبارُ ودجت ─────────────────────────────────────
// `AppShell` ودجتٌ ضخمةٌ (Riverpod + قاعدةُ بيانات + Scaffold كامل)، فعزلُ
// *قرارِ* الظهور وحده — يملك الصلاحية · ليس داخل شاشة البيع ⇒ أظهِر —
// يجعله قابلاً للاختبار مباشرةً بلا شجرة ودجت هشّة.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/models/pos_shortcut_fab_gate.dart';

void main() {
  group('shouldShowPosShortcutFab', () {
    test('يملك صلاحية pos_access وليس داخل شاشة البيع ⇒ يظهر', () {
      expect(
        shouldShowPosShortcutFab(hasPosAccess: true, isOnPosScreen: false),
        isTrue,
      );
    });

    test('يملك الصلاحية لكنه داخل شاشة البيع نفسها ⇒ لا يظهر (ضجيج)', () {
      expect(
        shouldShowPosShortcutFab(hasPosAccess: true, isOnPosScreen: true),
        isFalse,
      );
    });

    test('لا يملك صلاحية pos_access وليس داخل شاشة البيع ⇒ لا يظهر', () {
      expect(
        shouldShowPosShortcutFab(hasPosAccess: false, isOnPosScreen: false),
        isFalse,
      );
    });

    test('لا يملك الصلاحية وهو داخل شاشة البيع ⇒ لا يظهر', () {
      expect(
        shouldShowPosShortcutFab(hasPosAccess: false, isOnPosScreen: true),
        isFalse,
      );
    });
  });
}
