part of 'database.dart';

// Top-level constants and raw-SQL single sources of truth (JE auto-post dedup
// index, multi-JE / investing / purchase reference types, dedup indexes for
// salary/attendance/bookings/bank-statement/import-purchase, e-invoice
// status log). Pure move out of database.dart.

// ═══════════════════════════════════════════════════════════════════════════
// Spec 151 — auto-post dedup UNIQUE index: single source of truth
// ═══════════════════════════════════════════════════════════════════════════
//
/// Name of the partial UNIQUE index that backstops duplicate auto-posted JEs
/// for the same `(reference_type, reference_id)` pair (originally added in the
/// v120 migration).
const String kJeAutopostDedupIndexName = 'idx_je_autopost_dedup';

/// Canonical CREATE statement for [kJeAutopostDedupIndexName] — the ONE place
/// the index shape is defined. Referenced by (a) the v150 migration step,
/// (b) the fresh-install `onCreate` SQLite path, and (c) the every-boot
/// `ensureSchemaDefaults` self-heal, so all three agree.
///
/// Spec 151: return JEs are now keyed on the ORIGINATING invoice id
/// (`referenceId = invoice.id`), so multiple partial returns of one invoice
/// legitimately share `(reference_type, reference_id)`. Their per-event
/// uniqueness rides on `journal_entries.global_id` (its own UNIQUE constraint),
/// NOT on this index — so the return types are exempted here.
///
/// The exemption list MUST stay in lock-step with `createJournalEntry`'s
/// `multiJeReferenceTypes` guard: EVERY reference type that legitimately posts
/// more than one auto-posted JE per `referenceId` is exempt. Besides the two
/// return types that Spec 151 re-keyed, that set already includes `sale`
/// (the original JE plus authorized-edit reposts), `commercial_paper` (one JE
/// per lifecycle status: deposited → cashed …) and `partial_collection` (one
/// JE per instalment). Omitting those here would let the index — once it lives
/// on fresh installs (b) — reject the second lifecycle/repost/instalment JE
/// that the in-code guard deliberately allows.
///
/// SQLite-only (partial index `WHERE …`). Postgres never carried this index
/// (the v120 migration was SQLite-only and it is not a Drift schema entity), so
/// we do NOT create it on PG — matching existing behavior.
/// أنواعُ المراجع التي تُنتج **قيداً لكلِّ حدثٍ** لا قيداً لكلِّ مرجع.
///
/// هذه هي القائمةُ الواحدةُ التي يقرؤها الطرفان: حارسُ
/// `createJournalEntry` في التطبيق، و`NOT IN` في الفهرس أدناه. وكانا
/// مكتوبَين مرّتين، والوثيقةُ تقول «لا بدّ أن يبقيا متطابقَين» — ولا شيءَ
/// يفرض ذلك.
///
/// 🔴 **وقع فعلاً 2026-08-27:** أُضيف `asset_depreciation` إلى حارس التطبيق
/// وحدَه، فصار الترحيلُ يمرّ الحارسَ ثمّ يصطدم بـ`UNIQUE constraint failed`
/// في الفهرس. و`runMonthlyDepreciation` يلتقط الاستثناءَ **لكلِّ أصلٍ على
/// حدة** ويتخطّاه، فتراجعت المعاملةُ كلُّها: لا قيدَ ولا صفَّ إهلاكٍ ولا
/// بطاقةٌ متقدّمة. أي أنّ الإهلاكَ **توقّف** بعد شهره الأوّل — والمصالحةُ
/// مرّت خضراءَ لأنّ الطرفَين تساويا عند الرقم الخاطئ.
///
/// و`e_je_dedup_lockstep_test.dart` يثبّت التطابقَ الآن.
const Set<String> kMultiJeReferenceTypes = {
  // Spec 151 (A-01/F-02) — قيودُ المردودات مفتاحُها فاتورةُ المنشأ ليتمكّن
  // `cancelSalesReturn` / `editPurchaseReturn` من عكسها بذلك الرقم. وفاتورةٌ
  // واحدةٌ تحمل مردوداتٍ جزئيّةً متعدّدة، فتفرّدُها يركب على `globalId`
  // الحتميِّ لا على `(refType, refId)`.
  'sales_return',
  'purchase_return',
  // قيدُ البيع قد يتعدّد عبر عمر الفاتورة: الأصلي ثمّ إعادةُ الترحيل بعد
  // عكسه عند تعديلٍ مُجاز. وتفرّدُ كلّ حدثٍ مضمونٌ بـ`globalId` الحتميِّ،
  // كما في المردودات، بينما حارسُ `hasAutoPostEntry` يحمي الترحيلَ الأوّل.
  'sale',
  // قيدٌ لكلِّ انتقالِ حالة: pending → deposited → cashed.
  'commercial_paper',
  // قيدٌ لكلِّ قسطِ تحصيل.
  'partial_collection',
  // 🔴 v168 (‏2026-08-27) — كشفته مصالحةُ الأصول في المرحلة ٤، ولا يظهر في
  // أيّ اختبارِ وحدة.
  //
  // الإهلاكُ قيدٌ لكلِّ **شهر**، و`referenceId` رقمُ الأصل **بلا فترة**.
  // فأصلٌ يُهلَك شهريّاً كان يُرحَّل في شهره الأوّل فقط، ويُعَدّ كلُّ شهرٍ
  // تالٍ «مكرَّراً» فيُبتلَع — بينما صفُّ `asset_depreciations` يُكتَب
  // و`fixed_assets.accumulated_depreciation` يتقدّم كالمعتاد.
  //
  // والأثرُ يتراكم صامتاً: مجمَّعُ الإهلاك في الأستاذ يتجمّد عند شهرٍ واحدٍ
  // لكلّ أصل، فالأصولُ الثابتةُ **مضخَّمةٌ** في الميزانيّة ومصروفُ الإهلاك
  // **منقوصٌ** في قائمة الدخل — ربحٌ أعلى من حقيقته وضريبةُ دخلٍ على أساسٍ
  // خاطئ. والشاشاتُ تقرأ البطاقةَ لا الأستاذ، فتبدو سليمةً تماماً.
  //
  // مقيسٌ: ثلاثةُ أشهرٍ ⇒ البطاقةُ ٦٠٠ والأستاذُ ٢٠٠، وصفوفُ الإهلاك
  // الثلاثةُ كلُّها تشير إلى **نفس** رقم القيد.
  //
  // وتفرّدُه لكلِّ حدثٍ محفوظٌ في موضعه الصحيح: `runMonthlyDepreciation`
  // يفحص `(assetId, periodDate)` ويتخطّى المُهلَك سلفاً قبل أن يصل هنا.
  'asset_depreciation',
  // 🔴 v174 (‏2026-09-20) — نفسُ فئةِ عطبِ v168 أعلاه، في نقلِ الأصل وتقييمه.
  //
  // `transferAsset` يُرحّل قيدَه بـ`referenceId: assetId` — رقمُ الأصل **بلا
  // وجهة**. فالنقلةُ الأولى (‏CC-A ← CC-B) تُرحَّل، وكلُّ نقلةٍ تاليةٍ لنفس
  // الأصل تُعَدّ تكراراً فيعيد الحارسُ رقمَ القيد الأوّل صامتاً ولا يُرحِّل
  // شيئاً. والأستاذُ يُبقي القيمةَ في CC-B إلى الأبد.
  //
  // وهي أعمقُ درجةً من العطب الذي أصلحه 0f7d2787: هناك كانت البطاقةُ جامدةً
  // والأستاذُ يتحرّك، وهنا — بعد أن صارت البطاقةُ تتحرّك — يتجمّد الأستاذُ عند
  // النقلة الأولى. والنتيجةُ واحدة: بطاقةٌ في مركزٍ ودفترٌ في آخر، وكلُّ تقريرٍ
  // يجمع الأصولَ بمركز التكلفة يخالف الدفتر. ولا يكشفه ميزانُ المراجعة لأنّ
  // طرفَي القيد الغائب في **نفس** الحساب.
  //
  // و`asset_revaluation` نفسُ الشكل: قيدٌ لكلِّ حدثِ تقييمٍ ومفتاحُه رقمُ الأصل
  // وحدَه ⇒ التقييمُ الثاني يُبتلَع بينما `purchase_price` يتقدّم.
  //
  // ⚖️ **والمقايضةُ صريحة:** الإعفاءُ يرفع الحمايةَ من الترحيل المزدوج على
  // مستوى القاعدة، و`transferAsset` — بخلاف `runMonthlyDepreciation` — لا
  // يملك مفتاحاً طبيعيّاً لكلِّ حدثٍ مثل `(assetId, periodDate)`. فلولا بديلٌ
  // لصارت الضغطةُ المزدوجةُ تُرحّل نقلتَين متطابقتَين: ضِعفُ القيمة الدفتريّة
  // في الوجهة وسالبُها في المصدر.
  //
  // والبديلُ موجودٌ في الطرفَين، وهو مفتاحٌ لكلِّ حدثٍ بالفعل لا بالاسم:
  //   • النقل: حارسُ `fromCostCenterId == asset.costCenterId` (‏0f7d2787).
  //     فبعد CC-A ← CC-B تصير البطاقةُ في CC-B، وتكرارُ «CC-A ← CC-B» يُرفَض
  //     قبل أيّ كتابة. النقلةُ المشروعةُ التاليةُ (‏CC-B ← CC-C) تختلف عنها
  //     بالمصدر، فتمرّ — وهذا هو عينُ التمييز الذي عجز عنه `(refType, refId)`.
  //   • التقييم: `if (difference.abs() < 0.01) return;` — والتقييمُ يكتب
  //     `purchasePrice = newFairValue + accumulatedDepreciation`، فإعادتُه إلى
  //     نفس القيمة العادلة تُخرج فرقاً صفراً ولا تصل هنا أصلاً.
  //
  // ⚠️ والباقي بعد ذلك: الحارسان تطبيقيّان لا قيدٌ في القاعدة. فكاتبان
  // متزامنان حقيقيّان قد يقرآن البطاقةَ قبل أن يكتب أيُّهما. وSQLite تُسلسِل
  // معاملاتِ الكتابة فالثاني يقرأ الحالةَ المثبَّتة ويُرفَض، والنقلُ يبدأ من
  // العميل لا من الخادم — فالفجوةُ نظريّةٌ اليوم، ومكانُ سدّها عمودُ وجهةٍ في
  // مفتاح القيد لا العودةُ إلى `(refType, refId)` الذي يخنق النقلةَ المشروعة.
  //
  // الحارس: `test/unit/asset_transfer_chain_posts_each_move_test.dart` —
  // ثلاثةُ فحوصٍ حمراءَ قبلَه وثلاثةُ مراسٍ خضراءَ تثبّت البديلَ أعلاه.
  'asset_transfer',
  'asset_revaluation',
};

