# إصلاح B — إعداد القوالب والطباعة الحرارية

التاريخ: 2026-11-03

## النتيجة قبل/بعد

| المجال | قبل | بعد |
|---|---|---|
| ربط القالب بالطابعة | `printWithTemplate` لا يستقبل `printerId`، فيسقط الحسم عن سياق الطابعة. | أُضيف `printerId` اختيارياً، ووصل إلى `TemplateResolver` في مسار التخطيطين. عند الطباعة المباشرة يستنتج المسار طابعة الغرض المناسبة إن لم يمررها المنادي؛ المنادون العارفون بالطابعة يمررونها صراحةً. |
| عرض الطابعة والتوافق | جدول `printers` لا يخزن العرض، وكان حارس المقاس يعتمد على عرض يمرره المنادي فقط. | أضيف `paper_width_mm REAL NULL`، الإصدار 197؛ هجرة SQLite إضافية تحفظ الصفوف، وتهيئة PostgreSQL القائمة تضيف العمود من Drift schema parity. يستخدم `activateBinding` عرض الطابعة المحفوظ عند غياب وسيط العرض، وتبقى القيمة `null` للطابعات القديمة مجهولة العرض. |
| إيصال 58mm | خلايا المبالغ الطويلة تستخدم خط الجدول كما هو، وقد تتجاوز عرضها وتتراكب. | خلايا المبالغ الرقمية ذات 8 خانات فأكثر في الورق ذي عرض المحتوى ≤52mm تُصغّر لتناسب عرض الخلية في محرك التخطيط v2؛ لا يتغير الخط في A4/A5/80mm أو النصوص غير الرقمية. يظل مسار القوالب القديمة `layoutVersion == 1` كما هو. |
| 78mm | لا يوجد مقاس 78mm في المحرر؛ محرك الحراري يطرح 8mm من `paperWidth`. | لا إضافة لمقاس في المحرر وفق قرار المالك. السلوك الحسابي الحالي: `78 - 8 = 70mm`، مع تسامح توافق 3mm؛ نكتفي بقوالب 80mm ولا ندّعي وجود قالب 78mm مستقل. |

## مسارات اللقطات

ستُحفظ الأدلة في `docs/plans/print_fix_B_2026-11-03/`:
- `58mm_S9_before.png` — نسخة من لقطة التدقيق السابق دون تعديل المصدر.
- `58mm_S9_eight_digit_discount_tax.png` — حالة 58mm بعد الإصلاح.
- `invoice_matrix_contact_sheet.png` — لوحة مصفوفة PDF بعد الإصلاح.

