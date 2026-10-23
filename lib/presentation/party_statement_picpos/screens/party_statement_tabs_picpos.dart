part of 'party_statement_picpos_screen.dart';

/// تبويبةٌ واحدة — تعريفٌ خالصٌ بلا حالة.
typedef _StatementTab = ({String id, String label, IconData icon, String note});

/// محتوى تبويبةٍ بعد التحميل.
///
/// **قائمةُ لبناتٍ مرتّبةٌ** لا خاناتٌ مسمّاة: التصميمُ يضع الرسمَ **فوقَ**
/// الجدول في تبويبةٍ و**تحته** في أخرى (‏«أعمار الدين» مقابلَ «المستحق
/// والاستحقاق»)، فخاناتٌ ثابتةٌ كانت ستفرض ترتيباً واحداً على الاثنتين.
class _TabData {
  const _TabData({this.blocks = const [], this.badge, this.footer});

  final List<Widget> blocks;

  /// شريطٌ **مثبَّتٌ أسفلَ التبويبة** خارجَ التمرير — «عرض المستند · طباعة
  /// الكشف · تصدير» في تصميم كشف الحساب.
  ///
  /// ⚠️ **وليس لبنةً أخيرةً في [blocks]**: اللبناتُ داخلَ `SingleChildScrollView`،
  /// فشريطُ أفعالٍ بينها ينزل مع الصفحة ويختفي عند أوّل كشفٍ طويل — وهو
  /// موضعُ الفعل.
  final Widget? footer;

  /// شارةُ العدد على رأس التبويبة — **مقيسةٌ من الصفوف المحمَّلة** لا مكتوبة،
  /// فلا تظهر قبل التحميل.
  final String? badge;

  bool get isEmpty => blocks.isEmpty;
}

// ═══════════════════════════════════════════════════════════════════════════
// تبويباتُ كشفَي الحساب — عشرُ تبويباتٍ تلتقي في ثلاثٍ وتفترق في اثنتين
// ═══════════════════════════════════════════════════════════════════════════
//
// | # | كشفُ العميل            | كشفُ المورد                 | الاستعلام
// | ١ | الحركة والرصيد          | الحركة والرصيد               | getPartyStatement
// | ٢ | أعمار الدين             | المستحق والاستحقاق           | getPartyOpenInvoices
// | ٣ | مطابقة الدفعات          | مطابقة الفواتير بالاستلام    | getPartyPaymentMatches / getPurchaseOrderMatches
// | ٤ | الأوراق والضمانات       | الأوراق والمقايضات           | getPartyPapers
// | ٥ | ملفُّ العميل والائتمان   | ملفُّ المورد والتقييم         | getPartyProfileMetrics + حقولُ v164

// ═══ أدواتٌ مشتركة ═══════════════════════════════════════════════════════

String _money(double v) =>
    '${v.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}';

/// كمّيّةٌ بلا أصفارٍ زائدة — أعمدةُ المطابقة كمّيّاتٌ لا مبالغ.
String _qty(double v) {
  final s = v.toStringAsFixed(3);
  return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
}

String _count(int v, String unit) => '$v $unit';

/// نسبةٌ لا تُقسَم على صفر.
double _ratio(double part, double whole) => whole == 0 ? 0 : part / whole * 100;

String _pct(double v) => tr('{p0}٪', {'p0': v.toStringAsFixed(0)});

/// `null` = لا سجلَّ يُقاس عليه — و«لا بيانات» ليست «صفر٪».
String _pctOrNone(double? v) => v == null ? tr('لا بيانات') : _pct(v);

const _tintOk = AppColors.success;
const _tintWarn = AppColors.warning;
const _tintErr = AppColors.error;
const _tintBrand = AppColors.primary;
const _tintIdle = Color(0xFF6B7280);
const _tintViolet = Color(0xFF8B5CF6);

/// لونُ شريحةِ العمر — نفسُ حدودِ `PartyOpenInvoiceRow.bucket`.
Color _bucketTint(String bucket) => switch (bucket) {
  'لم يحن' => _tintOk,
  '١—٣٠' => _tintWarn,
  _ => _tintErr,
};