const String kCreateJeAutopostDedupIndexSql =
    'CREATE UNIQUE INDEX IF NOT EXISTS $kJeAutopostDedupIndexName '
    'ON journal_entries(reference_type, reference_id) '
    'WHERE is_auto_posted = 1 '
    "AND reference_type NOT IN "
    "('sales_return', 'purchase_return', 'sale', 'commercial_paper', "
    "'partial_collection', 'asset_depreciation', "
    "'asset_transfer', 'asset_revaluation')";

/// أنواعُ المراجع التي تُصنَّف **أنشطةً استثماريّةً** في قائمة التدفّقات
/// النقديّة (‏IAS 7.16) — وهي عينُ ما يكتبه محرّكُ الأصول الثابتة.
///
/// 🔴 **وقع فعلاً:** كانت القائمةُ مكتوبةً مرّتين حرفيّاً داخلَ
/// `getCashFlowStatement` — في `NOT IN` التشغيليّة وفي `IN` الاستثماريّة —
/// وكلتاهما تحملان `'asset_acquisition'` و`'asset_disposal'`، **ولا يكتب
/// المستودعُ كلُّه أيّاً منهما**. والمحرّكُ في
/// `fixed_assets_dao_ext.dart` يكتب `'fixed_asset'` للاقتناء
/// و`'fixed_asset_disposal'` للاستبعاد.
///
/// فكلُّ شراءِ أصلٍ أو بيعِه نقداً كان يقع في **القِسم الخطأ مرّتين**:
/// لا يُستثنى من التشغيليّة (فيُحتسَب «مدفوعاتٍ/مقبوضاتٍ أخرى» في فرع
/// `default:`)، ولا يظهر في الاستثماريّة (فتُقرأ صفراً). وصافي التغيّر في
/// النقديّة يبقى صحيحاً لأنّ المبلغَ لم يضِعْ بل انتقل — فلا يمسكه أيُّ
/// فحصِ اتّزان، والمكسورُ هو الفصلُ الذي هو **غرضُ القائمة الأوّل**.
///
/// مقيسٌ قبل الإصلاح: أصلان نقداً بـ١٣٠٠٠٠ وبيعٌ بـ٣٠٠٠٠ ⇒ الاستثماريّةُ
/// `0.0` والتشغيليّةُ خارجاً `130000.0`.
///
/// و`'asset_transfer'` و`'asset_revaluation'` كانا مطابقَين في الطرفَين
/// أصلاً، فبقيا كما هما.
///
/// ⚠️ **و`'asset_depreciation'` ليس هنا بقصد**: قيدُه مدين `6213` / دائن
/// مجمَّعُ الإهلاك، ولا رِجْلَ له على النقد. وترشيحا القائمة **كلاهما**
/// مقيَّدان بحسابات النقد/البنك، فالإهلاكُ يُقرأ صفراً في الطرفَين بلا
/// تصنيف. والقائمةُ هنا تُبنى بالمنهج **المباشر** (جمعُ رِجْلِ النقد) لا
/// غيرِ المباشر (الربحُ ثمّ إضافةُ غير النقديّ عكسيّاً — IAS 7.20)، فلا
/// إضافةَ عكسيّةً للإهلاك تُصنَع أصلاً. ويثبّت ذلك
/// `ias7_fixed_asset_cashflow_classification_test.dart` قياساً لا افتراضاً.
///
/// والقائمةُ **واحدةٌ لا اثنتان**: الطرفان يقرآنها من هنا،
/// و`ias7_reference_type_lockstep_guard_test.dart` يشتقُّ ما يكتبه المحرّك
/// من الملفِّ نفسِه ويرفض أيَّ نوعٍ جديدٍ غيرِ مصنَّف.
const Set<String> kInvestingJeReferenceTypes = {
  'fixed_asset', // الاقتناء — fixed_assets_dao_ext.dart
  'fixed_asset_disposal', // الاستبعاد
  'asset_transfer',
  'asset_revaluation',
};

