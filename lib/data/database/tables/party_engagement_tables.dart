part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// تعاملُ الأطراف — متابعةُ التحصيل ومطالبةُ المورد (v165، أمرُ المالك 2026-08-26)
// ═══════════════════════════════════════════════════════════════════════════
//
// الجدولان يسندان حوارَي «متابعة تحصيل» و«تسوية ومطالبة المورد» في كشفَي
// الحساب. وكلاهما **سجلُّ تواصلٍ لا قيدٌ ماليّ**: لا يحرّكان خزنةً ولا ذمّةً
// ولا يكتبان قيداً. والمالُ يتحرّك بسندِ قبضٍ أو صرفٍ أو بإشعارٍ دائنٍ حين
// يصل — وكلُّها مساراتٌ قائمةٌ لا تُنسَخ هنا.
//
// ⚠️ **وما لا يفعله البرنامجُ لا يُخزَّن.** حوارا التصميم يحملان مفاتيحَ
// تعِد بسلوكٍ غيرِ مبنيّ:
//   · «تعليق البيع الآجل حتى الوعد» و«تعليق سداد PUR حتى التسوية» — حجزُ
//     ائتمانٍ يُفرَض عند إنشاء الفاتورة، ولا موضعَ له في مسار البيع اليوم.
//   · «مهمة تحصيل في زيارة الأربعاء» — يربط المتابعةَ بمسارات التوزيع.
//   · «إرفاق أذون الاستلام وصور الميزان» — بُنيت المرفقاتُ في v176
//     (§٨)، لكنَّ `PartyFollowUps` و`SupplierClaims` **ليستا من الأنواع
//     التسعة** التي قرّر المالكُ أنّها تقبل مرفقاً (§٨٫٤ قرار ٢).
//     وإضافتُهما سطران في `kAttachmentEntities` يومَ يُطلَب.
//   · «تصعيدٌ تلقائيٌّ بعد ٣ أيام» — لا جدولةَ خلفيّةً تُنفّذه.
// فلا أعمدةَ لها: مفتاحٌ يُحفَظ ولا يُنفَّذ أسوأُ من مفتاحٍ غائب. والباقي
// منها ممّا **يُقاس** صار تاريخاً يُعرَض: [PartyFollowUps.nextActionAt]
// و[SupplierClaims.replyDueAt].

/// محاولةُ تحصيلٍ مسجَّلة — «متابعة تحصيل» في كشف العميل.
///
/// صفٌّ لكلّ محاولة، فـ«محاولاتٌ سابقة» في التصميم عدٌّ لا عمود.
class PartyFollowUps extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get partyId => integer().references(Parties, #id)();

  /// الفاتورةُ موضوعُ المتابعة. تقبل الفراغَ عمداً: المتابعةُ قد تكون على
  /// الرصيد كلِّه لا على مستندٍ بعينه.
  IntColumn get invoiceId => integer().nullable()();
  TextColumn get invoiceNumber => text().nullable().withLength(max: 50)();

  /// **لقطةُ** المتبقّي وقتَ المتابعة — لا يُعاد حسابُه لاحقاً.
  ///
  /// المتبقّي اليومَ رقمٌ آخر (سُدِّد جزءٌ أو صدرت فاتورةٌ جديدة)، وقراءةُ
  /// المتابعة بأرقام اليوم تجعل سجلَّ الأمس يكذب عن نفسه.
  RealColumn get amountDue => real().withDefault(const Constant(0))();

  DateTimeColumn get contactedAt => dateTime()();

  /// `promise` · `no_answer` · `disputed` · `refused` — بطاقاتُ «نتيجة
  /// الاتصال» الأربع.
  TextColumn get outcome => text().withLength(max: 20)();

  /// تفاصيلُ الوعد — تقبل الفراغَ لأنّ ثلاثاً من النتائج الأربع بلا وعد.
  DateTimeColumn get promisedDate => dateTime().nullable()();
  RealColumn get promisedAmount => real().nullable()();

  /// من تُكُلِّم معه عند الطرف — نصٌّ حرٌّ لأنّه ليس مستخدمَ نظام.
  TextColumn get contactPerson => text().nullable().withLength(max: 120)();

  /// موعدُ الإجراء التالي — يُشتقّ من النتيجة (وعدٌ ⇒ تاريخُه، لم يُردّ ⇒
  /// بعد يومين) ويُعرَض في القائمة. **ولا مؤقّتَ يوقظه**: هو تاريخٌ يُقرأ لا
  /// تنبيهٌ يُطلَق، والفرقُ مذكورٌ في الحوار.
  DateTimeColumn get nextActionAt => dateTime().nullable()();

  TextColumn get notes => text().nullable()();

  IntColumn get createdBy => integer().nullable().references(Users, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  TextColumn get globalId => text().nullable().unique()();
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

/// مطالبةُ مورّدٍ بفروقِ المطابقة الثلاثيّة — «تسوية ومطالبة المورد».
class SupplierClaims extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get supplierId => integer().references(Parties, #id)();

  DateTimeColumn get claimDate => dateTime()();

  /// **لقطةُ** رصيد المورد في دفاترنا وقتَ المطالبة — «رصيده في دفاترنا».
  /// ونظيرُه «رصيدنا لديه» بيانةٌ عند المورد لا عندنا، فلا عمودَ لها.
  RealColumn get ledgerBalance => real().withDefault(const Constant(0))();

  /// `credit_note` · `goods` · `invoice_discount` · `cash_refund` — بطاقاتُ
  /// «شكل التسوية» الأربع.
  TextColumn get settlementKind => text().withLength(max: 24)();

  /// `draft` · `sent` · `accepted` · `rejected` · `settled`.
  TextColumn get status => text().withDefault(const Constant('draft'))();

  /// صافي المطالبة: **موجبٌ = لنا على المورد**، سالبٌ = عليه لنا.
  RealColumn get netAmount => real().withDefault(const Constant(0))();

  /// الفروقُ المطالَبُ بها مسلسلةً JSON — لكلٍّ رقمُ الأمر والصنفُ ونوعُ
  /// الفرق وكمّيّتُه.
  ///
  /// ⚠️ **ولمَ عمودٌ لا جدولُ أسطر؟** المطالبةُ **مراسلةٌ لا قيدٌ**: لا
  /// تُرحَّل إلى دفترٍ ولا تُجمَع في تقريرٍ ماليّ، والأسطرُ تُقرأ مع مطالبتها
  /// ولا تُستعلَم عبرها. وجدولٌ ثالثٌ كان يجرّ استراتيجيّةَ مزامنةٍ ومسارَ
  /// خادمٍ وهجرةً مقابلَ لا شيءٍ يُكسَب. فإن صارت تُرحَّل يوماً فهي هجرةٌ
  /// تُخطَّط، لا دَينٌ خفيّ.
  TextColumn get linesJson => text().nullable()();

  /// عددُ الفروق — يُقرأ بلا فكِّ [linesJson] في القوائم.
  IntColumn get lineCount => integer().withDefault(const Constant(0))();

  /// مهلةُ الردّ المتّفقة — تاريخٌ يُعرَض لا تنبيهٌ يُطلَق.
  DateTimeColumn get replyDueAt => dateTime().nullable()();

  TextColumn get notes => text().nullable()();

  IntColumn get createdBy => integer().nullable().references(Users, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  TextColumn get globalId => text().nullable().unique()();
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}