// ═══ أعمدةُ «الحركة والرصيد» — كتالوجٌ واحدٌ يقرؤه الجدولُ والمنتقي ═══════
//
// قرارُ المالك على الصورة `(7)`: **«تخصيص الأعمدة» يُبنى بتفضيلٍ يُحفَظ لكلّ
// مستخدم**.
//
// ⚠️ **الرمزُ هو المحفوظُ لا الترتيب**: التفضيلُ يُخزَّن أسماءَ أعمدةٍ، فترتيبُ
// الأعمدة يبقى ترتيبَ هذا الكتالوج دائماً. وحفظُ الترتيبِ كان سيعني تفضيلاً
// قديماً يفرض ترتيباً على عمودٍ أُضيف بعده.
//
// ⚠️ **وما يُقرأ من التفضيل يُقاطَع مع هذه القائمة**: اسمُ عمودٍ حُذف لاحقاً
// يُسقَط بدل أن يُنتج خانةً في صفٍّ بلا رأسٍ فوقها.
const String kStatementColumnDate = 'date';
const String kStatementColumnDoc = 'doc';
const String kStatementColumnDesc = 'desc';
const String kStatementColumnDebit = 'debit';
const String kStatementColumnCredit = 'credit';
const String kStatementColumnBalance = 'balance';
const String kStatementColumnStatus = 'status';

typedef StatementColumnDef = ({
  String id,
  String label,
  double flex,
  PicPosCellAlign align,
});

List<StatementColumnDef> get kStatementColumnCatalogue => [
  (
    id: kStatementColumnDate,
    label: tr('التاريخ'),
    flex: 1.1,
    align: PicPosCellAlign.start,
  ),
  (
    id: kStatementColumnDoc,
    label: tr('المستند'),
    flex: 1.4,
    align: PicPosCellAlign.start,
  ),
  (
    id: kStatementColumnDesc,
    label: tr('البيان'),
    flex: 2,
    align: PicPosCellAlign.start,
  ),
  (
    id: kStatementColumnDebit,
    label: tr('مدين'),
    flex: 1.2,
    align: PicPosCellAlign.end,
  ),
  (
    id: kStatementColumnCredit,
    label: tr('دائن'),
    flex: 1.2,
    align: PicPosCellAlign.end,
  ),
  (
    id: kStatementColumnBalance,
    label: tr('الرصيد الجاري'),
    flex: 1.3,
    align: PicPosCellAlign.end,
  ),
  (
    id: kStatementColumnStatus,
    label: tr('الحالة'),
    flex: 1.2,
    align: PicPosCellAlign.start,
  ),
];

Set<String> get kStatementColumnIds => {
  for (final c in kStatementColumnCatalogue) c.id,
};

/// مفتاحُ التفضيل — **لكلّ مستخدمٍ على حدة**.
///
/// ⚠️ مفتاحٌ مشتركٌ بلا معرِّفٍ كان سيجعل تفضيلَ آخرِ من فتح الشاشةَ يحكم
/// الجميعَ على نفس الجهاز — وهو عكسُ ما طُلب حرفيّاً: «يُحفَظ لكلّ مستخدم».
String statementColumnPrefKey(int userId) =>
    'statement.ledger.columns.u$userId';

String encodeStatementColumnPreference(Set<String> cols) => [
  for (final c in kStatementColumnCatalogue)
    if (cols.contains(c.id)) c.id,
].join(',');

/// يقرأ المحفوظَ — و`null` تعني «لا تفضيلَ، خُذِ الافتراض».
///
/// ⚠️ **ويُقاطَع مع الكتالوج**: اسمُ عمودٍ حُذف لاحقاً يُسقَط بدل أن يُنتج
/// خانةً في صفٍّ بلا رأسٍ فوقها — و`PicPosDataTable` تؤكّد على تساوي الطولين،
/// فالخلطُ كان سيُسقط الشاشةَ لا أن يُزيح خانة.
///
/// ⚠️ **وعمودُ التاريخ يُعاد دائماً**: تفضيلٌ قديمٌ — أو نصٌّ حُرِّر بيدٍ —
/// بلا تاريخٍ يُنتج كشفاً لا يُقرأ ولا يُرتَّب.
Set<String>? parseStatementColumnPreference(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final kept = raw
      .split(',')
      .map((e) => e.trim())
      .where(kStatementColumnIds.contains)
      .toSet();
  if (kept.isEmpty) return null;
  return {...kept, kStatementColumnDate};
}

/// الافتراضُ: **الأعمدةُ السبعةُ كلُّها**.
///
/// ⚠️ التصميمُ يرسم ستّاً بلا «الحالة» — و«الحالة» عمودٌ **مقيسٌ** قائمٌ
/// (‏الفاتورةُ القائمةُ تُعرَف من `getPartyOpenInvoices`). فإطفاؤه افتراضاً
/// كان إسقاطَ معلومةٍ بلا طلب؛ والمنتقي يصل إلى ستّ التصميم بنقرةٍ واحدة.
const Set<String> kDefaultStatementColumns = {
  kStatementColumnDate,
  kStatementColumnDoc,
  kStatementColumnDesc,
  kStatementColumnDebit,
  kStatementColumnCredit,
  kStatementColumnBalance,
  kStatementColumnStatus,
};