/// أنواعُ مراجع **قيدِ فاتورة المشتريات** — اسمان لقيدٍ واحد.
///
/// ⚠️ **ولهما مصدران مختلفان يكتبان نفسَ المستند:** المسارُ المُدمَج في
/// `createPurchaseInvoice` يختم `'purchase_invoice'`، و`autoPostPurchase`
/// يختم `'purchase'`. فأيُّ قارئٍ يفحص أحدَهما وحدَه يقرأ نصفَ الفواتير
/// «غيرَ مُرحَّلة» وهي مُرحَّلة.
///
/// وهي مقروءةٌ في ثلاثة مواضعَ: عكسُ القيد عند التعديل، وعكسُه عند الإلغاء،
/// وعمودُ «حالة الترحيل» في شاشة الاستعلام. وثلاثُ نسخٍ يدويّةٍ من نفس
/// القائمة تفترق في أوّل نوعٍ يُضاف — وهي بعينها عائلةُ عطبِ
/// [kInvestingJeReferenceTypes] أعلاه: طرفان يكتبان ويقرآن ولا يعرف
/// أحدُهما الآخر. فالقائمةُ **واحدةٌ** و`purchase_je_reference_lockstep_
/// guard_test.dart` يرفض أيَّ مُرشِّحٍ يكتبها بيده.
const Set<String> kPurchaseJeReferenceTypes = {
  'purchase_invoice', // المسارُ المُدمَج — createPurchaseInvoice
  'purchase', // الترحيلُ الآليّ — autoPostPurchase
};

