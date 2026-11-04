# دراسة: الإعداد الأول وإعدادات المطوّر والبيع بالسالب والملصقات والنماذج (البنود 8–13)

> دراسة قراءة فقط. لم يُعدَّل أي ملف شيفرة ولم تُشغَّل الاختبارات ولا التطبيق.
> أرقام الأسطر مأخوذة من القراءة الساكنة وقت الدراسة؛ تُراجَع قبل التنفيذ.
> تجاهل نسخ `.claude/worktrees/*` المكررة عند أي بحث.

---

## 8) «شامل» يفتح على «لايت»

### المسار كما هو في الكود
| المرحلة | الموضع |
|---|---|
| اختيار الباقة في المعالج (الافتراضي `pos`) | `lib/presentation/screens/first_run/steps/step_company.dart:58-67`، الافتراضي `lib/domain/models/first_run/first_run_draft.dart:192` |
| خريطة الباقة→ملف النشاط (`full`→`unified`، `pos`→`lite`) | `lib/domain/models/first_run/first_run_packs.dart:11-15` (التعليق يقول «مبدئي بانتظار تأكيد المالك E2») |
| المستقل (standalone): تحويل المسودة | `first_run_finish.dart:38-39` |
| المستقل: الحفظ عبر الكاش | `setup_wizard/setup_finish_runner.dart:265` ← `setup_persistence_riverpod.dart:38-39` |
| الإنهاء وإعادة تحميل الكاش | `first_run_finish_tail.dart:35-56` ← `core/config/business_profile_provider.dart:409-428` |
| مسار HQ/فرع: يكتب في قاعدة **الخادم** | `first_run_finish_server.dart:28-41,113-132` ← `services/setup/server_setup_writer.dart:235` (`db.setSetting` مباشرة) |
| القراءة عند الإقلاع | `main.dart:848-880` ثم `BusinessProfileNotifier.build()` في `business_profile_provider.dart:54-64` |
| أين يظهر «لايت» | fallback إلى `AppConfig.profile` في `business_profile_provider.dart:59,63` ← `core/config/app_config.dart:115-129` ← `Brand.defaultProfileCode='lite'` في `core/config/brand.dart:~181` |
| `runtime_config_hash` | يُكتب فقط (`business_profile_provider.dart:454`) ولا يُقارَن به أي شيء في أي مكان؛ لا علاقة له بضياع الاختيار |
| شاشات كل ملف | `core/navigation/screen_registry.dart:531-558` و`feature_policy.dart:238-264` (فرع `Brand.isPicPos` للايت عند 243) |

### الحكم
- **لم أجد سبباً جذرياً مؤكداً.** مسار المستقل يبدو سليماً: `full→unified` يُكتب عبر الكاش ثم يُعاد تحميله، ولا يوجد تعارض في أسماء الـ enum.
- **فرضية 1 (الأرجح — متوسطة الثقة): مسارا HQ والفرع.** `business_profile` يُكتب في قاعدة الخادم فقط (`server_setup_writer.dart:235`)، أما النسخة المحلية فيُكتب فيها اسم الشركة فقط (تعليق `first_run_finish_server.dart:119`). عند الإقلاع المحلي يغيب المفتاح فيسقط إلى `lite` (افتراضي PicPos). ولم أتحقق من أن مزامنة الإعدادات تجلب `business_profile` للنسخة المحلية؛ `setting_sync_strategy.dart` لا يتناوله صراحةً.
- **فرضية 2:** المستخدم اختار بطاقة «النظام الكامل» لكن المسودة المستعادة تُسقِط `pack` إلى `pos` عند قيمة غير مفهومة (`first_run_draft.dart:~468`). تحتاج فحص حفظ/استعادة المسودة (`first_run_draft_store.dart`).
- **فرضية 3:** فشل `rehydrateRuntimeConfigCache` يُبتلع كتحذير فقط (`first_run_finish_tail.dart:54-56`) فيبقى الكاش القديم حتى إعادة التشغيل.
- **فرضية 4:** مسح لاحق للمفتاح (`provisioning_reset.dart`, restore) أو كتابة `changeProfile` (`business_profile_provider.dart:277-281`) من مزامنة/إعادة تهيئة. لم تُقرأ الملفات.
- **فرضية 5:** الدلالة: المستخدم يقصد «شامل» وهو لا يطابق نصاً في الواجهة (النص «النظام الكامل» و«نقطة بيع + محاسبة + مستودعات»). إن اختار الثانية فالناتج `supermarket` لا `lite` — يستبعد هذا التفسير إلا إن كان العنوان مضلّلاً.
- **خطوة تشخيص أولى (قبل أي إصلاح):** بعد إنهاء المعالج مباشرة وبعد إعادة التشغيل، استعلم عن `settings.business_profile` في القاعدة المحلية (وفي قاعدة الخادم لو HQ). `unified` في الحالتين ⇒ العطب في السياسة/التنقل؛ `lite` أو فارغ ⇒ العطب في الكتابة/المسودة. كذلك اسأل المستخدم أي مسار استعمل (مستقل/مقر/فرع).

