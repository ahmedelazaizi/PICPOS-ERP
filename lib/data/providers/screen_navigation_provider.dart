// قناةُ «افتح شاشةَ كذا» — من أيّ شاشةٍ إلى مُوجِّه التابات.
//
// ═══ لماذا وُجدت ═══
//
// ‏`_activateScreen` في `app_main_screen` هي **المعبرُ الوحيد** لفتح تابٍ
// أو تنشيطه، وهي حالةٌ خاصّةٌ في تلك الودجت. فالشاشاتُ المتداخلةُ لا تصلها:
// كان يُمرَّر `onNavigate` يدويّاً إلى ودجتَين اثنتَين فقط.
//
// وقرارُ المالك 2026-09-18 يبني **زرَّ القفز إلى المستند المصدر** في اليومية
// العامة، وقرارُ كشف الحساب يبني «عرض المستند» **بنفس الآليّة**. فالقناةُ
// مشتركةٌ بالتصميم لا بالمصادفة.
//
// ═══ 🔴 ولماذا عدّادٌ مع الفهرس ═══
//
// مزوِّدُ حالةٍ يحمل الفهرسَ وحدَه **يوقظ مرّةً واحدة**: طلبُ نفسِ الشاشة
// مرّتَين يعطي قيمتَين متساويتَين، فتبتلع Riverpod الثانيةَ بالمساواة ولا
// يقع شيء. والمستخدمُ ينقر «المستند المصدر» على قيدَين من نفس النوع فيعمل
// الأوّلُ ويموت الثاني.
//
// فلكلّ طلبٍ **رقمٌ متزايد**: قيمتان لا تتساويان أبداً ولو تساوى فهرساهما.

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// طلبُ فتحِ شاشة.
class ScreenNavigationRequest {
  const ScreenNavigationRequest({required this.screenIndex, required this.seq});

  /// فهرسُ الشاشة في `kAllNavItemDefs` — لا `ScreenId` نفسُه، لأنّ المُوجِّهَ
  /// يعمل بالفهارس.
  final int screenIndex;

  /// رقمُ الطلب — يجعل طلبَين متطابقَين في الفهرس **مختلفَين** في القيمة.
  final int seq;

  @override
  bool operator ==(Object other) =>
      other is ScreenNavigationRequest &&
      other.screenIndex == screenIndex &&
      other.seq == seq;

  @override
  int get hashCode => Object.hash(screenIndex, seq);
}

class ScreenNavigationController extends Notifier<ScreenNavigationRequest?> {
  var _seq = 0;

  @override
  ScreenNavigationRequest? build() => null;

  /// يطلب فتحَ شاشةٍ بفهرسها.
  ///
  /// ⚠️ **ولا يفتحها بنفسه**: مَن يستمع هو مالكُ التابات، وهو وحدَه يعرف
  /// الصلاحيّاتِ وتاريخَ الرجوع وسقفَ التابات.
  void open(int screenIndex) {
    state = ScreenNavigationRequest(screenIndex: screenIndex, seq: ++_seq);
  }

  /// يُستهلَك الطلبُ بعد تنفيذه فلا يُعاد تنفيذُه عند إعادة بناءٍ عارضة.
  void consume() => state = null;
}

final screenNavigationProvider =
    NotifierProvider<ScreenNavigationController, ScreenNavigationRequest?>(
        ScreenNavigationController.new);
