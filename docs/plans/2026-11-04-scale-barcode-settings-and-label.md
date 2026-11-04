# إعداد باركود الميزان وملصق الميزان — تقرير (2026-11-04)

نقطة البداية: HEAD `da664339`. لم يُنفَّذ commit/push/reset/checkout/stash، ولا build_runner، ولا تغيير schema.

## السبب الجذري

### 1. شاشة «باركود الميزان» تظهر «غير مفعّل» بلا حقول
- في `scale_barcode_settings_picpos.dart` (نسخة حرفية من `screens/settings/scale_barcode_settings.dart`) كانت حقول البادئة/طول الكود/القسمة **داخل `if (_weightEnabled)` / `if (_priceEnabled)`**، والكل داخل `ExpansionTile` مطويّ. القيمة الافتراضية لـ`scale_weight_enabled` غير موجودة ⇒ `false` ⇒ يرى المستخدم «غير مفعّل» ومفتاحين فقط، وهذا ما وثّقه التحقق الحي final3.
- **مؤشر مخفي/معماري:** مفتاحا `scale_weight_enabled` و`scale_price_enabled` **لا يقرؤهما أي كود سوى الشاشة نفسها**. `ScaleBarcodeHandler` يحلّل باركود الميزان في البيع دائماً بالبادئات وحدها (`quick_sale_policy.dart`، صف `pos_read_scale_barcode`، يصرّح بأن الإطفاء لا يوقف القراءة). فالمفتاح كان شكلياً، ويحجب الحقول فقط.
- **تعارض افتراضي:** الشاشة كانت تفترض بادئة السعر `22`، بينما المحلّل يفترض `20` للسعر ويستعمل `22` بادئةً بديلة للوزن (`scale_fallback_prefix`). ولأن المحلّل يفحص بادئة السعر أولاً، فإن تفعيل «ميزان المجموع» بالقيم الافتراضية يحفظ `scale_price_prefix=22`، فتصبح ملصقات الوزن ذات البادئة 22 «سعراً».
- لم يكن هناك أي تحقق: الحفظ يجري عند كل ضغطة مفتاح، ويقبل بادئة فارغة أو غير رقمية أو أطوالاً لا تتسع في 13 خانة.

### 2. «ملصق ميزان» لم يظهر في نافذة طباعة الباركود
- `BarcodeLabelBatchDialog` فيه قائمتان: «قالب الملصق» (يظهر فيها «ملصق ميزان» كقالب عادي) و«مقاس الملصق: باركود قياسي/باركود الميزان» (`scale_label_template_dropdown`)، والثانية لا تظهر إلا لصنف موزون واحد بالضبط. اختيار «ملصق ميزان» من القائمة الأولى لا يُظهر حقل الوزن، فيُطبع الملصق بباركود الصنف العادي وبلا وزن. ولصنف غير موزون يظهر القالب كأي قالب آخر، بلا تفسير.
- `BarcodePrintDialog` كان يقرأ ثلاثة مفاتيح فقط (`scale_weight_prefix`, `scale_weight_item_code_len`, `scale_weight_divider`). فلا يعرف إن كان الإعداد مفعّلاً، ولا يقرأ المفاتيح القديمة.
- غياب القالب من المكتبة في لقطة final3: البذرة `seedScaleBarcodeTemplateIfMissing` تُستدعى عند كل إقلاع عبر `deployReadyTemplates` (`database_startup.dart:1058`)، بعلامة `seed:scale_label`. والحزمة المنشورة في `D:\qa\ui_audit\app` لم يُعَد بناؤها، فعلى الأرجح تسبق البذرة. **لم أتحقق من ذلك حياً.** إن غاب القالب، يعرض الحوار الآن سبباً صريحاً بدل الصمت.