### الإصلاح المقترح (بعد التأكيد)
1. مسار HQ/فرع: كتابة `business_profile` (وملحقاته `feature.*`) أيضاً في النسخة المحلية عبر `saveCachedSetting` قبل `runFinishTail`، أو تمريرها من `ServerSetupWriter` عبر الكاش، ثم تأكيد أن مزامنة الإعدادات لا تستبدلها.
2. جعل فشل `rehydrateRuntimeConfigCache` يمنع/يحذّر بوضوح بدل تحذير صامت.
3. عدم إسقاط `pack` غير المفهوم إلى `pos` بصمت؛ تسجيل تحذير ورفض الاستعادة.
4. سجل تشخيصي عند سقوط `BusinessProfileNotifier.build()` إلى الافتراضي (يقتضي لمس `business_profile_provider.dart` — منسَّق مع البند 9، انظر الخطة).
5. بند إضافي في شاشة المراجعة (`step_review.dart`) يعرض ملف النشاط الناتج.

### المخاطر
- تغيير fallback يؤثر على أول إقلاع لكل PicPos. تغيير ترتيب الكتابة يمس منطق `setup_completed` والاسترداد.
- كتابة محلية مزدوجة قد تتعارض مع المصدر الحاكم (الخادم) في مرحلة المزامنة (ADP-006).

### الاختبارات المطلوبة
- معالج مستقل بباقة `full` ثم إقلاع بارد ⇒ `businessProfileProvider == unified` (اختبار `test/widget/first_run/first_run_standalone_flow_test.dart:44` يؤكد `lite` للباقة الافتراضية فقط؛ لا تغطية لـ `full`).
- نفس الاختبار لمسار HQ وفرع بقاعدتين.
- دورة حفظ/استعادة المسودة تحافظ على `pack`.
- فشل `rehydrate` يُظهر تحذيراً.
- اختبار على أن الافتراضي PicPos لا يطغى على قيمة مخزّنة.

---

## 9) كلمة مرور المطوّر لا تُطلب في الجلسة الجديدة

### الحالة الفعلية
- حالة الفتح **في الذاكرة فقط**، ليست static ولا في prefs/settings: `DeveloperSession`/`DeveloperSessionNotifier`/`developerSessionProvider` في `lib/core/config/business_profile_provider.dart:225-267` (نافذة منزلقة 10 دقائق عند ~239، البداية مقفلة عند ~242).
- الفتح: `lib/presentation/screens/developer_tools_screen.dart:104` (بعد `auth.verify`) و`:137` (بعد `setPassword`). التمديد `extend()` عند كل تعديل إعداد: `business_profile_provider.dart:288,302,314,362,388` و`developer_tools_screen.dart:813`.
- القراءة: `developer_tools_screen.dart:151-157` (`DeveloperPasswordGate`)، والشاشة الثانية `settings_picpos/screens/developer_tools_picpos_screen.dart:77`.
- المسح `clear()`: **فقط** من زر «إنهاء الجلسة» (`developer_tools_screen.dart:302`، `developer_tools_picpos_screen.dart:71`).

### السبب الجذري
`AuthNotifier.logout()` (`lib/data/providers/auth_providers.dart:474-495`) ينظّف جلسات الخادم وكاش موافقة المدير ولا يلمس `developerSessionProvider`. والـ provider يعيش في `ProviderScope` الجذري فلا يُعاد بناؤه عند الخروج. الصلاحية تنتهي بالوقت فقط ولا ترتبط بهوية مستخدم/جلسة. وبما أن النافذة منزلقة فكل تعديل يمددها، فمن يعمل متتابعاً يبقى مفتوحاً.

> تحفظ: لم أجد أي مسار تخزين على القرص يفسّر بقاء الفتح بعد **إعادة تشغيل التطبيق**. إن حدث هذا فعلاً فالأرجح hot restart/عدم إعادة بناء الـ scope، أو الدخول من شاشة لا تمر عبر `DeveloperPasswordGate` (مثال: `fiscal_year_gate_dialog.dart:110` و`fiscal_year_screen.dart:619` يستعملان `developerAuthServiceProvider` — لم يُفحص مسارهما). يجب إعادة الإنتاج قبل الجزم.

### الإصلاح
1. مسح الجلسة عند الخروج وعند أي تغيّر لمعرّف المستخدم/الجلسة: الأنظف `ref.listen` على حالة المصادقة داخل `DeveloperSessionNotifier.build()` يمسح عند التحول إلى غير مصادَق أو تغيّر `userId` (يغطي انتهاء الجلسة التلقائي أيضاً)، مع استدعاء مباشر `clear()` في `logout()` كحزام ثان.
2. إضافة `userId`/`sessionId` إلى `DeveloperSession` ومقارنته في `isActive`.
3. اختياري: مهلة مطلقة `maxExpiresAt` لا يمدّها `extend()`، ومسح عند `paused` طويل.
4. تدقيق كل مواضع استعمال `developerAuthServiceProvider` للتأكد من مرورها عبر البوابة نفسها.
5. إبقاء الحالة في الذاكرة فقط.

### المخاطر
- المسح على أي تغيّر في حالة المصادقة (تجديد token) سيقفل أثناء العمل: قارن بالمعرّف لا بالحالة.
- المسح أثناء فتح الشاشة يفقد نموذجاً غير محفوظ.

### الاختبارات
- وحدة: unlock ⇒ active؛ clear ⇒ غير active؛ انتهاء بعد 10 دقائق (ساعة وهمية)؛ `extend` لا يعمل على مقفلة.
- تكامل: افتح ثم `logout()` ⇒ غير active؛ دخول مستخدم آخر ⇒ يبقى مقفلاً.
- widget: `DeveloperPasswordGate` بعد logout تُظهر حقل كلمة المرور.
- ساكن (على نمط `test/static/settings_unified_header_test.dart:134`): مسار الخروج يستدعي مسح جلسة المطوّر.

