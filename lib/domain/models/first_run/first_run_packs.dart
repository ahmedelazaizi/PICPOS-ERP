// «الباقات» = اختيارُ ملفّ النشاط فقط (قرارُ المالك 2026-10-23): لا استحقاقَ
// ولا ترخيصَ بالأقسام — التفعيلُ في الإعدادات. الباقةُ تضبط ما يظهر من
// الأقسام (‏`business_profile`) ويمكن تعديلُها لاحقاً من الإعدادات.
//
// الربطُ (‏E2 — مبدئيّ بانتظار تأكيد المالك):
//   pos → lite · restaurant → restaurant · business → supermarket · full → unified
// ولا باقةَ `custom` في هذه المرحلة: الأقسامُ غيرُ المعرَّفة بـ`FeatureKey` لا
// تُعرض (‏B6) و«حسب الطلب» تنتظر قرارَ E2.
library;

enum FirstRunPack {
  pos(profileName: 'lite', hasTables: false),
  restaurant(profileName: 'restaurant', hasTables: true),
  business(profileName: 'supermarket', hasTables: false),
  full(profileName: 'unified', hasTables: true);

  const FirstRunPack({required this.profileName, required this.hasTables});

  /// اسمُ قيمة `BusinessProfile` المقابلة (‏`BusinessProfile.values.byName`).
  final String profileName;

  /// هل تعرض الباقةُ إعدادَ الطاولات وطريقةَ خدمة المطعم؟
  final bool hasTables;
}

/// طريقةُ خدمة المطعم (‏تُترجم إلى `feature.pos.tables` و`feature.pos.delivery`).
enum FirstRunServiceType {
  /// طاولات + سفري + توصيل.
  all(tables: true, delivery: true),

  /// سفري وتوصيل فقط.
  takeawayDelivery(tables: false, delivery: true),

  /// طاولات فقط.
  tablesOnly(tables: true, delivery: false);

  const FirstRunServiceType({required this.tables, required this.delivery});

  final bool tables;
  final bool delivery;
}