## حصر مفاتيح الإعداد (من الكود)
| المفتاح | يقرؤه | الافتراضي |
|---|---|---|
| `scale_weight_prefix` | المحلّل، شاشة PLU، `label_scale_service` | 21 |
| `scale_price_prefix` | المحلّل، شاشة PLU | 20 |
| `scale_fallback_prefix` | المحلّل (وزن) | 22 |
| `scale_weight_item_code_len` / `scale_price_item_code_len` | المحلّل | 5 |
| `scale_weight_divider` / `scale_price_divider` | المحلّل (`double.tryParse`) | 1000 / 100 |
| `scale_weight_enabled` / `scale_price_enabled` | الشاشة، والآن حوار الطباعة | false |
| قديمة، للقراءة فقط: `scale_barcode_prefix`, `scale_barcode_code_length`, `scale_barcode_divider`, `scale_qty_enabled`, `scale_qty_prefix`, `scale_qty_code_length`, `scale_price_code_length`, `scale_qty_divider` | الشاشة | — |

- **عدد خانات القيمة لا مفتاح له:** المحلّل يأخذ ما بين نهاية PLU والخانة 12، فهو مشتق = 12 − طول البادئة − خانات PLU. يُعرض للقراءة فقط.
- **خانة التحقق (13):** إلزامية دائماً، يحسبها المشفّر ويرفض المحلّل الملصق إن كانت خاطئة. لا يوجد في الكود «check digit للسعر» داخل القيمة، فلم يُضف.

## بعد الإصلاح
- **`ScaleBarcodeConfig`** في `lib/presentation/pos/services/scale_barcode_config.dart` (نقي، بلا Flutter/DB/tr) هو مصدر واحد لما يلي:
  - المفاتيح والافتراضات المطابقة للمحلّل، مع احتياط المفاتيح القديمة.
  - `toSettings` للحفظ و`fromSettings` للقراءة.
  - `validate()`: البادئة أرقام فقط، تبدأ بـ2، من 1 إلى 4 خانات. خانات PLU تترك خانة قيمة واحدة على الأقل من 12. المعامل قوة للعشرة (1…100000)، ويقبل «1000.0» كما يقبله المحلّل.
  - **منع التعارض:** يُرفض تساوي بادئتي الوزن والسعر أو بدء إحداهما بالأخرى، وكذلك تداخل البادئة البديلة مع بادئة السعر. يُفحص هذا حتى لو كان ملف السعر معطّلاً، لأن المحلّل يفحص بادئة السعر دائماً.
  - `encode()` و`sample()` للمعاينة.
- **`ScaleBarcodeSettingsPanel`** في `lib/presentation/widgets/settings/` يعرض:
  - الحالة، ومفتاحَي «تفعيل باركود الوزن» و«تفعيل باركود السعر (المجموع)».
  - **كل الحقول ظاهرة دائماً:** البادئة، خانات PLU، معامل القسمة مع «الدقة: n منازل عشرية»، خانات القيمة المشتقة، والبادئة البديلة للوزن.
  - سطر يشرح خانة التحقق، وقائمة أخطاء.
  - **معاينة حية** لباركودَي EAN-13 مثالين: «منتج تجريبي PLU 12345، وزن 1.234 كجم»، و«إجمالي 12.34» للسعر. المعاينة ترسم القضبان (`ean13_modules.dart`، جداول GS1) وتعرض الأرقام مقسّمة [بادئة][PLU][قيمة][تحقق].
  - زر «حفظ» صريح، معطّل عند الخطأ أو عند عدم وجود تغيير، مع سجل التدقيق المنقول. الحقول تقبل أرقاماً فقط (`digitsOnly`).
