// P2 (2026-10-18) — محلِّل «الشاشة الافتراضية» عند الدخول.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/navigation/default_screen_resolver.dart';
import 'package:picpos_erp/core/navigation/screen_id.dart';

void main() {
  const allowed = [0, 1, 3, 4, 8, 17, 61];

  group('parseStoredScreen', () {
    test('ScreenId.name', () {
      expect(parseStoredScreen('salesInvoices'), 17);
      expect(parseStoredScreen('bookings'), 61);
    });

    test('المفاتيحُ القديمة الخمسة = أسماءُ ScreenId بنفس الفهارس', () {
      const legacy = {
        'pos': 1,
        'dashboard': 0,
        'tables': 3,
        'products': 4,
        'inventory': 8,
      };
      legacy.forEach((k, v) {
        expect(parseStoredScreen(k), v, reason: k);
        expect(ScreenId.values.byName(k).navigationIndex, v, reason: k);
      });
    });

    test('فهرسٌ رقمي', () {
      expect(parseStoredScreen('0'), 0);
      expect(parseStoredScreen(' 12 '), 12);
    });

    test('null/فارغ/غيرُ مفهوم ⇒ null', () {
      expect(parseStoredScreen(null), isNull);
      expect(parseStoredScreen(''), isNull);
      expect(parseStoredScreen('nonsense'), isNull);
    });
  });

  group('resolveDefaultScreenIndex', () {
    test('قيمةٌ مسموحة تُطبَّق', () {
      expect(resolveDefaultScreenIndex('salesInvoices', allowed), 17);
      expect(resolveDefaultScreenIndex('tables', allowed), 3);
      expect(resolveDefaultScreenIndex('0', allowed), 0);
    });

    test('قيمةٌ غيرُ مسموحة ⇒ البيع السريع', () {
      expect(resolveDefaultScreenIndex('treasury', allowed), 1);
    });

    test('بلا بيع سريع ⇒ أولُ مسموح', () {
      expect(resolveDefaultScreenIndex('treasury', [8, 4]), 8);
    });

    test('لا مسموح إطلاقاً ⇒ null (لا شاشةَ غيرَ مسموحة) — B-7', () {
      expect(resolveDefaultScreenIndex('treasury', const []), isNull);
      expect(resolveDefaultScreenIndex(null, const [], globalDefault: '0'),
          isNull);
      expect(resolveDefaultScreenIndex('0', const []), isNull);
    });

    test('قيمةُ مستخدمٍ غيرُ مفهومة ⇒ بيعٌ سريع لا الإعدادُ العام', () {
      expect(
          resolveDefaultScreenIndex('garbage', allowed, globalDefault: '8'), 1);
    });

    test('لا قيمةَ للمستخدم ⇒ الإعدادُ العام ثم البيع السريع', () {
      expect(resolveDefaultScreenIndex(null, allowed, globalDefault: '8'), 8);
      expect(resolveDefaultScreenIndex('', allowed, globalDefault: '8'), 8);
      expect(resolveDefaultScreenIndex(null, allowed), 1);
      expect(resolveDefaultScreenIndex(null, allowed, globalDefault: '99'), 1);
    });

    test('النتيجةُ ضمن المسموح دائماً', () {
      for (final s in [null, '', 'pos', 'x', '3', '99', 'floorPlanDesigner']) {
        expect(allowed, contains(resolveDefaultScreenIndex(s, allowed)));
        expect(resolveDefaultScreenIndex(s, const <int>[]), isNull);
      }
    });
  });
}