---

## 10) حذف مجموعات التصنيفات من إعدادات المطوّر

### الموجود
- شاشة المطوّر `developer_tools_picpos_screen.dart:23` لا تذكر التصنيفات إطلاقاً.
- الحذف موجود لكن في شاشة التصنيفات العادية: `presentation/categories_picpos/screens/categories_picpos_screen.dart:454` (تأكيد بسيط عند 0 منتج `:530`، و«نقل وحذف» عند ≥1 `:588`، تحذير الفرع `:504`، سجل `logCategoryDelete` `:747`). الشاشة القديمة المكررة `presentation/screens/categories_screen.dart:712`.
- الطبقات: `categories_controller.dart:186` ← `domain/repositories/i_products_repository.dart:155-166` ← `drift_product_repository.dart:440-454` (الويب فارغ `web_product_repository.dart:197-206`) ← DAO `data/database/daos/product_crud_dao.dart:961` (حذف **ناعم** في معاملة: ينقل المنتجات النشطة إلى وجهة أو NULL، `isActive=false`، `deletedAt`، `lastModifiedAt`). عدّادات `countActiveProductsInCategory :856` و`countCategoryInvoicedItemsOnBranch :875`.
- الجدول `Categories` (`data/database/tables/product_tables.dart:21`): `parentId :28`، `isActive :30`، `isLocked :31`، `globalId :46`، `isSystemDefault :48`، `lastModifiedAt :49`، `deletedAt :50`، `rowVersion :52`. روابط: `CategoryBranches :56`، `Products.categoryId :77`، `kitchen_tables.dart:109`.
- المزامنة: العميل عبر outbox `services/interceptor/cwi_catalog_operations.dart:379`؛ الخادم `DELETE /api/categories/<id>` في `services/api/routes/api_routes_write.dart:101` ← `api_data_inventory.dart:220` (صلاحية `categoriesDelete`)؛ `services/sync/strategies/category_sync_strategy.dart:79` يحترم `isActive=false`.

### الثغرات الحالية
1. لا حارس على الأبناء (يبقى `parentId` يشير إلى معطَّل).
2. العدّ للمنتجات **النشطة** فقط؛ غير النشطة تبقى مربوطة بمحذوف.
3. لا فحص `isSystemDefault`/`isLocked` داخل الحذف.
4. الوجهة قد تكون من النسل أو معطلة (يُمنع الاختيار الذاتي فقط، `:965`).
5. لا تنظيف `CategoryBranches` ولا روابط المطبخ.
6. نقل المنتجات لا يحدّث `lastModifiedAt/rowVersion` لها ⇒ قد لا تنتشر بالمزامنة (غير مؤكد).
7. السجل `unawaited` بلا أعداد/وجهة. لا حارس على مستوى DAO.

### التصميم المقترح
1. **قسم «مجموعات التصنيفات»** في أدوات المطوّر (داخل بوابة كلمة مرور المطوّر): شجرة بعدد المنتجات (نشط/غير نشط)، الأبناء، حركات الفواتير.
2. `analyzeCategoryDelete(id)` في DAO: يعيد مجموع المنتجات في النسل (CTE عودي على `parent_id`)، الأبناء، الفواتير، روابط الفروع/المطبخ، الأعلام.
3. **رفض صلب:** `isSystemDefault`؛ `isLocked` إلا بفكّ صريح؛ وجهة = نفسه/نسله/معطّلة؛ أبناء بلا اختيار صريح («حذف الشجرة» أو «رفع الأبناء للأب»).
4. **حارس المنتجات:** إن وُجد منتج (نشط أو غير نشط) فالنقل لوجهة أو `NULL` إلزامي، مع تحديث `lastModifiedAt/rowVersion` للمنتجات.
5. **حذف ناعم** في معاملة واحدة، بلا حذف فعلي أبداً (`deletedAt` tombstone يمنع «عودة» التصنيف بعد المزامنة كما يوثّق تعليق DAO ~917-929).
6. **مزامنة:** عبر `ClientWriteInterceptor` مع `idempotencyKey`؛ ذرّية على الخادم؛ التأكد أن `CategorySyncStrategy` يمرّر `deletedAt` وأن الأبناء والمنتجات المنقولة تصل في الـ delta.
7. **تأكيد:** معاينة بالأعداد ← كتابة اسم التصنيف ← إعادة مصادقة المطوّر ← صلاحية `categoriesDelete` على الخادم.
8. **تدقيق:** سجل مُنتظَر (`await`) يحمل المنفِّذ و`globalId` والوجهة والأعداد ومعرّفات المنتجات المنقولة؛ مع إمكانية الاسترجاع (إعادة `isActive` ومنتجاتها).
9. الاستخدام الأمثل: استخراج الحذف الآمن إلى دالة DAO واحدة تستعملها الشاشة العادية والمطوّر، منعاً للازدواج (شاشتان قديمة/جديدة).

