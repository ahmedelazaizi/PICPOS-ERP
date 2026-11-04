# إصلاح C — تنسيق جدول فاتورة 58mm

التاريخ: 2026-11-03

## أ) قائمة التحقق

- ✔ **تخطيط v2 عند عرض محتوى ≤52mm:** جدول الأصناف القياسي يختار نمطاً موحّداً حسب البيانات: المدمج عندما لا تتجاوز خانات الجزء الصحيح 7 وتثبت قياسات عرض محافظة ملاءمة الكمية×السعر والإجمالي عند 7pt؛ سطر الاسم ثم سطر رقمي واحد بخليتين متقابلتين (الكمية×السعر إلى اليمين والإجمالي إلى اليسار في RTL). غير ذلك يُستخدم النمط المكدّس بعرض كامل؛ وقد بقيت قيم 8/10 خانات في المصفوفة كاملة بلا اقتطاع. لا يتغير جدول ذو أعمدة إضافية ولا المقاسات الأوسع.
- ✔ **الخط والاقتطاع الآمن:** لا يقل الخط الرقمي عن 7pt. القيم 8 و10 خانات تستخدم النمط المكدّس بلا اقتطاع في الحالات المقاسة؛ وإذا لم يتسع رقم حتى في عرضه الكامل عند الحد الأدنى، يظهر اقتطاع مرئي `...` عند حد حرفي. الاسم الطويل يلتف داخل ارتفاع سطرين ثم يُقتطع بـ`...` بدلاً من أن يُخفى بصمت.
- ✔ **الترويسة والمحاذاة وتقليل طول الإيصال:** الترويسة سطران في الوضع المدمج وثلاثة في المكدّس، وتحاذي الخلايا المقابلة. قُصّرت ارتفاعات الصور المرسومة: S1 من 875 إلى 684px، وS3 من 2780 إلى 2045px، وS5 (120 صنفاً) من 11828 إلى 8508px؛ أُلغي padding الإضافي عند نهاية الجدول. لقطات S1/S3/S5/S6/S9/S13 روجعت بصرياً؛ مبالغ كاملة ومحاذاة متقابلة، واسم S6 يلتف ثم يُعلّم اقتطاعه.
- ✔ **عدم تغيير A4/A5/80mm وlayoutVersion==1:** اختبار `printing_layout_v2_test.dart` نجح (7 اختبارات). قورنت لقطات PDFium في 40 صورة A4/A5/80mm مع إصلاح B: 0 اختلافات و0 مفقودات (SHA-256 متطابق لكل صورة).
- ✔ **اختبارات الخلية الضيقة والمصفوفة:** اجتازت اختبارات الوحدة الأربعة اختيار 5/7 خانات المدمج، ومحاذاة RTL، واقتطاع الاسم الطويل، وبقاء قيم 8/10 خانات كاملة في النمط المكدّس. المصفوفة أنشأت 266 PDF (19 قالباً × 14 حالة)؛ النتائج في `D:\qa\print_fix_C\invoices\results.csv`.
- ✔ **التحقق البصري والأدلة:** أداة PDFium رسمت 56 tile؛ روجعت S1/S3/S5 (120 صنفاً)/S6/S9/S13. تحفظ `*_before_adaptive.png` صور S1/S3/S5 السابقة، واللقطات الحالية بأسمائها الأصلية؛ توجد نسخة overview قابلة للعرض لـ120 صنفاً. الأدلة في [`print_fix_C_2026-11-03/`](<print_fix_C_2026-11-03/>): `58mm_S1_5_items_before_adaptive.png`، `58mm_S1_5_items.png`، `58mm_S3_25_items_before_adaptive.png`، `58mm_S3_25_items.png`، `58mm_S5_120_items_before_adaptive.png`، `58mm_S5_120_items_before_adaptive_overview.png`، `58mm_S5_120_items_overview.png`، `58mm_S6_long_name_96.png`، `58mm_S9_eight_digit_discount_tax.png`، `58mm_S13_ten_digit_amount.png`، و`invoice_matrix_contact_sheet.png`.
- ✔ **الحراس:** `file_size_ratchet_test` و`i18n_coverage_test` و`i18n_runtime_safety_test` و`dark_mode_guard_test` و`analytics_parity_test` و`presentation_db_import_guard_test` اجتازت جميعها دون رفع أي سقف.
- ✔ **التحليل والتنسيق:** `flutter analyze` لملفي التخطيط والرسم لم يجد ملاحظات. تحليل `lib` أظهر المعلومتين القديمتين المسموحتين فقط. فحص `dart format` النهائي اجتاز دون تغييرات.
- ✔ **الممنوعات:** لم يُشغّل `build_runner`، ولم تُمس الملفات المحاسبية أو التقارير أو مسار الطابعة، ولم تُنشأ قوالب جديدة، ولم يحدث commit أو push أو reset/checkout/stash.

## ب) الأوامر والنتائج