/// أنواعُ المراجع المصنَّفةُ **أنشطةً تمويليّةً** (‏IAS 7.17).
const Set<String> kFinancingJeReferenceTypes = {'commercial_paper'};

/// يصيّر مجموعةَ أنواعٍ إلى قائمةِ SQL حرفيّة: `'a', 'b'`.
///
/// المُدخَلُ ثوابتُ ترجمةٍ لا مُدخَلُ مستخدمٍ، فلا مسرحَ لحقنٍ هنا —
/// والمتغيّراتُ المرقَّمةُ لا تُستعمل لأنّ الترشيحَ يُركَّب داخلَ نصٍّ
/// يحمل `?` لتواريخَ ومرشِّحاتٍ أخرى، فإدخالُ عددٍ متغيّرٍ منها يُزيح
/// ترتيبَ الوسائط.
String sqlRefTypeList(Iterable<String> types) =>
    types.map((t) => "'$t'").join(', ');

/// B1 — قيد قاعدة البيانات ضد صرف الراتب مرتين لنفس الفترة.
///
/// الحارس في `recordSalaryPayment` على مستوى التطبيق، وبيقفل الحالة الشائعة
/// (ضغطتين على نفس الجهاز). لكنه **مش كافٍ**: كاتب متزامن من جهاز تاني بيقرا
/// «مفيش صرف سابق» في نفس اللحظة، فالاتنين بيعدّوا الفحص ويكتبوا. ده الطبقة
/// اللي بتمنع ده.
///
/// `type` جزء من المفتاح بقصد — مكافأة أو سلفة لنفس الفترة التزام مختلف لا
/// تكرار للراتب.
///
/// ⚠️ `period` عمود nullable، وSQLite بيعتبر الـNULLات متمايزة في الفهرس
/// الفريد. فصفوف بلا فترة **مش محروسة** — وده **مطابق عن قصد** لحارس التطبيق:
/// `p.period.equals(null)` بيترجم لـ`= NULL` اللي عمره ما بيتحقق. التطابق بين
/// الطبقتين أهم من إحكام أكتر في طبقة واحدة، لأن اختلافهما بينتج رفضاً من
/// القاعدة بلا رسالة مفهومة من التطبيق.
const String kSalaryPaymentDedupIndexName = 'idx_salary_payments_period_dedup';
const String kCreateSalaryPaymentDedupIndexSql =
    'CREATE UNIQUE INDEX IF NOT EXISTS $kSalaryPaymentDedupIndexName '
    'ON salary_payments(employee_id, period, type)';

