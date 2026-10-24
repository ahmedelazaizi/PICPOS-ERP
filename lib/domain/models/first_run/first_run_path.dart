// مسارات الإعداد الأول — نموذجٌ خالصٌ بلا Flutter (P1 من خطة إعادة التصميم).
//
// ⚠️ لا يستورد `NetworkService`: ربطُ المسار بـ`NetworkMode` في طبقة العرض
// (‏`first_run_finish.dart`)، فهذا الدليلُ يُقاس بلا شبكةٍ ولا قاعدة.
library;

/// الأدوارُ الثلاثة لهذا الجهاز.
enum FirstRunPath {
  /// نسخةٌ مستقلّةٌ على جهازٍ واحد (‏NetworkMode.standalone).
  standalone,

  /// سيرفر رئيسيّ لشركةٍ وفروع (‏NetworkMode.server + PostgreSQL).
  hq,

  /// فرعٌ تابعٌ للسيرفر الرئيسيّ (‏NetworkMode.client).
  branch,
}

/// دورُ الجهاز داخل الفرع.
enum BranchDeviceRole {
  /// أوّل جهازٍ / خادمُ الفرع.
  first,

  /// جهازٌ إضافيٌّ داخل الفرع — عميلٌ آخرُ للرئيسيّ بنفس الفرع (E5).
  additional,
}