### المخاطر
- ترقيم `id` محلي/خادم مختلط (تعليق `category_sync_strategy.dart:39-54`)؛ سباق بين العدّ والحذف؛ مزامنة جارية تعيد `isActive=true`.
- اعتماد جهات على اسم/معرّف التصنيف: التقارير، `excel_service` (`getOrCreateCategory` بالاسم)، قوالب المطبخ والطباعة، تطبيق `mobile`.
- الويب لا ينفّذ شيئاً.

### الاختبارات
- DAO: فارغ؛ نشط/غير نشط؛ ثلاثة مستويات؛ وجهة غير صالحة؛ نظام/مقفل؛ تحديث `lastModifiedAt`؛ تراجع المعاملة كاملة عند خطأ.
- مزامنة: delta بعد الحذف لا يعيد الصف؛ إعادة تشغيل outbox مرة واحدة (idempotency).
- خادم: رفض بلا `categoriesDelete`.
- widget: أعداد المعاينة؛ تعطيل الزر حتى كتابة التأكيد؛ كتابة سجل التدقيق؛ استرجاع.

---

## 11) البيع بالسالب وتكلفة الصنف

### الوضع الحالي
- **لا توجد نافذة تسأل عن التكلفة عند البيع** (بحث بأنماط `CostPrompt`/`askCost`/«تكلفة…صفر» لم يجد، ولم تُفتح شاشات POS واحدة واحدة). ما يراه المستخدم هو **رفض الحفظ** بسبب `zero_cost_policy=block`: الرسالة «يرجى تحديث تكلفة الصنف أولاً» في `data/database/daos/sales_mutations_dao.dart:342-345`.
- `enable_negative_sales`: واجهة `presentation/widgets/settings/pos_settings_widget_main_section.dart:66` والتخزين `pos_settings_widget_storage.dart:7,296`؛ تعبئة افتراضية `negative_sales_default_backfill_extension.dart:24` (من `main.dart:651`)؛ مرآة `quick_sale_policy.dart:287`. علم الصنف `products.allowNegativeSale` (`product_tables.dart:122`). سياسة النقص `stock_shortage_policy_service.dart:31`.
- `ZeroCostPolicy {block, warn, allow}` في `journal_entry_factory.dart:68` (افتراضي factory `block` عند `:105`)؛ البذر `database_seeder.dart:173-183` = `block`؛ التحميل `accounting_service.dart:100-114`.
- **تناقض افتراضيات:** الـ DAO يقرأ `'warn'` عند غياب المفتاح في 3 مواضع (`sales_mutations_dao.dart:340` وما شابه) بينما البذر والـ factory `block`. قاعدة جديدة ⇒ block؛ قديمة بلا مفتاح ⇒ warn.
- **البوابة:** `sales_mutations_dao.dart:325-356` (التكلفة من `item.costPrice` أو `product.costPrice`؛ إن `saleType != 'return'` ويتتبع المخزون والتكلفة ≤ 0 تُطبَّق السياسة). السماح بالسالب: `sales_transaction_orchestrator.dart:259-305`، `inventory_dao.dart:210-214`، `cart_controller.dart:189,361`.
- **COGS:** لقطة `sales_invoice_items.cost_price` (`sales_mutations_dao.dart:357-364`) ← قيد `Σ cost×qty×qtyInBase` (`journal_entry_factory.dart:366`)؛ عند `warn/allow` وتكلفة 0 يُضاف 0 فلا COGS (`:347-366`، وهو FA-28 المفتوح في `docs/audit/2026-full-project-audit.md:126`). حركة البيع لا تمرّر `unitCost` (`sales_mutations_dao.dart:394`).
- **WAC:** `updateProductWAC` في `inventory_dao.dart:665-713` (إن `currentQty+newQty ≤ 0` تُعاد التكلفة لسعر الإيصال `:685-686`). تُستدعى من الشراء `purchase_dao.dart:379`، تعديل الشراء `purchase_update_dao.dart:350`، المرتجعات، التصنيع. **لا يوجد `last_cost`** في أي مكان.
- **تسوية الشراء:** `purchase_dao.dart:404-409` و`:633-659` تقيد فرق `negativeCoverage × (unitCost − costBeforeReceipt)` بين المخزون وCOGS في الأستاذ **فقط**، ولا تعدّل `sales_invoice_items.cost_price` القديمة ⇒ تقارير الربح (`sales_analytics_dao.dart:291,984,1375`) المبنية على اللقطة لا ترى التصحيح.
- ⚠️ ملاحظة غير محققة: اتجاه القيد عند `adjustment > 0` (`purchase_dao.dart:643-649`) يبدو معكوساً (ينقص COGS بينما التكلفة الفعلية أعلى). يلزم اختبار قبل البناء عليه.
- حالة غير مغطاة: رصيد صفر + بيع بتكلفة 0 ثم شراء ⇒ لا تسوية.

### مقارنة الخيارات
| الخيار | COGS | المخزون | التقارير | عند وصول الشراء |
|---|---|---|---|---|
| أ) السؤال عن التكلفة وقت البيع | يعتمد على إدخال الكاشير؛ تفاوت وأخطاء | الرصيد السالب يُقيَّم بما أُدخل | ربح مبني على رقم يدوي؛ يحتاج صلاحية/تدقيق | تسوية القيد تصحح الأستاذ فقط |
| ب) سعر البيع كتكلفة | ربح صفري على هذه الوحدات (مضلل) | تقييم السالب مرتفع | هامش مشوّه ثم خسارة ظاهرة لاحقاً | فرق كبير دفعة واحدة؛ يزعزع فترات مقفلة |
| ج) متوسط سعر الشراء | الأقرب للواقع والمتسق مع WAC الحالي (`products.costPrice` هو المتوسط أصلاً) | متسق مع المنهج القائم | الأعلى اتساقاً | فرق صغير. المشكلة: صنف لم يُشترَ قط أو رصيده سالب فتُعاد التكلفة عند أول إيصال (`inventory_dao.dart:685`) |
| د) آخر تكلفة | يتبع آخر سعر (يتقلب مع التضخم) | يخالف WAC | يحتاج حقل `last_cost` جديد + ترحيل مخطط وكتابته في `purchase_dao.dart:379` | فرق متوسط، وتعارض طريقتين |

