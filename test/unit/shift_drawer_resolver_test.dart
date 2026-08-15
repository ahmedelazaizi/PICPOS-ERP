import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/shift_drawer_resolver.dart';

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
  });
}
