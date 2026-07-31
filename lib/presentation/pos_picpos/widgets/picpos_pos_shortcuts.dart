import 'package:flutter/services.dart';

/// الخريطة القانونية لاختصارات نقطة بيع PicPos: المفتاح → معناه.
///
/// ── ليه الملف ده موجود ────────────────────────────────────────────────────
/// كان فيه شريط سفلي (`PicPosShortcutBar`) بيعرض التسميات، وسلسلة `if/else`
/// منفصلة بتنفّذ الأفعال. الشريط اتشال (طلب ٤) — فالتسميات اللي كانت بتوثّق
/// المفاتيح للكاشير وللمبرمج اختفت معاه، وبقى الوحيد اللي يعرف المفاتيح هو
/// سلسلة `if/else` جوه دالة خاصة.
///
/// الثابت ده هو التوثيق الباقي، و`_PicPosPosScreenState._keyActions()` فيه
/// `assert` بيقارن مفاتيحه بمفاتيح الخريطة دي. فأي واحد يضيف مفتاح في مكان
/// وينساه في التاني بياخد فشل صريح في أول ضغطة زر في الديباج أو في الاختبارات،
/// مش اختصار ميت بصمت في الإنتاج.
///
/// ── ليه مش نفس مفاتيح UralCash ───────────────────────────────────────────
/// شاشة UralCash عندها F1–F12 بدلالات مختلفة، وهي ذاكرة عضلات لكاشيرين
/// شغالين فعلاً — مش بتتحرك من هنا. دي مفاتيح تصميم PicPos.
/// `final` مش `const`: `LogicalKeyboardKey` بيعمل override لـ `==`/`hashCode`،
/// و Dart بيمنعه كمفتاح في map ثابتة.
final picposShortcutLabels = <LogicalKeyboardKey, String>{
  LogicalKeyboardKey.f2: 'حفظ',
  LogicalKeyboardKey.f3: 'الفاتورة السابقة',
  LogicalKeyboardKey.f4: 'دفع (حفظ + طباعة + درج)',
  LogicalKeyboardKey.f6: 'تعديل السطر المحدَّد',
  LogicalKeyboardKey.f8: 'حذف السطر المحدَّد',
  LogicalKeyboardKey.escape: 'إلغاء الفاتورة',
  LogicalKeyboardKey.arrowDown: 'السطر التالي',
  LogicalKeyboardKey.arrowUp: 'السطر السابق',
};