### التوصية (مبدئية — لا تُحسم دون المالك)
سياسة **متدرّجة**: (1) متوسط الشراء/`products.costPrice` إن كان > 0 (خيار ج)؛ (2) وإلا **سؤال/تحذير** للصنف الذي بلا أي تكلفة عند أول بيع بالسالب، مع حفظ التكلفة المُدخلة كتكلفة مبدئية قابلة للتصحيح، وتعليم الأصناف في «تقرير الأصناف ذات التكلفة صفر» (`sales_dao.dart:903-909`)؛ (3) لا نستخدم سعر البيع كتكلفة افتراضياً؛ (4) تصحيح لقطة `cost_price` لسطور البيع السالب عند وصول الشراء (backfill) أو وسمها `provisional_cost` ليراها التقرير. وتوحيد افتراضي `zero_cost_policy` بين الـ DAO والـ seeder.

### أسئلة مفتوحة للمستخدم (للتأكيد)
1. ما الذي تريده بالضبط: **نافذة سؤال عند البيع** أم **عدم السؤال أبداً**؟ (الوضع الحالي رفض لا سؤال.)
2. عند صنف لم يُشترَ قط: نسأل الكاشير، أم نستعمل سعر البيع، أم نسمح بتكلفة صفر مع تحذير ونصحّح لاحقاً؟
3. هل تقبل تعديل `cost_price` المخزّنة في فواتير البيع القديمة عند وصول الشراء (backfill، يغيّر تقارير الربح التاريخية)، أم يكتفى بقيد التسوية في الأستاذ؟
4. هل نضيف «آخر تكلفة» كحقل مستقل (يتطلب ترحيل مخطط) أم نكتفي بالمتوسط المرجح؟
5. من يملك صلاحية إدخال/تعديل التكلفة عند البيع؟
6. ما الافتراضي المطلوب لـ `zero_cost_policy` (block أم warn)؟

### المخاطر والاختبارات
- مخاطر: فترات محاسبية مقفلة، اختلاف تقارير تاريخية، ترحيل مخطط لـ `last_cost`، تعارض مع الأجهزة المتزامنة.
- اختبارات: بيع سالب بكل خيار؛ قيد التسوية بتكلفة أعلى/أقل (يكشف سؤال الاتجاه أعلاه)؛ رصيد صفر ثم شراء؛ مرتجع؛ تقرير الربح قبل/بعد الـ backfill؛ توحيد الافتراضي.

---

## 12) ملصقات الباركود: مقاسات مخصصة وعدد نسخ مخصص

### الموجود
- **مساران:**
  1. بسيط (الأكثر استعمالاً): `presentation/screens/products/widgets/barcode_print_dialog.dart` (حقل «عدد النسخ» فقط `:26,63`) ← `services/invoice_generator.dart:776 printBarcodeLabel` ← `services/printing/report_pdf_generator.dart:1096`. المقاس **ثابت 50×25 مم وهامش 2 مم** (`:1104-1110`)، كل نسخة صفحة PDF مستقلة (`:1112`)، طباعة عبر `PdfComputeHelper.layoutPdf` (حوار النظام).
  2. بالقالب: `services/templated_invoice_service.dart:552 printBarcodeWithTemplate` ← `services/templated_invoice_service/template_barcode_labels.dart:6`. المقاس من `template.paperWidth/paperHeight` (`:42-45`)، وA4 متعدد الأعمدة بحساب تلقائي `floor` وهامش 10 مم ثابت وتباعد ثابت 2 (`:47-60`)، والطباعة المباشرة بغرض `barcode` (`:100-106`). **لا يُستدعى من أي شاشة** (ما وجدت إلا التعريف داخل `lib`؛ لم أبحث في `mobile`/`packages`).
- مصمم القوالب يتيح فئة «ملصقات الباركود» (`presentation/screens/invoice_designer/invoice_designer_ui.dart:369`)، وبذر 6 قوالب (`data/database/daos/invoice_template_seeder_dao.dart:1453-1732`). جدول `InvoiceTemplates` فيه `paperWidth/paperHeight` و`templateCategory='barcode'` (`tables/invoice_template_tables.dart:8,20-22`).
- استدعاءات أخرى لـ`printBarcodeLabel`: `offers_picpos/offer_dialogs_picpos.dart:196`، `offer_cards_picpos.dart:557`، `screens/offers/offer_dialogs.dart:201`، `offer_cards.dart:550`، `pos/widgets/cart/cart_auto_scroll.dart:227`، `screens/warehouse_locations_screen.dart:144`.
- الحزم: `pdf ^3.11.3`، `printing ^5.14.2` (`pubspec.yaml:54-55`). لا ZPL/TSPL في سطح المكتب؛ ESC/POS للموبايل فقط (`mobile/lib/printing/escpos.dart`, `mobile_warehouse/lib/printing/label_builder.dart`). غرض «طابعة الباركود» في `printers_screen.dart:297`.
- لا إعدادات ملصقات في `shared_preferences`.

