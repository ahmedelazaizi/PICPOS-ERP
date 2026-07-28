# patch: إظهار قناة كليك في تقرير طباعة إغلاق الوردية

**الملف:** `click-shift-close-print.diff` — يمسّ 3 ملفات مشتركة (أصلها UralCash):
`lib/services/printing/thermal_receipt_generator.dart` ·
`lib/services/invoice_generator.dart` ·
`lib/presentation/pos/providers/pos_closing_controller.dart`.

## الباج
تقرير إغلاق الوردية **المطبوع** كان يعرض النقد/البنك/الآجل لكن **يُسقط قناة كليك
تماماً**. البيانات (`salesClick`/`systemClick`/`actualClickAmount`/`clickVariance`)
والديالوج على الشاشة كانا سليمين — لكن مسار الطباعة لم يكن يستقبل أي بارامتر كليك
(`printShiftClosingReport` والـ thermal generator بلا حقول كليك، والكنترولر يمرّر
النقد/البطاقة فقط). فقيم كليك كانت غير مرئية على الإيصال المطبوع.

## الإصلاح
- `thermal_receipt_generator`: أُضيفت 3 بارامترات (`systemClick`/`actualClick`/
  `clickVariance`، افتراضي 0.0) + كتلة «كليك - النظام/الفعلي/الفارق» بعد كتلة البطاقة.
- `invoice_generator`: تمرير البارامترات عبر الغلاف.
- `pos_closing_controller`: تمرير `state.systemClick`/`actualClickAmount`/`clickVariance`.
متوافق رجعياً (البارامترات الجديدة افتراضها 0.0).

## التطبيق (يعمله صاحب المشروع على UralCash)
```bash
git -C D:/URAL-ERP apply --3way patches-for-uralcash/click-shift-close-print.diff
```
صفر إشارات `Brand.`، صفر ملفات PicPos.