وسيُحفظ PDF/CSV الخاص بتوليد المصفوفة في `D:\qa\print_fix_B\invoices\` لتجنب الكتابة فوق مخرجات التدقيق السابق في `D:\qa\print_matrix\invoices\`.

## الاختبارات والتحقق

**التوليد:** انتهت المحاولة الأولى للأمر المعتاد برمز خروج 1 بلا تشخيص، ثم تعلّقت المحاولة المفصّلة. بعد ذلك أُبلغت أن التوليد اكتمل؛ تحققت عند 07:03 من `database.g.dart` ووجدت `paper_width_mm` في الـDrift output، ولا توجد عملية `dartaotruntime`/`dart` لـ`build_runner`. لم أعد تشغيله.

**اختبارات قاعدة البيانات والطابعة:** الأمر المجمّع شغّل `setup_path_audit_test.dart` و`template_binding_reaches_paper_test.dart` و`print_plan_narrow_numeric_test.dart` و`audit_b_migration_safety_test.dart` و`template_bindings_schema_test.dart` و`pg_schema_parity_static_test.dart` و`sqlite_table_parity_heal_test.dart` و`v196_reservation_parties_migration_test.dart` و`audit_b_data002_backfill_country_test.dart` و`backup_restore_drill_real_test.dart` — **67 اختباراً ناجحاً، واختبار SQLCipher واحد متخطّى** لأن المحرك المحمّل ليس SQLCipher. أظهرت المحاولة الأولى بعد التوليد تعارض النوعين `InvoiceItem` في محوّل العناصر؛ فُصل التحويل حسب نوع DTO وأُعيد تشغيل المجموعة بنجاح. ظهرت أثناء هذه الاختبارات تحذيرات `path_provider`/`Binding` من `forTesting`، ورسالة safe-skip لعمود v197 الموجود مسبقاً في قواعد الاختبار، لا إخفاقات اختبار.

- `flutter test --concurrency=1 --dart-define=APP_BRAND=picpos test/structural/migration_numbering_test.dart` — **نجح: اختباران**.
- `flutter test --concurrency=1 --dart-define=APP_BRAND=picpos test/unit/paper_width_guard_test.dart` — **نجح: 8 اختبارات**.
- `flutter test --concurrency=1 --dart-define=APP_BRAND=picpos test/structural/analytics_parity_test.dart test/unit/presentation_db_import_guard_test.dart test/structural/file_size_ratchet_test.dart test/structural/i18n_coverage_test.dart test/structural/i18n_runtime_safety_test.dart test/structural/dark_mode_guard_test.dart` — **كل الاختبارات نجحت**.
- `flutter test --concurrency=1 --dart-define=APP_BRAND=picpos test/unit/print_plan_narrow_numeric_test.dart` — **نجح** بعد إزالة حدّ 4.5pt الذي أبقى التراكب؛ خط التصغير يستخدم معامل عرض محافظاً 0.6em ولا يضع أرضية أعلى من حجم الملاءمة.
- `flutter analyze lib/services/printing/paint_plan.dart test/unit/print_plan_narrow_numeric_test.dart` و`flutter analyze lib/services/printing/template_item_map.dart` — **No issues found!**
- `dart format --output=none --set-exit-if-changed` على 23 ملف Dart معدل — **0 تغييرات**.
- `flutter test --concurrency=1 --dart-define=APP_BRAND=picpos test/structural/file_size_ratchet_test.dart` — **نجح دون رفع السقف**؛ احتاج `invoice_generator.dart` استخراج محوّل العناصر المتكرر إلى `printing/template_item_map.dart` للحفاظ على حد 30KB.
- `flutter analyze lib` انتهى برمز خروج 1 وفيه **معلومتان فقط** من `use_build_context_synchronously` عند `purchase_returns_picpos_logic.dart:48` و`sales_returns_picpos_logic.dart:84`، وهما المذكورتان سابقاً والمسموحتان. أُزيلت المعلومة الجديدة التي ظهرت أولاً في `printer_dao.dart`، ثم أُعيد التحليل؛ لا توجد ملاحظات أخرى.

**مصفوفة PDF:** شُغّل `RUN_PRINT_AUDIT=1 flutter test --concurrency=1 --dart-define=APP_BRAND=picpos test/print_audit/invoices/print_matrix_test.dart` مرتين؛ الجولة النهائية **All tests passed!** وأنتجت 247 PDF/صفاً في `results.csv`. أداة PDFium رسمت 52 tile و9 لقطات مختارة. بصرياً، كانت لقطة قبل الإصلاح متراكبة، وبعده خلايا S9 على 58mm لم تعد تتراكب؛ سجل الصف `clipped_text_runs=0` و`min_font_pt=3.08`. وُثّقت الصور في المسار أدناه.

للتأكد من عدم تغيير المقاسات الأوسع: قورنت صور PDF لـS9 بكسلياً مع المصفوفة السابقة في 18 قالباً (كل A4/A5/80mm) — **كلها متطابقة**؛ كما تطابقت مقاييس CSV لجميع 234 حالة A4/A5/80mm. لم تُنشأ قوالب 78mm.

`TemplateResolver` يحتفظ بسلسلة الربط القائمة؛ اختبار اختيار الطابعة يمرّر سياق المستوى المباشر الحالي (فرع + طابعة + لغة)، ولم أضف مستوى «طابعة فقط». لم يُشغّل PostgreSQL أو واجهة PicPos أو طابعة فعلية؛ توافق PostgreSQL مستنتج من parity الحالي لا من اختبار حي.

## تغييرات متزامنة محفوظة

لم تُمس التغييرات المتزامنة التالية:
- ملفات معدّلة: `lib/services/generators/report_generator.dart`، `lib/services/printing/report_pdf_generator.dart`، `test/print_audit/reports/report_matrix_test.dart`.
- ملفات/مجلدات جديدة: `lib/services/printing/financial_statement_pdf_sections.dart`، `docs/plans/2026-11-03-print-fix-A-reports.md`، `docs/plans/print_fix_A_2026-11-03/`، `docs/plans/2026-11-03-final-live-verification-9.md`، `docs/plans/live9_2026-11-03/`، `Cairo,Noto_Naskh_Arabic/`، `backups/postgres/fiscal_year_overlap/`، `تصميم شاشات فواتير PicPos-handoff/`، `صور لاعادة تصميم الشاشات الموضحه/`، و`طلب مراجعه.txt`.
لم أعدّل `lib/services/printing/report_pdf_generator.dart` أو `assets/invoice_templates/`، ولم أنفذ commit أو push.