### مقارنة بالبرامج المشابهة (معرفة عامة لم تُتحقق من مصادرها في هذه الدراسة)
- **Zebra Designer:** تصميم حر بمقاس الملصق وعدد النسخ وبيانات من قاعدة بيانات/ملف، وإخراج للطابعة الحرارية مباشرة.
- **ERPNext:** أداة Print Format/Barcode مع طباعة ملصقات بكمية، وقوالب HTML.
- **Odoo:** تقرير ملصقات المنتج بتنسيقات جاهزة (مثل 4×12، 4×7، 2×7 على A4، ومقاس 57×35 مم لأسطوانات) وعدد نسخ من الكمية أو 1/صنف، وخيار طباعة الباركود والسعر.
- **Dolibarr:** إعداد «Barcode print» لأوراق Avery وغيرها (أعمدة×صفوف، هوامش، مسافات، مقاس) ويمكن تعريف تنسيق مخصص.
- القاسم المشترك: **(1)** قائمة مقاسات جاهزة + مخصص، **(2)** تنسيق ورقة (أعمدة، صفوف، هوامش، تباعد، إزاحة بداية) وملصق بمقاس رول، **(3)** عدد نسخ لكل صنف، ومن الكمية/فاتورة الشراء، **(4)** حفظ التنسيقات كإعدادات مسبقة.

### الفجوات
1. المسار الفعلي لا يقبل أي مقاس غير 50×25.
2. عدد النسخ رقم واحد لصنف واحد؛ لا قائمة أصناف، ولا ملء من المخزون/فاتورة الشراء.
3. تخطيط A4 ثابت ويعمل بصنف واحد فقط، ولا يوجد إزاحة بداية (لأوراق مستعملة جزئياً).
4. المساران منفصلان؛ مسار القالب المرن مهجور.

### التصميم المقترح
- **جدول إعدادات مسبقة** `LabelPresets`: `id`, `globalId`, `name`, `kind` (`roll`|`sheet`), `widthMm`, `heightMm`, `columns`, `rows`, `marginTop/Left/Right/BottomMm`, `gapXMm`, `gapYMm`, `startOffset`, `showPrice/Name/Barcode`, `isDefault`, `isActive`. يحتاج ترحيل مخطط (ويُنسَّق مع أي مهاجرة أخرى في الخطة). البديل الأخف JSON في الإعدادات (لا يُزامَن).
- **مقاسات مبذورة:** رول 50×30، 50×25، 40×30، 40×25، 38×25، 30×20؛ A4: 3×7 (70×38)، 4×10، 5×13 (للأسعار الصغيرة)، ومخصص.
- **حوار طباعة جديد** (دفعي): جدول أصناف (إضافة من بحث/ملف/فاتورة شراء/جرد) بعمود «نسخ» لكل صنف + أزرار «نسخ = الكمية» و«نسخ = كمية الفاتورة» + اختيار الإعداد + معاينة.
- **مولّد PDF واحد** `LabelSheetRenderer` يعتمد على المقاس بالـ mm والأعمدة/الصفوف بدل الثوابت، ويستبدل `report_pdf_generator.dart:1096` تدريجياً، ويبقى `printBarcodeLabel` واجهة متوافقة (يتوجه للمولّد الجديد بالإعداد الافتراضي 50×25).
- ربط مسار القالب كخيار «تصميم متقدم» بدل الإهمال أو حذفه إن لم يُستعمل.

### المخاطر
- دقة الطابعة الحرارية: قياس PDF بالـ mm مقابل اقتطاع الطابعة؛ يلزم اختبار طابعة حقيقية.
- ترحيل مخطط وتوافق المزامنة مع الأجهزة الأقدم.
- تضخم عدد الصفحات عند نسخ كبيرة (ضبط حد).
- عناصر الباركود العربية (اتجاه RTL، الخط).

### الاختبارات
- وحدة: حساب شبكة A4 (أعمدة/صفوف/إزاحة) وعدد الصفحات من (عدد الملصقات، الإعداد).
- وحدة: التحقق من القيم (عرض/ارتفاع > 0، هوامش لا تتجاوز الورقة).
- golden/PDF: أبعاد الصفحة بالـ mm لكل إعداد.
- widget: الحوار الدفعي، وملء النسخ من كمية فاتورة الشراء.
- تكامل: الحفظ والاستعادة من `LabelPresets`، والمسارات القديمة (العروض، السلة) ما زالت تعمل.
- يدوي: طباعة على طابعة حرارية فعلية.

---

## 13) «مكتبة النماذج» مقابل «مصمم الفواتير»

### العلاقة الحالية
**مخزن واحد وليس اثنين.** كلا الشاشتين تقرآن/تكتبان نفس الجداول `invoice_templates` و`invoice_template_elements` و`invoice_table_settings` و`template_bindings` (`data/database/tables/invoice_template_tables.dart`، `TemplateBindings :184`)، عبر `invoice_template_dao.dart` و`template_binding_dao.dart` و`invoice_template_seeder_dao.dart`. الفرق في **الشكل** (`layout_version`): 1 = تدفق قديم (`sortOrder/flexWidth`)، 2 = نطاقات بإحداثيات mm. و`domain/printing/template_mapper.dart` يحوّل بين الشكلين.

