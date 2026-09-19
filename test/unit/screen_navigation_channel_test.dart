// قناةُ «افتح شاشةَ كذا» — **توقظ في كلّ مرّة، لا مرّةً واحدة**.
//
// ═══ 🔴 فئةُ العطب ═══
//
// مزوِّدُ حالةٍ يحمل الفهرسَ وحدَه يُبتلَع بالمساواة: طلبُ نفسِ الشاشة
// مرّتَين يعطي قيمتَين متساويتَين، فلا يُخطَر المستمعُ بالثانية. والمستخدمُ
// ينقر «المستند المصدر» على قيدَين من نفس النوع فيعمل الأوّلُ ويموت الثاني —
// نقرةٌ لا يتبعها شيء، وهي **عينُ** العطب الموثَّق في
// `StreamProvider<void>` في هذا المستودع.
//
// ولذلك لكلّ طلبٍ رقمٌ متزايدٌ يجعل قيمتَين لا تتساويان أبداً.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/screen_navigation_provider.dart';

void main() {
  late ProviderContainer container;
  late List<int> woken;

  setUp(() {
    container = ProviderContainer();
    woken = [];
    container.listen<ScreenNavigationRequest?>(
      screenNavigationProvider,
      (_, next) {
        if (next != null) woken.add(next.screenIndex);
      },
      fireImmediately: false,
    );
  });

  tearDown(() => container.dispose());

  test('تبدأ بلا طلب', () {
    expect(container.read(screenNavigationProvider), isNull);
  });

  test('وطلبٌ واحدٌ يوقظ مرّةً بفهرسه', () {
    container.read(screenNavigationProvider.notifier).open(32);
    expect(woken, [32]);
  });

  test('🔴 وطلبان لنفس الشاشة يوقظان **مرّتَين**', () {
    // بلا العدّاد تُبتلَع الثانيةُ بالمساواة: نقرةٌ لا يتبعها شيء.
    final n = container.read(screenNavigationProvider.notifier);
    n.open(32);
    n.consume();
    n.open(32);
    expect(woken, [32, 32],
        reason: 'الطلبُ الثاني ابتُلع بالمساواة — الزرُّ يعمل مرّةً ثمّ يموت');
  });

  test('وحتى بلا استهلاكٍ بينهما', () {
    final n = container.read(screenNavigationProvider.notifier);
    n.open(32);
    n.open(32);
    expect(woken, [32, 32]);
  });

  test('والاستهلاكُ يمحو الطلبَ فلا يُعاد تنفيذُه', () {
    // ⚠️ مزوِّدٌ يحتفظ بآخر طلبٍ يُعيد تنفيذَه مع أوّل إعادةِ بناءٍ عارضة،
    // فتقفز الشاشةُ بلا أن ينقر أحد.
    final n = container.read(screenNavigationProvider.notifier);
    n.open(7);
    expect(container.read(screenNavigationProvider), isNotNull);
    n.consume();
    expect(container.read(screenNavigationProvider), isNull);
  });

  test('والرقمُ يتزايد فلا تتساوى قيمتان أبداً', () {
    final n = container.read(screenNavigationProvider.notifier);
    n.open(1);
    final first = container.read(screenNavigationProvider)!;
    n.open(1);
    final second = container.read(screenNavigationProvider)!;
    expect(first.screenIndex, second.screenIndex);
    expect(first == second, isFalse,
        reason: 'قيمتان متساويتان ⇒ إخطارٌ مبتلَع');
    expect(second.seq, greaterThan(first.seq));
  });
}
