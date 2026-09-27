# PR: تدقيق شامل للمشروع + إصلاح الفجوات الآمنة

**الفرع:** `review/full-audit-2026` ← `main`

## الملخص

- تقرير تدقيق تفصيلي بالعربية: `docs/audit/2026-full-project-audit.md` يغطي الفجوات المالية والمحاسبية (44 بندًا)، والتقنية (30 بندًا)، والواجهة (18 بندًا)، مع تصنيف الخطورة وخارطة طريق مرحلية.
- إصلاح 22 من 24 بندًا «آمنًا» مقترحًا في §5 من التقرير (البند 7 لم يُنفَّذ عمدًا، والبند 8 مؤجَّل لتعذّر تنزيل الخطوط).
- إضافة `invoice_templates/` (قوالب الطباعة وتصاميم الشاشات).

## الإصلاحات

**حواجز محاسبية (لا تغيّر نتيجة أي مسار صحيح):**
- `rejectJournalEntry` يرفض القيد المرحَّل.
- `updateSalesInvoicePayment`: فحص الفترة المالية قبل حذف القيد، لا بعده.
- `deleteExpense`: فحص الفترة المالية المقفلة قبل الحذف.
- `changePaperStatus`: تجاهل تغيير الحالة إلى نفس الحالة (يمنع قيدًا مكررًا).
- تسجيل تشخيصي لفشل قيد سند المخزون، و`@Deprecated` على `createDraftJournalEntry`.

**الواجهة:** زر «عرض» ميت في طلبات المخزون، وزر «الميزان» يُرسم معطَّلًا، وكاسرات الوضع الداكن في 5 شاشات، وفيض العناوين في 3 حوارات، وألوان الخطر عبر `AppColors.error`، وتحويلات RTL اتجاهية في 7 مواضع، وإعلان خط `Cairo` في `pubspec.yaml`.

**المستودع وCI:** `.gitignore` (`*.bak`، `*.root-backup`، `tools/picpos-activation/`)، وحذف ملفَي `.bak` من `lib/`، وإزالة كلمة مرور قاعدة الاختبار من `scripts/gate.sh` (صار يتطلب `PG_TEST_DSN`)، وحدود حجم CI لأكبر 3 ملفات.

## التحقق

- `dart analyze` على الـ26 ملف Dart المعدَّلة: `No issues found!`
- `flutter test test/unit/audit_safe_fixes_test.dart test/unit/commercial_papers_state_machine_test.dart test/integration/pir_fiscal_period_blocking_test.dart`: `All tests passed!` (15).
- **لم يُشغَّل:** مجموعة الاختبارات الكاملة و`flutter analyze lib/` الكامل. لم يُفحَص أي شيء بصريًا على الشاشة.

## تنبيهات قبل الدمج

- **CI سيبقى أحمر** بسبب `client_write_interceptor.dart` (48,876 بايت > حد 43,000). المشكلة موجودة في `main` قبل هذا الـ PR.
- **`scripts/gate.sh --with-pg`** يحتاج الآن ضبط `PG_TEST_DSN`، ويجب تغيير كلمة مرور قاعدة الاختبار المكشوفة.
- **حرج (TE-01):** ملح الترخيص ما زال في `lib/services/license_service.dart:20` في `main`؛ أي شخص لديه الكود يمكنه توليد مفاتيح تفعيل. يحتاج قرارًا (توقيع غير متماثل).