- `. D:\qa\luna_tools.ps1; flutter test --concurrency=1 --dart-define=APP_BRAND=picpos test/unit/print_plan_narrow_numeric_test.dart` — `00:00 +4: All tests passed!`.
- `. D:\qa\luna_tools.ps1; $env:RUN_PRINT_AUDIT='1'; flutter test --concurrency=1 --dart-define=APP_BRAND=picpos test/print_audit/invoices/print_matrix_test.dart; $code=$LASTEXITCODE; Remove-Item Env:\RUN_PRINT_AUDIT -ErrorAction SilentlyContinue; exit $code` — `00:08 +1: All tests passed!`، و266 ملف PDF. ظهرت أثناء تشغيل الاختبار تحذيرات `MissingPluginException` من `path_provider` ورسائل تعذر رسم emoji glyphs؛ لم تفشل الاختبارات.
- `python tool/print_audit/render_pdfium_sheets.py` عبر Python المرفق — `PDFium rendered 56 contact-sheet tiles`، و`Curated images: 18`.
- مقارنة SHA-256 للصور A4/A5/80mm — `checked=40 mismatches=0 missing=0`.
- `. D:\qa\luna_tools.ps1; Invoke-FlutterTest test/structural/file_size_ratchet_test.dart test/structural/i18n_coverage_test.dart test/structural/i18n_runtime_safety_test.dart test/structural/dark_mode_guard_test.dart test/structural/analytics_parity_test.dart test/unit/presentation_db_import_guard_test.dart` — `00:44 +14: All tests passed!`.
- `. D:\qa\luna_tools.ps1; Invoke-FlutterTest test/unit/printing_layout_v2_test.dart` — `00:09 +7: All tests passed!`.
- `flutter analyze lib/services/printing/layout_engine.dart lib/services/printing/paint_plan.dart` — `No issues found! (ran in 0.8s)`.
- `flutter analyze lib` — `2 issues found. (ran in 12.0s)`، كلاهما معلومتا `use_build_context_synchronously` فقط: `lib\presentation\purchase_returns_picpos\screens\purchase_returns_picpos_logic.dart:48:7` و`lib\presentation\sales_returns_picpos\screens\sales_returns_picpos_logic.dart:84:7`.
- `dart format --output=none --set-exit-if-changed lib/services/printing/layout_engine.dart lib/services/printing/paint_plan.dart test/unit/print_plan_narrow_numeric_test.dart test/print_audit/invoices/print_matrix_test.dart` — `Formatted 4 files (0 changed) in 0.05 seconds.`

ملاحظة قياس: تسجل الحالات الست `min_font_pt=7.00`. `clipped_text_runs=0` في S1/S3/S5/S9/S13، وواحد في S6 وهو اقتطاع الاسم الطويل المقصود والظاهر بعلامة `...`. عمود `text_overlaps` تقديري وغير موثوق وفق تدقيق B؛ لم يُستخدم لإعلان القبول، بل روجعت اللقطات بصرياً.

## ج) الملفات المعدّلة

- `lib/services/printing/layout_engine.dart` — تحديد النمط المدمج/المكدّس من عرض الأرقام، خليتا الأرقام المتقابلتان RTL، وتقليص الاسم عند حدّ السطرين.
- `lib/services/printing/paint_plan.dart` — استخدام إزاحات/ارتفاعات الخلايا، والحفاظ على حد أدنى 7pt مع علامة اقتطاع مرئية للأرقام التي تتجاوز حتى العرض الكامل.
- `test/unit/print_plan_narrow_numeric_test.dart` — اختبارات حدّ النمط، قياسات الخلايا والمحاذاة، الاقتطاع المرئي للاسم الطويل، واكتمال الأرقام المكدّسة.
- `test/print_audit/invoices/print_matrix_test.dart` — مخرجات خاصة بـC وإضافة حالة عشرة أرقام.
- `tool/print_audit/render_pdfium_sheets.py` — تحويل جذر النتائج إلى C، اختيار لقطات الحالات، وإنشاء overview قبل/بعد لـ120 صنفاً.
- تقرير C الحالي ومجلد اللقطات المذكور أعلاه.

حُفظت نسخ ما قبل التعديل في `D:\qa\print_fix_C_backup\` وفق ميثاق العمل. لا تغيير في `file_size_baseline.txt`. لا تعديل على `template_render_pipeline.dart` أو ملفات الأصول: الحصر داخل محرك التخطيط v2 مناسب، ويتجنب تغيير القوالب الافتراضية أو أي منطق أعمال.

## د) ما لم يُنفذ

لم يُشغّل build_runner عمداً (ممنوع ولا حاجة إليه). لم يُشغّل تحليل على Windows printer حقيقي أو معاينة واجهة؛ التحقق بصري على PDFium. `flutter analyze lib` بقي برمز خروج 1 بسبب المعلومتين السابقتين المحددتين أعلاه؛ تحليل الملفين المعدّلين نجح بلا ملاحظات.

## هـ) المخاطر والتراجع

التخطيط المدمج يخفض ارتفاع الصف إلى 15mm للأسماء ذات الحيز المحدد وسطر الأرقام، والمكدّس 21mm؛ كلاهما بلا padding ختامي زائد. اختيار المدمج محافظ ومشروط بحد 7 خانات وقياس مساحة عند 7pt؛ أي قيمة 8 خانات فأكثر تبقي الجدول كله مكدّساً. يقتصر الإصلاح على `contentWidth <=52mm` والجداول القياسية ذات الاسم والكمية والسعر والإجمالي. للتراجع عند طلب المالك، تُستخدم النسخ الاحتياطية في `D:\qa\print_fix_C_backup\` يدوياً بعد مراجعة حال الشجرة؛ لم يُنفّذ أي استرجاع أو حذف.
