# تصفير المرتجع السريع ومجاميع الدفع — 2026-11-04

## التغييرات

- عند التخلص من شاشة `PicPosPosScreen` يُستدعى callback أُنشئ في `initState` لالتقاط notifier قبل التخلص من `WidgetRef`. إذا بقي وضع مرتجع نشط، يُجدول تصفير `posReturnModeProvider` بـ`scheduleMicrotask`؛ لا تُجرى قراءة أو كتابة عبر `ref` داخل `dispose`. لا يُستدعى هذا المسار في إعادة البناء أو تبديل محتوى داخل الشاشة. اختبار دورة الواجهة يدخل المرتجع، يغادر الشاشة، ثم يعود ويتحقق من غياب الوضع.
- في وضع المرتجع، تستبدل لوحة الدفع مجاميع سلّة البيع بقيمة `refundTotal` نفسها المعروضة في تذييل لوحة المرتجع، بصيغة منزلتين. تسمية الإجمالي «المبلغ المسترد»، ونص زر الإجراء «استرداد {المبلغ}». اختبار widget في الوضع الداكن يثبت تطابق التذييل والإجمالي والزر، ثم يغيّر الكمية ويتحقق من تحديث القيمة فوراً. لم يتغير مسار الإتمام أو قيوده.
- أضيفت ترجمتا «المبلغ المسترد» و«استرداد {p0}» إلى [en.json](<../../assets/i18n/en.json>). استُخرجت دوال عرض المبلغ إلى part صغيرة لتجنّب تجاوز سقف حجم لوحة الدفع.

## التحقق

شُغّل الأمر المطلوب بعد dot-source لـ`D:\qa\luna_tools.ps1` واستدعاء `Clear-SqliteLock`:

`flutter test --concurrency=1 --dart-define=APP_BRAND=picpos` مع اختباري الدورة ولوحة المرتجع، و`test/scenarios/picpos_quick_return_cart_test.dart`، وكل `test/widget/pos_picpos`، والحراس الستة.

النتيجة: 43 نجاحاً وفشل واحد في [حارس حجم الملفات](<../../test/structural/file_size_ratchet_test.dart>) فقط. الحارس سجّل ملفاً من التغييرات المتزامنة: [picpos_search_controller.dart](<../../lib/presentation/pos_picpos/providers/picpos_search_controller.dart>) بحجم 33628 بايت مقابل حد 31585. لم أعدّل هذا الملف أو أي ملف باركود ميزان، ولم أرفع سقف الحارس. لم يذكر الحارس ملفات الشاشة أو لوحة الدفع المعدّلة هنا. نجحت حراس [تغطية الترجمة](<../../test/structural/i18n_coverage_test.dart>) و[أمان الترجمة](<../../test/structural/i18n_runtime_safety_test.dart>) و[الوضع الداكن](<../../test/structural/dark_mode_guard_test.dart>) و[تطابق التحليلات](<../../test/structural/analytics_parity_test.dart>) و[منع استيراد قاعدة البيانات](<../../test/unit/presentation_db_import_guard_test.dart>). وبعد المراجعة النهائية نجحت الاختبارات السبعة في اختباري widget؛ وأعاد حارس الحجم الفشل الخارجي نفسه.

شُغّل `flutter analyze lib`: لا أخطاء تحليل؛ خرج الأمر برمز 1 مع معلومتَي `use_build_context_synchronously` الموجودتين مسبقاً في [purchase_returns_picpos_logic.dart:48](<../../lib/presentation/purchase_returns_picpos/screens/purchase_returns_picpos_logic.dart#L48>) و[sales_returns_picpos_logic.dart:84](<../../lib/presentation/sales_returns_picpos/screens/sales_returns_picpos_logic.dart#L84>).

لم يُشغّل `build_runner`، ولم تتغير schema، ولم يُنفّذ commit أو push أو reset أو checkout أو stash.

## تعايش التغييرات

بقيت تعديلات العامل الموازي دون تعديل في [pos_search_controller.dart](<../../lib/presentation/pos/providers/pos_search_controller.dart>) و[scale_barcode_config.dart](<../../lib/presentation/pos/services/scale_barcode_config.dart>) و[scale_barcode_handler.dart](<../../lib/presentation/pos/services/scale_barcode_handler.dart>) و[picpos_search_controller.dart](<../../lib/presentation/pos_picpos/providers/picpos_search_controller.dart>) و[scale_barcode_config_test.dart](<../../test/unit/scale_barcode_config_test.dart>). كما بقيت العناصر غير المتعقبة الموجودة مسبقاً للمالك دون تعديل: `Cairo,Noto_Naskh_Arabic/` و`backups/postgres/fiscal_year_overlap/` و`تصميم شاشات فواتير PicPos-handoff/` و`صور لاعادة تصميم الشاشات الموضحه/` و[طلب مراجعه.txt](<../../طلب مراجعه.txt>).
