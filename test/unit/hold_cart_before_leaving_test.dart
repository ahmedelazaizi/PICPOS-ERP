// تعليق السلّة قبل المغادرة: النجاح، والفشل (استثناء أو null) لا يُفقد السلّة
// بصمت — يُسجَّل ويُرجَع failed.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/presentation/pos/logic/hold_cart_before_leaving.dart';

void main() {
  test('سلّةٌ فارغة ⇒ empty ولا يُستدعى التعليق', () async {
    var called = false;
    final r = await holdCartOrKeep(
      itemCount: 0,
      hold: () async {
        called = true;
        return 'H1';
      },
    );
    expect(r, CartHoldOutcome.empty);
    expect(called, isFalse);
  });

  test('نجاح التعليق ⇒ held بلا تسجيل خطأ', () async {
    final errors = <String>[];
    final r = await holdCartOrKeep(
      itemCount: 2,
      hold: () async => 'H120000',
      onError: (m, e, s) => errors.add(m),
    );
    expect(r, CartHoldOutcome.held);
    expect(errors, isEmpty);
  });

  test('الحفظ يُرجع null ⇒ failed ويُسجَّل الخطأ', () async {
    final errors = <String>[];
    final r = await holdCartOrKeep(
      itemCount: 2,
      hold: () async => null,
      reason: 'inactivity',
      onError: (m, e, s) => errors.add(m),
    );
    expect(r, CartHoldOutcome.failed);
    expect(errors, hasLength(1));
    expect(errors.single, contains('inactivity'));
  });

  test('الحفظ يرمي استثناءً ⇒ failed ويُسجَّل مع الاستثناء (لا يتسرّب)', () async {
    Object? seen;
    final r = await holdCartOrKeep(
      itemCount: 1,
      hold: () async => throw StateError('db down'),
      onError: (m, e, s) => seen = e,
    );
    expect(r, CartHoldOutcome.failed);
    expect(seen, isA<StateError>());
  });
}
