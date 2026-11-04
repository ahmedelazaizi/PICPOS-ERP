# إصلاح E — حفظ PDF وعرض الورق والصفحة القصيرة

التاريخ: 2026-11-03

## ما نُفّذ

- شاشة اختبار الطباعة تُنتج بايتات PDF من `TemplateRenderPipeline.render` بنفس القالب وبيانات الحالة التي خرجت منها المعاينة. زر «حفظ PDF» يفتح `FilePicker.saveFile`، يكتب البايتات فعلياً، ثم يعرض المسار وإجراء «فتح» عبر `url_launcher`. لا يوجد fallback تلقائي إلى Documents لأن حزمة اختيار الملف متاحة في `pubspec.yaml`.
- معالج الطابعة يعرض مقاسات 58/80/A5/ A4 وعرضاً مخصصاً؛ يتصل الحفظ بـ`paperWidthMm` عبر repository القائم. عُزل عنصر الواجهة في مكوّن مستقل للحفاظ على سقف حجم الملف. لم تتغير جداول Drift أو schema.
- خُفّضت هوامش كشف الطرف، وفُصلت آخر أربع حركات مع الإجمالي في مجموعة غير قابلة للانقسام عند تجاوز 25 حركة. حتى 25 حركة تبقى في جدول واحد لتجنب رأس مكرر في منتصف الصفحة. لم يتغير أي احتساب مالي.

## اختبارات ولقطات قبل/بعد

- `party_statement_orphan_test.dart` ينشئ كشفاً واقعياً لكل N من 18 إلى 45، يستخرج نص الصفحات بـ`pdf_probe`، ويتطلب أربع حركات على الأقل في الصفحة الأخيرة، مع الرأس المتكرر والترقيم على كل صفحات الاستمرار. اجتاز النطاق كاملاً بعد تعديل التقسيم. يحفظ أيضاً PDF لـN=25 خارج المستودع لأغراض العرض.
- `print_pdf_file_saver_test.dart` يحقن مساراً محدداً، يكتب ملفاً فعلياً إلى قرص الاختبار، ويتحقق من بادئة `%PDF` ومطابقة البايتات. `printer_paper_width_fields_test.dart` يثبت تفاعل القيم القياسية والمخصصة؛ وتثبت `setup_path_audit_test.dart` حفظ/قراءة العرض في Drift/repository، بينما يثبت `paper_width_guard_test.dart` أثر التوافق والرفض.
- اللقطة قبل مأخوذة من مصفوفة 25 حركة السابقة: الصفحة الثانية كانت حركتين والإجمالي فقط. اللقطة بعد هي PDF مولد حديثاً لـN=25، صفحة واحدة، دون رأس مكرر وسط الجدول أو تراكب ظاهر.

![قبل: صفحتان والثانية حركتان وإجمالي](<print_fix_E_2026-11-03/party_25_before.png>)

![بعد: 25 حركة والإجمالي بصفحة واحدة](<print_fix_E_2026-11-03/party_25_after.png>)

## نتائج التحقق الحالية

- اختبارات حفظ PDF وواجهة عرض الورق ومصفوفة الأطراف N=18..45 اجتازت منفردة. اختبار حفظ PDF أثبت الملف والبايتات، واختبار الواجهة أثبت 58mm و76.5mm. تحذيرات `MissingPluginException` الخاصة بـ`path_provider` في الاختبارات لم تفشل هذه الاختبارات.
- مجموعة التحقق المطلوبة شُغّلت بعد `Clear-SqliteLock`، وأعادت `All tests passed!` (44 test case): اختبارات حفظ PDF وعرض الورق وكشف الطرف، مصفوفة التقارير مع `--run-skipped`، `setup_path_audit_test.dart`، `paper_width_guard_test.dart`، `printing_layout_v2_test.dart`، والحراس الستة (`file_size_ratchet`, `i18n_coverage`, `i18n_runtime_safety`, `dark_mode_guard`, `analytics_parity`, `presentation_db_import_guard`).
- شغّلت `flutter test test/widget/first_run/` للتحقق من التحميل: لم يظهر خطأ `FilePicker.platform`؛ اكتمل الاختبار بـ150 نجاحاً و4 إخفاقات في اختبارات first-run الموجودة (ليست تغييرات هذه المهمة). لذلك لا أصف كامل مجلد first-run بأنه ناجح.
- `flutter analyze lib` — لا أخطاء تحليل؛ أعاد فقط معلومتَي `use_build_context_synchronously` الموجودتين في `purchase_returns_picpos_logic.dart:48` و`sales_returns_picpos_logic.dart:84` (رمز خروج 1 بسبب مستوى info).
- لم يُشغّل الاختبار الحي عبر Microsoft Print to PDF؛ هذه الجولة تغطي كود واختبارات فقط.

## ملفات ملامسة

`lib/presentation/print_test_picpos/screens/print_test_picpos_screen.dart`، `lib/data/providers/print_test_providers.dart`، `lib/presentation/screens/printers_screen.dart`، `lib/presentation/screens/printer_paper_width_fields.dart`، `lib/services/printing/print_pdf_file_saver.dart`، `lib/services/printing/report_pdf_generator.dart`، `test/unit/print_pdf_file_saver_test.dart`، `test/widget/printer_paper_width_fields_test.dart`، `test/print_audit/reports/party_statement_orphan_test.dart`، و`assets/i18n/en.json`.

لم يُعثر على زر آخر باسم «حفظ PDF» أو تصدير PDF يكتفي برسالة نجاح بلا إنشاء ملف؛ أزرار PDF/التصدير الأخرى التي تطابقت في البحث تستخدم مولّد PDF أو مسارات Excel/CSV.

اللقطات الأصلية: [قبل](<print_fix_E_2026-11-03/party_25_before.png>) و[بعد](<print_fix_E_2026-11-03/party_25_after.png>). لقطة قبل مأخوذة من مصفوفة التدقيق A وتُظهر صراحةً صفحتها الثانية ذات الحركتين والإجمالي؛ لقطة بعد رُسمت من PDF جديد ناتج عن `N=25`.