- `_ScaleBarcodeSettings` في PicPos صار غلافاً للوحة، وفي رأس الملف تعليق يشرح أن المنطق نُقل ولم يُحذف.
- الشاشة القديمة لـUralCash (`screens/settings/scale_barcode_settings.dart`) لم تتغير إلا في الافتراض `22 → 20`، مع تعليق. ملفها الأم `settings_screen.dart` في سقف ratchet (62826)، فلا يتسع لسطر استيراد اللوحة.
- **حوار الطباعة:**
  - «ملصق ميزان» عنصر في قائمة القوالب نفسها. اختياره يُظهر حقل الوزن ومقاس 58×40، وأي قالب آخر يخفيه. قائمة «مقاس الملصق: قياسي/الميزان» المكررة وُحّدت فيها، مع تعليق في الكود.
  - حين لا يُتاح، يبقى ظاهراً لكنه **معطّل** باسم «ملصق ميزان (غير متاح)»، ونص `scale_label_unavailable_hint` يشرح السبب. منطق الإتاحة في `scale_label_availability.dart`، والأسباب: صنف غير موزون، أكثر من صنف موزون، صنف بلا PLU، الإعداد غير مفعّل (مع المسار: الإعدادات ← الأجهزة والطباعة ← باركود الميزان)، إعداد غير صالح، القالب غير موجود.
  - الترميز يمر عبر `ScaleBarcodeConfig.encode`، أي القراءة نفسها التي تقوم بها شاشة الإعداد.
  - `BarcodePrintDialog` يقرأ كل `ScaleBarcodeConfig.readKeys` **عند كل فتح**، فتفعيل الإعداد يظهر في القائمة عند إعادة فتح النافذة.
  - `didUpdateWidget` يلغي اختيار الميزان إن أُطفئ الإعداد والحوار مبني.

## (3) تعريف الصنف «موزون» وPLU — الواجهة تتيحه
- العمودان: `products.is_sold_by_weight` (bool) و`scale_plu_number` (int nullable)، ومعهما `scale_type` (count/weight/weightByPiece/display).
- لا يوجد مفتاح «موزون» مستقل. يُشتق من محدد النوع (`SegmentedButton`: عدد / **ميزان** / ميزان بالحبة / عرض) في:
  - `product_edit_dialog.dart:930-958` (حفظ: `isSoldByWeight = weight || weightByPiece`، الأسطر 1229-1271)
  - `add_product_dialog.dart:~595-637`
- حقل «رقم PLU» يظهر فقط عند ميزان/ميزان بالحبة (`product_edit_dialog.dart:959-975`، `add_product_dialog.dart:638-654`)، ويُحفظ `null` إن تُرك فارغاً.
- شاشات PicPos تستخدم الحوارين نفسيهما (`products_picpos_screen.dart:89`، `products_table_picpos.dart:1042`).
- لا تعيين تلقائي لـPLU في النموذج. `getNextAvailableScalePlu()` غير مستدعاة، والتعيين الجماعي في مدير PLU القديم فقط.
- حوار الطباعة يستخدم `scalePluNumber ?? int.tryParse(code)`. صنف موزون بلا PLU يُظهر سبب «الصنف بلا رقم PLU».

## الملفات
- جديدة:
  - `lib/presentation/pos/services/scale_barcode_config.dart`
  - `lib/presentation/pos/services/ean13_modules.dart`
  - `lib/presentation/widgets/settings/scale_barcode_settings_panel.dart`
  - `lib/presentation/widgets/settings/scale_barcode_preview.dart`
  - `lib/presentation/screens/products/widgets/scale_label_availability.dart`
- معدّلة:
  - `scale_barcode_settings_picpos.dart`
  - `settings_picpos_screen.dart` (سطر استيراد؛ 26932 بايت < 30720)
  - `scale_barcode_settings.dart` (الافتراض)
  - `barcode_label_batch_dialog.dart` (26349 بايت < 30720)
  - `barcode_print_dialog.dart`
  - `assets/i18n/en.json` (40 مفتاحاً أُلحقت في آخره)
- اختبارات:
  - جديدة: `test/unit/scale_barcode_config_test.dart` و`test/widget/scale_barcode_settings_panel_test.dart` و`test/widget/scale_label_print_flow_test.dart`.
  - معدّل: `test/widget/scale_barcode_label_dialog_test.dart`، أُضيف `scale_weight_enabled=true` واستُبدل مفتاح القائمة المزالة.
- لم يُرفع أي سقف في `file_size_baseline.txt`، ولم تُضف استيرادات `data/database` في presentation.