/// B2 — قيد قاعدة البيانات ضد تكرار صف الحضور لنفس اليوم.
///
/// استيراد البصمة بقى يعمل upsert على (‏employeeId, date)، لكن ده كود تطبيق
/// كمان. والحضور بيتحوّل لفلوس مباشرةً (الراتب بيعدّ صفوف `present`)، فصف
/// مكرر واحد = يوم عمل مدفوع مرتين.
const String kAttendanceDayDedupIndexName = 'idx_employee_attendance_day_dedup';
const String kCreateAttendanceDayDedupIndexSql =
    'CREATE UNIQUE INDEX IF NOT EXISTS $kAttendanceDayDedupIndexName '
    'ON employee_attendance(employee_id, date)';

/// ٦‑١ — سجلُّ حالات الفاتورة الإلكترونيّة: جدولٌ **غائبٌ عن كلِّ تنصيبةٍ
/// SQLite جديدة**.
///
/// 🔴 `EInvoiceStatusLog` له صنفُ جدولٍ في `e_invoicing_tables.dart` لكنّه
/// **غيرُ مُعلَنٍ في `@DriftDatabase`**. و`onCreate` يبني من كيانات drift،
/// و`onUpgrade` لا يعمل على تنصيبةٍ جديدة — فالهجرةُ v81 التي تُنشئه لا
/// تصل إلّا القواعدَ المُرقَّاة. أمّا PostgreSQL فمغطًّى بكتلةٍ خاصّةٍ في
/// مسار التكافؤ.
///
/// والنتيجةُ على SQLite الجديد: `e_invoicing_dao` يكتب ويقرأ الجدولَ بـSQL
/// خامٍّ (‏`INSERT INTO` و`SELECT * FROM`) فيفشل بـ«no such table» — وهو
/// **عينُ العطب** الذي عولج هنا لفهارس v150/v152 وv159 بنفس التعليل.
///
/// فالـDDL مصدرٌ واحدٌ تقرؤه ثلاثةُ أطراف: الهجرةُ، و`onCreate`، والشفاءُ
/// الذاتيُّ كلَّ إقلاع — وإلّا افترقت وعادت الفجوةُ من بابٍ آخر.
///
/// v173 — **صار الصنفُ مُعلَناً في `@DriftDatabase`** فيبنيه `createAll`
/// و`_createAllForPostgres` كأيّ كيان، وهذا الـDDL بقي شفاءً ذاتيّاً
/// للقواعد التي سبقت الإعلان. ويحمل أعمدةَ المزامنة الخمسةَ ليتطابق مع
/// الكيان: سجلُّ حالات الفاتورة الإلكترونيّة إثباتٌ رقابيٌّ يُزامَن.
const String kCreateEInvoiceStatusLogSql = '''
CREATE TABLE IF NOT EXISTS e_invoice_status_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  submission_id INTEGER NOT NULL REFERENCES e_invoice_submissions(id),
  old_status TEXT,
  new_status TEXT NOT NULL,
  changed_by TEXT,
  notes TEXT,
  changed_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
  global_id TEXT UNIQUE,
  last_modified_at INTEGER,
  deleted_at INTEGER,
  origin_client_id TEXT,
  row_version INTEGER NOT NULL DEFAULT 0
)''';
const String kCreateEInvoiceStatusLogIndexSql =
    'CREATE INDEX IF NOT EXISTS idx_einv_status_log_submission '
    'ON e_invoice_status_log(submission_id)';

