// lib/domain/models/screen_tabs.dart
//
// تاباتُ الشاشات — بلاغُ المالك 2026-09-12: «لو خلينا الشاشات فعلا تفتح فى
// تابات ويتم التنقل من الاعلى حرفيا بينهم».
//
// ⚠️ **وما كان موجوداً ليس تاباتٍ معطوبةً بل فتاتَ خبزٍ خاملاً تماماً.**
// `setBreadcrumbs` يستبدل القائمةَ بمدخلٍ أو مدخلَين في كلّ تنقّل — فلا
// يظهر ثالثٌ أبداً — والنقرُ ميّتٌ لأنّ الأوّلَ (‏رأسُ المجموعة) يُبنى بلا
// `onTap`، والثاني يُبنى بـ`onTap` ثمّ يُرسَم بـ
// `onTap: isLast ? null : item.onTap`. فالوحيدُ الذي يحمل ردَّ فعلٍ هو
// **عينُ** الوحيدِ الذي يُلغى ردُّ فعله.
//
// ═══ حسابٌ خالصٌ بلا ودجت ═══
//
// ما يُخطئ في التابات هو الحساب: أيُّها يُخلى عند الامتلاء، وما يصير نشطاً
// بعد الإغلاق، وماذا يحدث لتابِ شاشةٍ سُحبت صلاحيتُها. والرسمُ تفصيلٌ تابع.

/// سقفُ التابات المفتوحة.
///
/// ⚠️ **والسقفُ ليس تجميلاً.** التاباتُ تُرسَم في `IndexedStack`، وكلُّ
/// شاشةٍ مفتوحةٍ **مبنيّةٌ حيّة**: مؤقّتاتُها تعمل ومراقباتُها على القاعدة
/// تستمع وتُعيد البناء. وثمانيةٌ حدٌّ يحتمله الجهازُ الضعيفُ الذي يُشحَن
/// إليه هذا المنتج، وأكثرُ منها يُحوّل الراحةَ إلى بطء.
const int kMaxScreenTabs = 8;

/// تاباتٌ لا يُخليها السقفُ تلقائيّاً.
///
/// ⚠️ **نقطةُ البيع تحمل بيعاً غيرَ مُفوتَر.** وتفكيكُ شجرتها يمسح السلّةَ
/// بلا سؤالٍ ولا أثرٍ في أيّ سجلّ — وهو عينُ ما تحرسه حوارات «يوجد أصناف في
/// السلة» في مواضعِها الثلاثة. فالإخلاءُ التلقائيُّ يتخطّاها كلَّها.
const Set<int> kUnevictableScreenTabs = <int>{1};

/// حالةُ شريط التابات — قيمةٌ ثابتةٌ لا تُعدَّل في مكانها.
class ScreenTabs {
  /// فهارسُ الشاشات المفتوحة **بترتيب الفتح**.
  ///
  /// ⚠️ **ولا يُعاد ترتيبُها أبداً.** الرسمُ `IndexedStack` والمطابقةُ فيه
  /// بالموضع؛ فترتيبٌ يتغيّر مع الاستعمال ينقل حالةَ شاشةٍ إلى أخرى —
  /// سلّةُ الكاشير تظهر في شاشة المخزون. والمفاتيحُ تُخفّف لا تُبرّئ.
  final List<int> order;

  /// الأحدثُ استعمالاً أوّلاً — للإخلاء وحدَه لا للرسم.
  final List<int> mru;

  /// فهرسُ الشاشة المعروضة.
  final int active;

  const ScreenTabs._({
    required this.order,
    required this.mru,
    required this.active,
  });

  /// تاباتٌ بتابٍ واحدٍ نشط.
  factory ScreenTabs.of(int screenIndex) => ScreenTabs._(
        order: List.unmodifiable([screenIndex]),
        mru: List.unmodifiable([screenIndex]),
        active: screenIndex,
      );

  bool get isFull => order.length >= kMaxScreenTabs;

  bool contains(int screenIndex) => order.contains(screenIndex);

  /// التابُ الذي يُخلى لو احتجنا موضعاً — أو `null` إن لم يوجد.
  ///
  /// أقدمُ **مستعمَلٍ** لا أقدمُ مفتوح: التابُ الأوّلُ قد يكون أكثرَ ما
  /// يُستعمَل. ويُستثنى النشطُ والمحصَّن.
  int? get evictionCandidate {
    for (var i = mru.length - 1; i >= 0; i--) {
      final cand = mru[i];
      if (cand == active) continue;
      if (kUnevictableScreenTabs.contains(cand)) continue;
      return cand;
    }
    return null;
  }

  /// ينشّط [screenIndex]، ويفتحه تاباً جديداً إن لم يكن مفتوحاً.
  ScreenTabs open(int screenIndex) {
    if (contains(screenIndex)) {
      return ScreenTabs._(
        order: order,
        mru: List.unmodifiable(_bumped(screenIndex)),
        active: screenIndex,
      );
    }

    final next = [...order];
    if (next.length >= kMaxScreenTabs) {
      final victim = evictionCandidate;
      if (victim != null) {
        next.remove(victim);
      } else {
        // كلُّ التابات محصَّنةٌ أو نشطة: الجديدُ يحلُّ محلَّ النشط في موضعه
        // — فالتنقّلُ ينجح ولا يُرفَض. والرفضُ يُقعِد المستخدمَ بلا مخرَج.
        next[next.indexOf(active)] = screenIndex;
      }
    }
    if (!next.contains(screenIndex)) next.add(screenIndex);

    return ScreenTabs._(
      order: List.unmodifiable(next),
      mru: List.unmodifiable(
        [screenIndex, ...mru.where(next.contains).where((i) => i != screenIndex)],
      ),
      active: screenIndex,
    );
  }

  /// يُغلق تابَ [screenIndex]. ولا يُغلق التابَ الوحيد.
  ScreenTabs close(int screenIndex) {
    if (order.length <= 1) return this;
    if (!contains(screenIndex)) return this;

    final next = [...order]..remove(screenIndex);
    final nextMru = mru.where(next.contains).toList();
    return ScreenTabs._(
      order: List.unmodifiable(next),
      mru: List.unmodifiable(nextMru),
      // النشطُ أُغلِق ⇒ آخرُ ما استُعمِل، لا الجارُ في الترتيب: الجارُ قد
      // يكون تاباً فُتِح ولم يُنظَر إليه.
      active: screenIndex == active ? nextMru.first : active,
    );
  }

  /// يُسقط تاباتِ الشاشات التي لم تبقَ في [allowed].
  ///
  /// ⚠️ **وهذا ليس تنظيفاً.** الشاشةُ المفتوحةُ في `IndexedStack` مبنيّةٌ
  /// حيّةٌ تقرأ وتكتب؛ فبقاءُ تابِها بعد سحب الصلاحية إبقاءُ الشاشة عاملةً
  /// لمن مُنِعَ منها — والنقرُ عليها لا يمرّ بحارسِ صلاحيةٍ ثانٍ.
  ScreenTabs retain(Set<int> allowed) {
    if (allowed.isEmpty) return this;
    final next = order.where(allowed.contains).toList();
    if (next.isEmpty) return ScreenTabs.of(allowed.first);
    if (next.length == order.length) return this;

    final nextMru = mru.where(next.contains).toList();
    return ScreenTabs._(
      order: List.unmodifiable(next),
      mru: List.unmodifiable(nextMru),
      active: next.contains(active) ? active : nextMru.first,
    );
  }

  List<int> _bumped(int screenIndex) =>
      [screenIndex, ...mru.where((i) => i != screenIndex)];
}