// ═══ تعريفاتُ التبويبات ═══════════════════════════════════════════════════

List<_StatementTab> get _customerTabs => [
  (
    id: 'ledger',
    label: tr('الحركة والرصيد'),
    icon: PhosphorIconsBold.listNumbers,
    note: tr('الرصيد الجاري يُحسب بالترتيب الزمني — مدين ناقص دائن'),
  ),
  (
    id: 'aging',
    label: tr('أعمار الدين'),
    icon: PhosphorIconsBold.hourglass,
    note: tr('العمر يُحسب من تاريخ استحقاق الفاتورة لا تاريخ إصدارها'),
  ),
  (
    id: 'match',
    label: tr('مطابقة الدفعات'),
    icon: PhosphorIconsBold.link,
    note: tr('الدفعة تُخصم من أقدم فاتورة ما لم تُربط يدوياً'),
  ),
  (
    id: 'papers',
    label: tr('الأوراق والضمانات'),
    icon: PhosphorIconsBold.note,
    note: tr('الشيك لا يُنقص الذمة إلا عند التحصيل'),
  ),
  (
    id: 'profile',
    label: tr('ملف العميل والائتمان'),
    icon: PhosphorIconsBold.identificationCard,
    note: tr('حد الائتمان ومدة السماح وسلوك السداد'),
  ),
  (
    id: 'reservations',
    label: tr('الحجوزات'),
    icon: PhosphorIconsBold.calendarCheck,
    note: tr('حجوزات الخدمات والطاولات المرتبطة بهذا العميل'),
  ),
];

List<_StatementTab> get _supplierTabs => [
  (
    id: 'ledger',
    label: tr('الحركة والرصيد'),
    icon: PhosphorIconsBold.listNumbers,
    note: tr('الدائن يزيد ما علينا والمدين ينقصه — عكس كشف العميل'),
  ),
  (
    id: 'due',
    label: tr('المستحق والاستحقاق'),
    icon: PhosphorIconsBold.calendarCheck,
    note: tr('الخصم النقدي المتاح يُقارن بتكلفة التمويل'),
  ),
  (
    id: 'match',
    label: tr('مطابقة الفواتير بالاستلام'),
    icon: PhosphorIconsBold.gitDiff,
    note: tr('ثلاثية المطابقة: أمر شراء ← إذن استلام ← فاتورة'),
  ),
  (
    id: 'papers',
    label: tr('الأوراق والمقايضات'),
    icon: PhosphorIconsBold.note,
    note: tr('الشيك الصادر التزام قائم حتى يُخصم من البنك'),
  ),
  (
    id: 'profile',
    label: tr('ملف المورد والتقييم'),
    icon: PhosphorIconsBold.identificationCard,
    note: tr('شروط السداد والالتزام بالتوريد وجودة التسليم'),
  ),
];

// ═══════════════════════════════════════════════════════════════════════════

