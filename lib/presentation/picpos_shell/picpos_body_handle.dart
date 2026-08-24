import 'package:flutter/foundation.dart';

/// وصلةٌ بين ترويسةِ شاشةِ PicPos وجسمِها.
///
/// الترويسةُ (`PicPosScreenScaffold.headerActions`) تعيش **فوق** الجسم، بينما
/// إجراءُ زرِّ الـCTA — «طابعة جديدة» · «عطلة جديدة» · «حفظ القالب» — يعيش
/// **داخل** حالةِ الجسم مع البيانات التي يعدّلها ودالّةِ التحديث. فبدل رفعِ
/// المنطق (‏نسخٌ) أو تمريرِ `GlobalKey` إلى حالةٍ عامّة (‏تسريبُ تفاصيل)،
/// يسجّل الجسمُ إجراءَه هنا في `initState` وتستدعيه الترويسة.
///
/// و[isReady] مُستمَعٌ إليه (`ValueListenable`) لأنّ الترويسةَ تُبنى **قبل**
/// أوّلِ `initState` للجسم: الزرُّ يبدأ معطَّلاً ثمّ يُفعَّل بإطارٍ تالٍ.
/// وبغيرِ ذلك يبقى الزرُّ ميّتاً حتّى أوّلِ `setState` عارض — وهو عطبٌ
/// يصعب رؤيتُه لأنّ الزرَّ يعمل عند كلِّ تفاعلٍ لاحق.
class PicPosBodyHandle {
  final ValueNotifier<bool> _ready = ValueNotifier<bool>(false);
  VoidCallback? _action;

  /// يستمع إليه بناءُ الترويسة ليعرف متى صار للزرّ إجراءٌ فعليّ.
  ValueListenable<bool> get isReady => _ready;

  /// يسجّله الجسمُ في `initState`. تمريرُ `null` يفكّ الربط (‏`dispose`).
  void register(VoidCallback? action) {
    _action = action;
    _ready.value = action != null;
  }

  /// تستدعيه الترويسة. آمنٌ قبل التسجيل — لا يفعل شيئاً.
  void invoke() => _action?.call();

  void dispose() {
    _action = null;
    _ready.dispose();
  }
}