/// v159 — المسارُ الساخنُ لمحرِّك الحجز: `getOverlappingBookings`.
///
/// كلُّ إنشاءِ حجزٍ وكلُّ نقلٍ أو تأجيلٍ أو إحياءٍ يشغّل استعلامَ مرشَّحين
/// على `(resource_id, starts_at)` بالضبط — داخل معاملةٍ تحجز الكتابة. وبلا
/// فهرسٍ فهو مسحُ جدولٍ كاملٍ ينمو بعمر المنشأة.
///
/// **وليس فريداً** — بخلاف فهرسَي B1/B2: التداخلُ يُمنَع بالفحص في الـDAO
/// لا بقيدٍ، وصفّان على نفس الموظَّف في نفس اللحظةِ **مشروعان** ما دام
/// أحدُهما `cancelled` أو `no_show`. فهرسٌ فريدٌ هنا كان سيمنع الصحيح.
///
/// ومحلُّه v159 عينُها: الجدولُ جديدٌ لم يُشحَن، فالتنصيبُ الجديدُ يأخذه من
/// `onCreate` والمُرقّى من الهجرة، بلا نسخةِ مخطّطٍ ثانية.
const String kBookingResourceSlotIndexName = 'idx_bookings_resource_starts_at';
const String kCreateBookingResourceSlotIndexSql =
    'CREATE INDEX IF NOT EXISTS $kBookingResourceSlotIndexName '
    'ON bookings(resource_id, starts_at)';