mixin _StatementTabsMixin on ConsumerState<PartyStatementPicposScreen> {
  // يوفّرها هيكلُ الشاشة
  bool get isSupplier;
  int? get partyId;
  Party? get party;
  DateTimeRange get range;
  DateFormat get df;

  /// الفرعُ المختار — `null` = كلُّ ما يراه المستخدم.
  int? get branchId;

  /// أعمدةُ الكشف الظاهرة، و«تخصيص الأعمدة» يفتح منتقيَها.
  ValueListenable<Set<String>> get visibleColumns;
  void openColumnPicker();

  /// الصفُّ المختار في الكشف — مصدرُ «عرض المستند» في الشريط السفليّ.
  ValueNotifier<PartyStatementEntry?> get selectedEntry;

  // يوفّرهما `_StatementExportMixin` على نفس الحالة — والشريطُ السفليُّ
  // يبنيهما داخلَ التبويبة التي يصدّرانها فعلاً.
  Future<void> printStatement();
  Future<void> exportToExcel();

  /// نصُّ البحث في الترويسة — يُرشِّح المحمَّلَ ولا يُعيد الاستعلام.
  ValueListenable<String> get query;

  /// يُفرغ كاشَ التبويبات ويُعيد الاستعلام — **بعد أيّ فعلٍ يحرّك مالاً**.
  void reloadTabs();

  IPartiesRepository get _repo => ref.read(partiesRepositoryProvider);

  /// سندُ قبضٍ للعميل أو صرفٍ للمورد — «تحصيل» و«سداد» في التصميم.
  ///
  /// ⚠️ **يُعاد استعمالُ حوارَي الخزينة القائمَين** لا يُبنى بديل: هما اللذان
  /// يكتبان في الخزنة والذمّة والقيد المحاسبيّ فعلاً، ونسخُهما كان سيُنتج
  /// مسارَ مالٍ ثانياً ينحرف عن الأوّل بأوّل إصلاح.
  ///
  /// ⚠️ **والسندُ على مستوى الطرف لا الفاتورة.** التصميمُ يضع الزرَّ في صفّ
  /// الفاتورة فيوحي بتحصيلٍ مخصَّصٍ لها، و`ReceiptVoucherDialog` يأخذ الطرفَ
  /// وحدَه. والتخصيصُ يقع بقاعدة «الأقدمُ أوّلاً» المعلَنةِ في تبويبة المطابقة
  /// — فالنتيجةُ هي هي حين تكون الفاتورةُ أقدمَ القائم، وتختلف حين لا تكون.
  /// والربطُ اليدويُّ للدفعة بفاتورةٍ بعينها ليس مبنيّاً بعد.
  Future<void> openVoucher() async {
    final p = party;
    if (p == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => isSupplier
          ? PaymentVoucherDialog(initialParty: p)
          : ReceiptVoucherDialog(initialParty: p),
    );
    if (!mounted) return;
    // ⚠️ يُعاد التحميلُ **دائماً** لا عند «حفظ» وحدَه: الحوارُ لا يعود بنتيجة،
    //    وسندٌ حُفظ ثمّ كشفٌ لم يتحرّك يقرؤه المشغّلُ عطباً في السند.
    reloadTabs();
  }

  /// «متابعة تحصيل» — سجلُّ محاولةٍ على فاتورةٍ بعينها.
  ///
  /// ⚠️ **لا يُعاد تحميلُ التبويبات إلّا إن حُفظت متابعة**: المتابعةُ لا تحرّك
  /// رصيداً، فإلغاءُ الحوار لا يغيّر رقماً — وإعادةُ تحميلٍ بلا سببٍ تومض
  /// الشاشةَ وتُوهم أنّ شيئاً وقع.
  Future<void> openFollowUp(PartyOpenInvoiceRow invoice) async {
    final p = party;
    if (p == null) return;
    final prior = await _repo.countPartyFollowUps(
      p.id,
      invoiceId: invoice.invoiceId,
    );
    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _FollowUpDialog(party: p, invoice: invoice, priorAttempts: prior),
    );
    if (saved == true && mounted) reloadTabs();
  }

  /// «تسوية ومطالبة المورد» — على فروق المطابقة الثلاثيّة.
  ///
  /// ⚠️ **يُفتَح على الفروق وحدَها**: الأسطرُ السليمةُ لا يُطالَب بها، وعرضُها
  /// في الحوار كان يُغرق ما يُطالَب به فعلاً.
  Future<void> openClaim(List<PoMatchRow> gaps) async {
    final p = party;
    if (p == null) return;
    if (gaps.isEmpty) {
      AppToast.show(
        context,
        tr('لا فروقَ يُطالَب بها'),
        type: ToastType.warning,
      );
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _SupplierClaimDialog(party: p, gaps: gaps, ledgerBalance: p.balance),
    );
    if (saved == true && mounted) reloadTabs();
  }

  Future<_TabData> _ledgerTab();
  Future<_TabData> _agingTab();
  Future<_TabData> _dueTab();
  Future<_TabData> _matchCustomerTab();
  Future<_TabData> _matchSupplierTab();
  Future<_TabData> _papersTab();
  Future<_TabData> _profileTab();
  Future<_TabData> _reservationsTab();

  Future<_TabData> loadTab(String id) {
    if (partyId == null) return Future.value(const _TabData());
    return switch (id) {
      'ledger' => _ledgerTab(),
      'aging' => _agingTab(),
      'due' => _dueTab(),
      'match' => isSupplier ? _matchSupplierTab() : _matchCustomerTab(),
      'papers' => _papersTab(),
      'profile' => _profileTab(),
      'reservations' => _reservationsTab(),
      _ => Future.value(const _TabData()),
    };
  }
}