| | مصمم الفواتير (قديم) | مكتبة النماذج + المحرر (الجديد) |
|---|---|---|
| الدخول | `settings_picpos_tiles.dart:187` | `settings_picpos_tiles.dart:148`, `settings_screen.dart:535` |
| الشاشة | `presentation/screens/invoice_designer/invoice_designer_templates.dart` | `TemplateLibraryPicposScreen` + `TemplateEditorPicposScreen` |
| الحفظ | مباشر عبر `updateTemplate` (`:108,193`)، يكتب العناصر صفوفاً v1 | `template_editor_providers.dart:400` ← `invoice_templates_repository_impl.dart:116` ← `template_layout_writer.dart:36` في معاملة، يرفع `layout_version=2` (`:49,56`) |
| الافتراضي | «تعيين كافتراضي» `:322` ⇒ `setDefaultTemplate` يضبط علَم `is_default` العالمي فقط (`invoice_template_dao.dart:130`) | «تفعيل لنوع مستند» (`template_editor_picpos_screen.dart:304-310`) ⇒ upsert في `template_bindings` |

### ما يُستعمل فعلاً عند الطباعة (إيصال POS)
1. `printInvoice(id)` من `picpos_pos_checkout_support.dart:89` و`picpos_pos_invoice_actions.dart:209` ← `pos_controller.dart:237-238` ← `printingService.printReceipt`.
2. `printing_service.dart:249` يتحقق `hasDefaultTemplate(db,'thermal',category:'receipt')` (`templated_invoice_service.dart:104-113`) — **علَم `is_default` فقط، لا يقرأ الروابط**. إن لم يوجد افتراضي بهذه الفئة يسقط إلى المولّد الثابت `thermal_receipt_generator.dart` مهما كانت الروابط.
3. وإلا `printWithTemplate(documentType:'sales_receipt')` (`printing_service.dart:274,296`) ← `template_resolution.dart:17 _resolveTemplate` ← `resolveTemplateFor` (`:27`) ← `template_binding_dao.dart:159-211` ← `TemplateResolver.resolve` (`services/printing/template_resolver.dart`، سلسلة 7 مستويات: المستوى 5 مزلاج البيع السريع، 6 الافتراضي بالفئة).
4. `templated_invoice_service.dart:246`: `layoutVersion >= kBandLayoutVersion` ⇒ `TemplateRenderPipeline.render` (`:252`)، وإلا المسار القديم المتدفق.
5. نفس النمط في `invoice_generator.dart` (`213,303,401,471,591`) و`shift_closing_print.dart:33`.
- أنواع المستندات الموصولة فعلاً: `TemplateResolver.wiredDocumentTypes` (`template_resolver.dart:177`): `sales_invoice`, `sales_return`, `purchase_invoice`, `purchase_return`, `sales_receipt`, `kitchen_order`, `shift_closing`, `party_statement`. **غير موصولة:** `quotation` و`report` (التقارير تمر بـ`report_pdf_generator.dart` بلا قوالب).

### الخلاصة
- النموذج المستعمل فعلاً = صف `invoice_templates` الذي يحدده المحلّل (روابط ثم الافتراضي بالفئة)، بصرف النظر عن الشاشة التي أنشأته.
- **الخطر الفعلي:** مفهومان للافتراضي (`is_default` مقابل `template_bindings`)؛ المصمم القديم يكتب الأول والمحرر الجديد يكتب الثاني، والبوابة `hasDefaultTemplate` تتحقق من الأول فقط. فمن يربط قالباً بنوع مستند ولا يملك افتراضياً بالفئة يُطبع بالمولّد الثابت بلا أي رسالة.
- مساران للحفظ لا يضمنان اتساق `layout_version` وجداول الأعمدة؛ وجهتا استيراد من `assets/invoice_templates/*.json` (`invoice_designer_templates.dart:465` و`new_template_sheet.dart:141`).
- ازدواجيات شاشات (`screens/settings_screen.dart` مقابل `settings_picpos`)؛ كود المولّدات الثابتة ليس ميتاً (احتياطي) ولم يُتحقق من استدعاءات الشاشات القديمة.

### اقتراح التوحيد
1. كيان واحد في الواجهة «النماذج»؛ المصمم القديم يصبح «تحرير متقدّم/قديم v1» داخل المكتبة مع زر «ترقية إلى النطاقات» (`template_migration.dart:134`)، ويُخفى بلاط «مصمم الفواتير» (`settings_picpos_tiles.dart:187`) أو يُحوَّل لفتح المحرر الجديد.
2. إزالة «تعيين كافتراضي» من المصمم (`invoice_designer_templates.dart:322`) وتوجيهه إلى «تفعيل لنوع مستند» الذي يكتب الرابط.
3. جعل `hasDefaultTemplate` يستعمل `resolveTemplateFor` (أو الروابط) حتى لا تُتجاهل الروابط.
4. في المكتبة: شارة لكل نموذج «يُطبع فعلاً لـ…/غير موصول» من `wiredDocumentTypes`، وشارة v1 (جزئية في `template_gallery_card.dart:61`)، وتنبيه عند ربط نوع غير موصول.
5. نص مساعد في الواجهة يشرح: المكتبة = تخزين وتفعيل، المحرر = تصميم.

