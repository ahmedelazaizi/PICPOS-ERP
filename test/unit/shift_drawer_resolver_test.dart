import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/models/shift_drawer_resolver.dart';

void main() {
  group('resolveShiftDrawer', () {
    test('يختار الدرجَ الأكثرَ حركةً', () {
      expect(
        resolveShiftDrawer(
          cashSafeIdsInBranch: {1, 2, 3},
          movedBySafeId: {1: 50.0, 2: 300.0, 3: 20.0},
        ),
        2,
      );
    });

    test('بلا حركةٍ يختار أوّلَ خزائن الفرع', () {
      expect(
        resolveShiftDrawer(
          cashSafeIdsInBranch: {7, 9},
          movedBySafeId: const {},
        ),
        7,
      );
    });

    test('بلا خزنةٍ نقديةٍ يرجع null', () {
      expect(
        resolveShiftDrawer(
          cashSafeIdsInBranch: const {},
          movedBySafeId: const {},
        ),
        isNull,
      );
    });

    test('يتجاهل حركةً على خزنةٍ خارجَ النطاق', () {
      // خزنةٌ من فرعٍ آخرَ تحرّكت أكثر — ولا يجوز أن تُختار درجاً.
      expect(
        resolveShiftDrawer(
          cashSafeIdsInBranch: {4},
          movedBySafeId: {4: 10.0, 99: 5000.0},
        ),
        4,
      );
    });

    test('عند التعادل يختار أوّلَ إدراجٍ في الخريطة', () {
      // حركةٌ متساويةٌ على درجَين: المتوقَّع الأولى في ترتيب إدراج الخريطة (1)
      // لا الأولى في ترتيب مجموعة النطاق (قد تكون 2 بحسب تنفيذ Set).
      expect(
        resolveShiftDrawer(
          cashSafeIdsInBranch: {2, 1},
          movedBySafeId: {1: 100.0, 2: 100.0},
        ),
        1,
      );
    });

    test('درجٌ لم تُلمَس لا تُختار حتى لو كانت في النطاق', () {
      // فقط الخزائنُ التي لها حركاتٌ فعليةٌ مرشحةٌ، لا كلُّ خزائنِ النطاق.
      expect(
        resolveShiftDrawer(
          cashSafeIdsInBranch: {5, 6},
          movedBySafeId: {6: 3.0},
        ),
        6,
      );
    });
  });
}
