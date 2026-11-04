// الخروج القسريّ بالخمول وسلّةُ البيع عامرة: تعليقٌ تلقائي *قبل* مسح الجلسة،
// وإن فشل التعليق فالسلّة لا تُمسح (تبقى) والخروج يتمّ والخطأ يُسجَّل.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/entities/cart_item_entity.dart';
import 'package:picpos_erp/presentation/pos/providers/cart_controller.dart';
import 'package:picpos_erp/presentation/widgets/inactivity_detector.dart';
import 'package:picpos_erp/services/session_timeout_service.dart';

final _events = <String>[];
String? _holdResult;

class _Auth extends AuthNotifier {
  @override
  AuthState build() => const AuthState(isAuthenticated: true);

  @override
  void logout() {
    _events.add('logout');
    state = const AuthState();
  }
}

class _Cart extends CartController {
  @override
  CartState build() => const CartState(items: [
        CartItemEntity(
          productId: 1,
          productName: 'x',
          productCode: 'c',
          quantity: 1,
          unitPrice: 5,
        ),
      ]);

  @override
  Future<String?> holdOrder({String? customerName}) async {
    _events.add('hold');
    if (_holdResult != null) state = const CartState(); // كما يفعل الأصلي
    return _holdResult;
  }
}

class _EmptyCart extends CartController {
  @override
  CartState build() => const CartState();

  @override
  Future<String?> holdOrder({String? customerName}) async {
    _events.add('hold');
    return null;
  }
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  CartController Function() cart,
) async {
  final container = ProviderContainer(overrides: [
    authProvider.overrideWith(_Auth.new),
    cartControllerProvider.overrideWith(cart),
    sessionTimeoutProvider.overrideWith((ref) async => 1),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const Directionality(
      textDirection: TextDirection.ltr,
      child: InactivityDetector(child: SizedBox.expand()),
    ),
  ));
  await tester.pump(); // يحلّ إعداد المهلة
  await tester.pump(); // callback التسليح
  return container;
}

void main() {
  setUp(() {
    _events.clear();
    _holdResult = null;
  });

  testWidgets('خمول + سلّة عامرة ⇒ تعليق ثم خروج (بهذا الترتيب)', (tester) async {
    _holdResult = 'H120000';
    final c = await _pump(tester, _Cart.new);

    await tester.pump(const Duration(minutes: 1, seconds: 1));
    await tester.pump();

    expect(_events, ['hold', 'logout']);
    expect(c.read(cartControllerProvider).items, isEmpty);
    expect(c.read(authProvider).isAuthenticated, isFalse);
  });

  testWidgets('فشل التعليق ⇒ السلّة لا تُمسح، والخروج يتمّ', (tester) async {
    _holdResult = null; // الحفظ فشل
    final c = await _pump(tester, _Cart.new);

    await tester.pump(const Duration(minutes: 1, seconds: 1));
    await tester.pump();

    expect(_events, ['hold', 'logout']);
    expect(c.read(cartControllerProvider).items, hasLength(1),
        reason: 'فشل التعليق لا يفقد السلّة');
    expect(c.read(authProvider).isAuthenticated, isFalse);
  });

  testWidgets('خمول + سلّة فارغة ⇒ خروج بلا محاولة تعليق', (tester) async {
    await _pump(tester, _EmptyCart.new);

    await tester.pump(const Duration(minutes: 1, seconds: 1));
    await tester.pump();

    expect(_events, ['logout']);
  });
}