/// ٦‑٣ — تفرّدُ ربطِ الحسابات على (‏الغرض، مركزُ التكلفة).
///
/// `getAccountByPurpose` يختار بـ`limit(1)` بلا `orderBy`، فصفّان لنفس الغرض
/// يجعلان **اختيارَ الحساب غيرَ حتميّ**: نفسُ الفاتورةِ قد تُرحَّل على حسابٍ
/// اليومَ وعلى آخرَ غداً. والازدواجُ ميدانيٌّ مُوثَّقٌ في
/// `accounting_dao_writes.dart` (‏«mirror sync replays can leave more than one
/// row per purpose key») — و`.limit(1)` هناك مسكّنٌ للعَرَض لا علاجٌ للجذر.
///
/// ⚠️ **و`UNIQUE(purpose, cost_center_id)` لا يعالجه**: الربطُ العامُّ
/// `cost_center_id IS NULL`، و`NULL` لا يساوي `NULL` في قيدِ تفرّد — فالصفُّ
/// الذي يزدوج هو بعينه الصفُّ الذي يفلت. ولذلك الفهرسُ **تعبيريٌّ** على
/// `coalesce(cost_center_id, 0)`، وهو الشكلُ المكتوبُ أصلاً في ثلاثِ خطواتِ
/// هجرةٍ في `epoch_3.dart` — لكنّ `onCreate` يبني من كيانات drift و`onUpgrade`
/// لا يعمل على قاعدةٍ جديدةٍ ومتجاوَزٌ كلّيّاً على PG، فلم يصل تنصيبةً واحدة.
///
/// والمُعلَنُ في صنف الجدول `@TableIndex(idx_account_mappings_purpose)` —
/// غيرُ فريدٍ وعلى الغرض وحدَه — فلا يسدّ شيئاً من هذا.
const String kAccountMappingsPurposeCcIndexName =
    'idx_account_mappings_purpose_cc';
const String kCreateAccountMappingsPurposeCcIndexSql =
    'CREATE UNIQUE INDEX IF NOT EXISTS $kAccountMappingsPurposeCcIndexName '
    'ON account_mappings(purpose, coalesce(cost_center_id, 0))';

/// §٣‑٦ — قيدُ قاعدةٍ ضدّ تغطيةِ سطرَي كشفٍ بنكيٍّ بقيدٍ واحد.
///
/// المطابقةُ الآليّةُ تُقصي سطرَ القيد المستعملَ سلفاً (`l.id NOT IN (...)`)،
/// واليدويّةُ صارت ترمي عليه — **لكنّ الاثنين كودُ تطبيق**. ونفسُ حجّةِ فهرسَي
/// B1/B2 تسري هنا حرفاً: الأثرُ ماليّ.
///
/// فسطرا كشفٍ يُغلقان على نفسِ سطر القيد يُعَدّان مطابَقَين اثنَين، وينخفض
/// «غيرُ المطابَق» بمقدارَين، فتبدو المطابقةُ تامّةً بينما حركةٌ بنكيّةٌ كاملةٌ
/// بلا ما يقابلها في الدفتر. وهذا **يُخفي** الفرقَ بدل أن يُظهره — وإظهارُه
/// هو الغرضُ الوحيدُ من المطابقة.
///
/// ⚠️ **ولا حاجةَ لفهرسٍ جزئيّ**: العمودُ nullable، و`UNIQUE` تعامل `NULL`
/// قيماً **متمايزةً** في SQLite وPostgreSQL معاً — فآلافُ الأسطر غير المطابَقة
/// (`matched_journal_line_id IS NULL`) لا تتصادم.
///
/// ⚠️ **ولا تسويةَ آليّةً قبله** — نفسُ سياسة B1/B2 لا سياسةِ ربطِ الحسابات:
/// الصفُّ الزائدُ هنا **حركةٌ ذاتُ قيمةٍ ماليّة** لا إعداداً، فحذفُه قرارُ
/// محاسبٍ لا قرارُ إقلاع. وعلى بياناتٍ مزدوجةٍ تفشل الجملةُ بصمتٍ ويبقى حارسُ
/// التطبيق.
const String kBankStatementMatchDedupIndexName =
    'idx_bank_stmt_matched_je_line_dedup';
