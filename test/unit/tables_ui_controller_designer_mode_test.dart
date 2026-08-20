// المهمّة ٦-ب — `TablesUIController.toggleView` يجب أن يُطفئ `isDesignerMode`
// عند مغادرة الخريطة (البند ٥ في `task-6b-brief.md`).
//
// `tablesUIProvider` مُخبّأٌ بلا `AppDatabase` ولا مستودعٍ إطلاقاً — حالةُ
// واجهةٍ خالصةٌ، فـ`ProviderContainer` وحدَه كافٍ بلا `ProviderScope` ولا
// فتح شاشة.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/presentation/screens/tables/providers/tables_state_provider.dart';

void main() {
  test('تفعيلُ التصميم ثم مغادرةُ الخريطة يُطفئه', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(tablesUIProvider.notifier);

    // الحالةُ الافتراضيّةُ خريطةٌ (isVisualView: true)، فتفعيلُ التصميم هنا
    // صالحٌ فوراً.
    notifier.toggleDesignerMode();
    expect(container.read(tablesUIProvider).isDesignerMode, isTrue);

    // مغادرةُ الخريطة إلى الشبكة.
    notifier.toggleView();
    final afterLeaving = container.read(tablesUIProvider);
    expect(afterLeaving.isVisualView, isFalse);
    expect(afterLeaving.isDesignerMode, isFalse,
        reason: 'مغادرةُ الخريطة تُطفئ وضعَ التصميم');
  });

  test('العودةُ إلى الخريطة لا تُعيد إشعالَ وضع التصميم من تلقاء نفسها', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(tablesUIProvider.notifier);

    notifier.toggleView(); // خريطة -> شبكة
    notifier.toggleView(); // شبكة -> خريطة

    final state = container.read(tablesUIProvider);
    expect(state.isVisualView, isTrue);
    expect(state.isDesignerMode, isFalse);
  });

  test('تبديلُ العرض بلا تصميمٍ مفعّلٍ لا يغيّر شيئاً في isDesignerMode', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(tablesUIProvider.notifier);

    notifier.toggleView();
    expect(container.read(tablesUIProvider).isDesignerMode, isFalse);
  });
}