## التحقق
- `Invoke-FlutterTest` (أي `flutter test --concurrency=1 --dart-define=APP_BRAND=picpos` بعد `Clear-SqliteLock`) على:
  - `test/unit/scale_*_test.dart` (8 ملفات)
  - `scale_barcode_settings_panel_test`، `scale_label_print_flow_test`، `scale_barcode_label_dialog_test`، `barcode_label_batch_dialog_test`، `picpos_scale_plu_test`، `test/services/scale_barcode_handler_test`
  - الحراس الستة: `file_size_ratchet_test`، `i18n_coverage_test`، `i18n_runtime_safety_test`، `dark_mode_guard_test`، `analytics_parity_test`، `presentation_db_import_guard_test`

  النتيجة: **`+92: All tests passed!`**. بعد تعديل `const` في `scale_barcode_config_test` أُعيد تشغيل ذلك الملف وحده: `+6: All tests passed!`.
- اختبار التدفق `scale_label_print_flow_test` يغطي:
  - إعداد مفعّل + منتج موزون PLU 12345: «ملصق ميزان» متاح، والتبديل عبر القائمة يُخفي حقل الوزن ويعيده. وزن 1.234 ⇒ الباركود المعروض = `ScaleBarcodeEncoder.encode(prefix: '23', …)`. «طباعة» تمرر القالب والبند بـ`scaleBarcode` نفسه. ثم `labelSampleForItem` ⇒ `printBarcodeWithTemplate(debugBuildOnly: true)` على قالب البذرة الحقيقي ⇒ `%PDF-` و MediaBox = 58×40mm.
  - إعداد غير مفعّل ⇒ الخيار معطّل والنص يحتوي «فعّله من الإعدادات». إعادة البناء بإعداد مفعّل ⇒ يُتاح. إطفاؤه مجدداً ⇒ يُلغى الاختيار.
  - صنف غير موزون ⇒ «ملصق ميزان (غير متاح)» مع «للأصناف المباعة بالوزن فقط».
  - صنف موزون بلا PLU ⇒ سبب PLU.
- `scale_barcode_config_test` يغطي حلقة كاملة عبر `ScaleBarcodeHandler` بإعداد مخصص (23/5/1000) ⇒ PLU 12345 ووزن 1.234، والتحقق والتعارض، وجدول EAN-13 على `4006381333931`.
- `flutter analyze lib`: **2 issues**، وهما فقط `use_build_context_synchronously` القديمتان (`purchase_returns_picpos_logic.dart:48`، `sales_returns_picpos_logic.dart:84`). `flutter analyze` على ملفات الاختبار الأربعة: No issues.

## قيود وملاحظات
- **لم يُجرَ تحقق حي** على الحزمة المنشورة (لم يُعَد البناء). يلزم بناء جديد ثم جولة UI: الإعدادات ← الأجهزة والطباعة ← باركود الميزان، ثم حوار طباعة صنف موزون.
- مؤشر التفعيل يحكم الآن ملصق الميزان فقط. قراءة باركود الميزان في البيع ما زالت دائمة كما كانت، فلم أغيّر سلوك POS.
- حوار إعداد مدمج آخر يكتب المفاتيح نفسها بلا تحقق: `scale_plu_picpos/screens/scale_logic_picpos.dart:808-825` (والأصل `scale_plu/scale_logic.dart`)، ويكتب طولاً واحداً للوزن والسعر. لم أعدّله (خارج النطاق). يُقترح لاحقاً أن يستخدم `ScaleBarcodeConfig.validate`.
- `test/unit/scale_barcode_label_pdf_test.dart` (اختبار سابق) يعيد كتابة `docs/plans/scale_label_2026-11-03/scale_label_preview.pdf` عند كل تشغيل. يظهر الملف معدّلاً في `git status` (الحجم نفسه 10170). لم أُرجعه لأن ذلك يتطلب `git checkout`.
- `assets/i18n/en.json` كان معدّلاً من عامل آخر أثناء العمل. أضفت مفاتيحي في آخره فقط ولم ألمس سطوره. ملفات `pos_picpos` و`print_test_picpos/sheet_preview_view.dart` المعدّلة في الشجرة ليست لي.
- انهار `flutter test` مرة بسبب `PathExistsException` على `sqlite3.dll`، وهو سباق مع العاملين الآخرين، فكتب `flutter_03.log` في الجذر. حذفته بعد التحقق من أنه من تشغيلي. أما `flutter_01.log` و`flutter_02.log` فليسا لي وبقيا.