const String kCreateBankStatementMatchDedupIndexSql =
    'CREATE UNIQUE INDEX IF NOT EXISTS $kBankStatementMatchDedupIndexName '
    'ON bank_statement_lines(matched_journal_line_id)';

/// تفرّدُ وسمِ الاستيراد — صفٌّ واحدٌ لكلّ فاتورة (v174، المرحلة ٨).
///
/// `ImportPurchaseDetails` ١:١ مع `PurchaseInvoices` بالتعريف، ولا `UNIQUE`
/// في تعريف الجدول. وصفّان لفاتورةٍ واحدةٍ يُظهرانها مرّتَين في شاشة
/// المشتريات الخارجيّة ويجعلان قراءةَ بيانِها الجمركيِّ اختياراً عشوائيّاً
/// بين ورقتَين.
///
/// ✅ **وبلا تسويةٍ تسبقه**: الجدولُ شُحن في v174 بلا كاتبٍ واحد، فهو فارغٌ
///    في كلّ تنصيبةٍ قائمة — والفهرسُ يُركَّب من أوّل مرّة.
const String kImportPurchaseDetailsUniqueIndexName =
    'idx_import_purchase_details_invoice';
const String kCreateImportPurchaseDetailsUniqueIndexSql =
    'CREATE UNIQUE INDEX IF NOT EXISTS '
    '$kImportPurchaseDetailsUniqueIndexName '
    'ON import_purchase_details(purchase_invoice_id)';

/// تسويةُ المزدوج **قبل** تركيب [kCreateAccountMappingsPurposeCcIndexSql].
///
/// قرارُ المالك 2026-08-31: **يبقى الأحدثُ بـ`updated_at`**، والتعادلُ يُحسَم
/// بأكبر `id`. المنطق: آخرُ ما اختاره المستخدمُ في شاشة ربط الحسابات هو
/// نيّتُه الحاليّة.
///
/// ⚠️ والترتيبُ مُلزِم: القيدُ على بياناتٍ مزدوجةٍ يفشل، وحلقةُ الشفاء الذاتيِّ
/// **تبتلع الفشلَ بصمت** — فتخرج القاعدةُ بلا حمايةٍ ولا بلاغ. ولذلك يُثبِت
/// الاختبارُ وجودَ الفهرس **بعد** التسوية لا نجاحَ الجملة.
///
/// وهذا يخالف عمداً سياسةَ فهرسَي B1/B2 المجاورَين (‏«التسويةُ اليدويّةُ شغلُ
/// محاسبٍ لا شغلُ إقلاع»): هناك الصفُّ الزائدُ حركةٌ لها قيمةٌ ماليّةٌ مستقلّة،
/// وهنا الصفُّ الزائدُ **إعدادٌ** مكرَّرٌ لا حركةَ فيه — وبقاؤه هو الضرر.
///
/// الصيغةُ مكتوبةٌ بمقارنةٍ مترابطةٍ لا بدوالِّ نوافذَ كي تعمل حرفيّاً على
/// SQLite وPostgreSQL معاً.
const String kDedupAccountMappingsSql = '''
DELETE FROM account_mappings
WHERE id NOT IN (
  SELECT m.id
  FROM account_mappings m
  WHERE m.id = (
    SELECT m2.id
    FROM account_mappings m2
    WHERE m2.purpose = m.purpose
      AND coalesce(m2.cost_center_id, 0) = coalesce(m.cost_center_id, 0)
    ORDER BY m2.updated_at DESC, m2.id DESC
    LIMIT 1
  )
)''';