### المخاطر والاختبارات
- مخاطر: عملاء يعتمدون على `is_default` الحالي؛ ترحيل قوالب v1 قد يغيّر شكل الطباعة؛ لا تُحذف المولّدات الثابتة الاحتياطية.
- اختبارات: ربط قالب بدون افتراضي ⇒ يُستعمل القالب لا المولّد الثابت؛ معاملة الحفظ من المصمم تحافظ على `layout_version`؛ تحويل v1→v2 بصرياً (golden)؛ شارات «غير موصول»؛ سلسلة المحلّل بالمستويات.

---

## خطة التنفيذ

### الترتيب (حسب المخاطرة والاعتماد)
1. **بند 9** (قفل المطوّر) — أمني، صغير، بلا اعتماد.
2. **بند 8** — يبدأ بخطوة التشخيص وإعادة الإنتاج، ثم الإصلاح.
3. **بند 13** — إصلاح `hasDefaultTemplate` أولاً (نقطة خطر فعلية)، ثم توحيد الواجهة.
4. **بند 10** — حذف التصنيفات الآمن.
5. **بند 12** — الملصقات (يحتاج ترحيل مخطط).
6. **بند 11** — بعد إجابة المالك على الأسئلة؛ لا يبدأ قبلها.

### المهام المستقلة وملفاتها (لا تقاطع)
| المهمة | الملفات الحصرية | ملاحظات |
|---|---|---|
| **T9** قفل المطوّر | `core/config/business_profile_provider.dart` (القسم 225-267 + سطر fallback اختياري)، `data/providers/auth_providers.dart`، اختبارات جديدة `test/.../developer_session_*` | تملك `business_profile_provider.dart` وحدها؛ T8 لا تلمسه |
| **T8** الباقة/الملف | `presentation/screens/first_run/first_run_finish_server.dart`، `first_run_finish_tail.dart`، `services/setup/server_setup_writer.dart`، `first_run_draft.dart`/`first_run_draft_store.dart`، اختبار `test/widget/first_run/*` | بعد التشخيص؛ سجل تحذير fallback يُؤجَّل إلى T9 (نفس الملف) |
| **T13** النماذج | `services/printing/printing_service.dart`، `services/templated_invoice_service.dart` (`hasDefaultTemplate` فقط)، `presentation/screens/invoice_designer/invoice_designer_templates.dart`، `settings_picpos/screens/settings_picpos_tiles.dart`، `template_library_picpos/*` | ينفرد بـ `settings_picpos_tiles.dart` |
| **T10** حذف التصنيفات | `data/database/daos/product_crud_dao.dart`، `domain/repositories/i_products_repository.dart`، `drift_product_repository.dart`، `web_product_repository.dart`، `presentation/products/providers/categories_controller.dart`، ملف جديد `settings_picpos/widgets/developer_categories_section.dart`، سطر إدراج في `developer_tools_picpos_screen.dart` | لا ترحيل مخطط |
| **T12** الملصقات | `services/printing/report_pdf_generator.dart` (دالة الملصق)، `services/invoice_generator.dart` (`printBarcodeLabel`)، `barcode_print_dialog.dart`، ملفات جديدة (`label_presets` جدول + DAO + dialog + renderer)، `data/database/tables/` الجديد | **حصرية** على مهاجرة المخطط في `app_database` |
| **T11** تكلفة البيع بالسالب | `sales_mutations_dao.dart`، `journal_entry_factory.dart`، `accounting_service.dart`، `purchase_dao.dart`، `pos_settings_widget_*`، (و`last_cost` ترحيل مخطط إن اعتُمد) | **محظورة حتى جواب المالك**؛ إن تطلبت ترحيلاً تُجدول بعد T12 كي لا تتزاحم المهاجرات |

### قواعد التنسيق
- مهاجرة مخطط واحدة في كل مرة (T12 ثم T11 إن لزم).
- `business_profile_provider.dart` ملك T9 فقط.
- `settings_picpos_tiles.dart` ملك T13 فقط؛ T12 لا يضيف بلاطاً فيه (يُفتح الحوار من الحوار الحالي).
- `developer_tools_picpos_screen.dart` ملك T10؛ T9 لا يغيّره (الإصلاح في الـ provider).
- كل مهمة تنتهي باختباراتها المذكورة أعلاه قبل الدمج.

### أسئلة مفتوحة إجمالاً
1. (8) أي مسار إعداد استُعمل (مستقل/مقر/فرع)؟ وما نص الخيار الذي اختاره بالضبط؟ وهل يتكرر بعد إعادة التشغيل؟
2. (9) هل الفتح بقي بعد **إغلاق التطبيق وإعادة تشغيله** فعلاً أم بعد تسجيل خروج/دخول فقط؟ وهل المطلوب مهلة مطلقة؟
3. (10) عند حذف تصنيف له أبناء: حذف الشجرة أم رفع الأبناء؟ وهل يُسمح بحذف تصنيف يحوي منتجات (بنقلها) أم الرفض الصلب؟
4. (11) الأسئلة الست في بند 11.
5. (12) هل يلزم دعم طابعات حرارية مباشرة (ZPL/TSPL) أم يكفي PDF؟ وما المقاسات الشائعة لديكم؟
6. (13) هل نُخفي «مصمم الفواتير» نهائياً أم نُبقيه كوضع متقدم؟
