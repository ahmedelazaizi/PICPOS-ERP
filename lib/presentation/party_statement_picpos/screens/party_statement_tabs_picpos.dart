part of 'party_statement_picpos_screen.dart';

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
  return s.contains('.')
      ? s.replaceFirst(RegExp(r'\.?0+$'), '')
      : s;
}

String _count(int v, String unit) => '$v $unit';

/// نسبةٌ لا تُقسَم على صفر.
double _ratio(double part, double whole) => whole == 0 ? 0 : part / whole * 100;

String _pct(double v) => '${v.toStringAsFixed(0)}٪';

/// `null` = لا سجلَّ يُقاس عليه — و«لا بيانات» ليست «صفر٪».
String _pctOrNone(double? v) => v == null ? 'لا بيانات' : _pct(v);

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

const List<StatementColumnDef> kStatementColumnCatalogue = [
  (
    id: kStatementColumnDate,
    label: 'التاريخ',
    flex: 1.1,
    align: PicPosCellAlign.start
  ),
  (
    id: kStatementColumnDoc,
    label: 'المستند',
    flex: 1.4,
    align: PicPosCellAlign.start
  ),
  (
    id: kStatementColumnDesc,
    label: 'البيان',
    flex: 2,
    align: PicPosCellAlign.start
  ),
  (
    id: kStatementColumnDebit,
    label: 'مدين',
    flex: 1.2,
    align: PicPosCellAlign.end
  ),
  (
    id: kStatementColumnCredit,
    label: 'دائن',
    flex: 1.2,
    align: PicPosCellAlign.end
  ),
  (
    id: kStatementColumnBalance,
    label: 'الرصيد الجاري',
    flex: 1.3,
    align: PicPosCellAlign.end
  ),
  (
    id: kStatementColumnStatus,
    label: 'الحالة',
    flex: 1.2,
    align: PicPosCellAlign.start
  ),
];

Set<String> get kStatementColumnIds =>
    {for (final c in kStatementColumnCatalogue) c.id};

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

const List<_StatementTab> _customerTabs = [
  (
    id: 'ledger',
    label: 'الحركة والرصيد',
    icon: PhosphorIconsBold.listNumbers,
    note: 'الرصيد الجاري يُحسب بالترتيب الزمني — مدين ناقص دائن',
  ),
  (
    id: 'aging',
    label: 'أعمار الدين',
    icon: PhosphorIconsBold.hourglass,
    note: 'العمر يُحسب من تاريخ استحقاق الفاتورة لا تاريخ إصدارها',
  ),
  (
    id: 'match',
    label: 'مطابقة الدفعات',
    icon: PhosphorIconsBold.link,
    note: 'الدفعة تُخصم من أقدم فاتورة ما لم تُربط يدوياً',
  ),
  (
    id: 'papers',
    label: 'الأوراق والضمانات',
    icon: PhosphorIconsBold.note,
    note: 'الشيك لا يُنقص الذمة إلا عند التحصيل',
  ),
  (
    id: 'profile',
    label: 'ملف العميل والائتمان',
    icon: PhosphorIconsBold.identificationCard,
    note: 'حد الائتمان ومدة السماح وسلوك السداد',
  ),
];

const List<_StatementTab> _supplierTabs = [
  (
    id: 'ledger',
    label: 'الحركة والرصيد',
    icon: PhosphorIconsBold.listNumbers,
    note: 'الدائن يزيد ما علينا والمدين ينقصه — عكس كشف العميل',
  ),
  (
    id: 'due',
    label: 'المستحق والاستحقاق',
    icon: PhosphorIconsBold.calendarCheck,
    note: 'الخصم النقدي المتاح يُقارن بتكلفة التمويل',
  ),
  (
    id: 'match',
    label: 'مطابقة الفواتير بالاستلام',
    icon: PhosphorIconsBold.gitDiff,
    note: 'ثلاثية المطابقة: أمر شراء ← إذن استلام ← فاتورة',
  ),
  (
    id: 'papers',
    label: 'الأوراق والمقايضات',
    icon: PhosphorIconsBold.note,
    note: 'الشيك الصادر التزام قائم حتى يُخصم من البنك',
  ),
  (
    id: 'profile',
    label: 'ملف المورد والتقييم',
    icon: PhosphorIconsBold.identificationCard,
    note: 'شروط السداد والالتزام بالتوريد وجودة التسليم',
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
      builder: (_) => _FollowUpDialog(
        party: p,
        invoice: invoice,
        priorAttempts: prior,
      ),
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
      AppToast.show(context, 'لا فروقَ يُطالَب بها', type: ToastType.warning);
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _SupplierClaimDialog(
        party: p,
        gaps: gaps,
        ledgerBalance: p.balance,
      ),
    );
    if (saved == true && mounted) reloadTabs();
  }

  Future<_TabData> loadTab(String id) {
    if (partyId == null) return Future.value(const _TabData());
    return switch (id) {
      'ledger' => _ledgerTab(),
      'aging' => _agingTab(),
      'due' => _dueTab(),
      'match' => isSupplier ? _matchSupplierTab() : _matchCustomerTab(),
      'papers' => _papersTab(),
      'profile' => _profileTab(),
      _ => Future.value(const _TabData()),
    };
  }

  // ═══ ١) الحركة والرصيد ═════════════════════════════════════════════════
  //
  // ⚠️ **الرصيدُ الجاري ورصيدُ أوّل الفترة لا يُحسبان هنا.**
  // `getPartyStatement` يحسب الافتتاحيَّ من حركةِ ما قبل الفترة (مبيعاتٌ −
  // مقبوضاتٌ − مدفوعاتٌ − مذكّراتُ مرتجعٍ + شيكات)، ويُدرج صفَّه أوّلَ الكشف،
  // ثمّ يملأ الرصيدَ الجاريَ بحلقةٍ تحترم اتّجاهَ الطرف. وإعادةُ الحساب هنا
  // كانت ستُنتج رقمين لنفس السؤال.
  Future<_TabData> _ledgerTab() async {
    final pid = partyId!;
    final entries = await _repo.getPartyStatement(
      pid,
      fromDate: range.start,
      toDate: range.end,
      branchId: branchId,
    );
    if (entries.isEmpty) return const _TabData();

    // الفاتورةُ القائمةُ تُعرَف بوجود رقمها في نتيجة `getPartyOpenInvoices`،
    // فعمودُ «الحالة» مقيسٌ لا مُخمَّن. و`PartyStatementEntry` وحدَه لا يحمل
    // حالةَ السداد.
    final open = await _repo.getPartyOpenInvoices(
      partyId: pid,
      supplier: isSupplier,
    );
    final openByNumber = {for (final o in open) o.invoiceNumber: o};

    var debit = 0.0;
    var credit = 0.0;
    for (final e in entries) {
      debit += e.debit;
      credit += e.credit;
    }
    final closing = entries.last.balance;
    final opening = entries
        .where((e) => e.entryType == 'opening')
        .fold<double>(0, (_, e) => e.balance);

    // المؤشّرُ الخامسُ يفترق بين الكشفين كما في التصميم: العميلُ يُسأل عمّا
    // تأخّر عليه، والمورّدُ عمّا يستحقّ قريباً.
    final overdue = open.where((o) => o.overdue).fold<double>(
          0,
          (s, o) => s + o.remaining,
        );
    final dueSoon = open
        .where((o) => o.daysLate >= -7)
        .fold<double>(0, (s, o) => s + o.remaining);

    final kpis = <PicPosHubKpi>[
      PicPosHubKpi(
        icon: PhosphorIconsBold.arrowSquareIn,
        label: 'رصيد أول الفترة',
        value: _money(opening),
        tint: _tintIdle,
        vs: df.format(range.start),
      ),
      PicPosHubKpi(
        icon: isSupplier
            ? PhosphorIconsBold.handCoins
            : PhosphorIconsBold.receipt,
        label: 'إجمالي المدين',
        value: _money(debit),
        tint: isSupplier ? _tintOk : _tintErr,
        vs: isSupplier ? 'مدفوعات ومرتجعات' : 'فواتير ورسوم',
      ),
      PicPosHubKpi(
        icon: isSupplier
            ? PhosphorIconsBold.receipt
            : PhosphorIconsBold.handCoins,
        label: 'إجمالي الدائن',
        value: _money(credit),
        tint: isSupplier ? _tintErr : _tintOk,
        vs: isSupplier ? 'فواتير شراء' : 'تحصيلات ومرتجعات',
      ),
      PicPosHubKpi(
        icon: PhosphorIconsBold.scales,
        label: 'الرصيد الختامي',
        value: _money(closing),
        tint: closing == 0
            ? _tintIdle
            : (isSupplier ? _tintErr : _tintBrand),
        vs: closing == 0
            ? 'مسوّى'
            : (isSupplier ? 'دائن لصالح المورد' : 'مدين على العميل'),
      ),
      if (isSupplier)
        PicPosHubKpi(
          icon: PhosphorIconsBold.clock,
          label: 'يستحق خلال ٧ أيام',
          value: _money(dueSoon),
          tint: dueSoon > 0 ? _tintErr : _tintOk,
          vs: 'شاملاً المتأخر',
        )
      else
        PicPosHubKpi(
          icon: PhosphorIconsBold.warning,
          label: 'المتأخر منه',
          value: _money(overdue),
          tint: overdue > 0 ? _tintErr : _tintOk,
          vs: 'فوق مدة السماح',
        ),
    ];

    // شرائحُ الترشيح **تعمل فعلاً**: شريحةٌ لا تُرشِّح تكذب كزرٍّ لا يفعل.
    final groups = <({String label, List<PartyStatementEntry> items})>[
      (label: 'كل الحركات', items: entries),
      (
        label: 'فواتير',
        items: entries
            .where((e) => e.entryType == 'invoice' || e.entryType == 'purchase')
            .toList()
      ),
      (
        label: isSupplier ? 'مدفوعات' : 'تحصيلات',
        items: entries
            .where((e) =>
                e.entryType == (isSupplier ? 'payment' : 'receipt'))
            .toList()
      ),
      (
        label: 'مرتجعات',
        items: entries
            .where((e) =>
                e.entryType == 'sales_return' || e.entryType == 'memo')
            .toList()
      ),
      if (isSupplier)
        (
          label: 'خصومات',
          items: entries.where((e) => e.entryType == 'discount').toList()
        )
      else
        (
          label: 'أوراق',
          items:
              entries.where((e) => e.entryType == 'commercial_paper').toList()
        ),
    ];

    /// خليّةُ عمودٍ واحدٍ من صفٍّ واحد — الكتالوجُ يختار أيَّها يُبنى.
    PicPosCell cellOf(String columnId, PartyStatementEntry e) =>
        switch (columnId) {
          kStatementColumnDate => PicPosTextCell(df.format(e.date)),
          // ⚠️ **بلون العلامة**: التصميمُ يرسم رقمَ المستند رابطاً تحته خطّ،
          //    وهو ما يُنقَر ليُفتَح. والصفُّ كلُّه قابلٌ للنقر هنا، فاللونُ
          //    يقول «هذا ما يُفتَح» بلا خطٍّ يوحي بمتصفِّح.
          kStatementColumnDoc => PicPosTextCell(
              (e.invoiceNumber ?? '').isEmpty ? '—' : e.invoiceNumber!,
              icon: _entryIcon(e.entryType),
              tint: _entryTint(e.entryType),
            ),
          kStatementColumnDesc => PicPosTextCell(e.description),
          kStatementColumnDebit =>
            PicPosTextCell(e.debit == 0 ? '—' : _money(e.debit)),
          kStatementColumnCredit =>
            PicPosTextCell(e.credit == 0 ? '—' : _money(e.credit)),
          kStatementColumnBalance => PicPosTextCell(_money(e.balance)),
          _ => _statusPill(e, openByNumber),
        };

    /// خانةُ المجاميع تحت عمودٍ واحد.
    ///
    /// ⚠️ المجاميعُ مجاميعُ **العمود المعروض** لا مجاميعَ الكشف كلِّه — فتتغيّر
    /// مع الشريحة، وإلّا قرأ المشغّلُ مجموعاً لا يخصّ ما يراه.
    String totalOf(String columnId, List<PartyStatementEntry> rows) {
      switch (columnId) {
        case kStatementColumnDate:
          return _count(rows.length, 'حركة');
        case kStatementColumnDebit:
          return _money(rows.fold<double>(0, (t, e) => t + e.debit));
        case kStatementColumnCredit:
          return _money(rows.fold<double>(0, (t, e) => t + e.credit));
        case kStatementColumnBalance:
          return rows.isEmpty ? '—' : _money(rows.last.balance);
        default:
          return '';
      }
    }

    return _TabData(
      badge: '${entries.length}',
      blocks: [
        PicPosHubKpiRow(items: kpis),
        _LedgerTable(
          columnsVN: visibleColumns,
          selectedVN: selectedEntry,
          query: query,
          groups: groups,
          subtitle: isSupplier
              ? 'الدائن يزيد ما علينا للمورد والمدين ينقصه · الرصيد الجاري تراكمي'
              : 'مرتّب زمنياً · المدين يزيد الذمة والدائن ينقصها · الرصيد الجاري تراكمي',
          cell: cellOf,
          total: totalOf,
          onCustomize: openColumnPicker,
        ),
      ],
      // شريطُ التصميم السفليّ: «عرض المستند · طباعة الكشف · تصدير».
      footer: _StatementActionBar(
        selectedVN: selectedEntry,
        onPrint: printStatement,
        onExport: exportToExcel,
      ),
    );
  }

  IconData _entryIcon(String type) => switch (type) {
        'opening' => PhosphorIconsBold.arrowSquareIn,
        'invoice' || 'purchase' => PhosphorIconsBold.receipt,
        'receipt' || 'payment' => PhosphorIconsBold.handCoins,
        'sales_return' || 'memo' => PhosphorIconsBold.arrowUUpLeft,
        'commercial_paper' => PhosphorIconsBold.note,
        'discount' => PhosphorIconsBold.percent,
        _ => PhosphorIconsBold.dotsThree,
      };

  Color _entryTint(String type) => switch (type) {
        'opening' => _tintIdle,
        'invoice' || 'purchase' => isSupplier ? _tintErr : _tintBrand,
        'receipt' || 'payment' => _tintOk,
        'sales_return' || 'memo' => _tintViolet,
        'commercial_paper' => AppColors.primaryLight,
        'discount' => _tintOk,
        _ => _tintIdle,
      };

  /// حالةُ الصفّ — الفاتورةُ وحدَها تُقاس بالقائمِ من الذمّة، والباقي يُسمّى
  /// بنوعه. والتصميمُ يكتب «مسدَّدة» على كلّ فاتورةٍ لأنّه صورة.
  PicPosCell _statusPill(
    PartyStatementEntry e,
    Map<String, PartyOpenInvoiceRow> openByNumber,
  ) {
    if (e.entryType == 'invoice' || e.entryType == 'purchase') {
      final o = openByNumber[e.invoiceNumber ?? ''];
      if (o == null) return const PicPosPillCell('مسدَّدة', _tintOk);
      return o.overdue
          ? PicPosPillCell('متأخرة ${o.daysLate} يوماً', _tintErr)
          : const PicPosPillCell('قائمة', _tintWarn);
    }
    return switch (e.entryType) {
      'opening' => const PicPosPillCell('مُدوَّر', _tintIdle),
      'receipt' => const PicPosPillCell('محصَّل', _tintOk),
      'payment' => const PicPosPillCell('مدفوع', _tintOk),
      'sales_return' || 'memo' => const PicPosPillCell('مرتجع', _tintViolet),
      'commercial_paper' => const PicPosPillCell('ورقة', _tintBrand),
      'discount' => const PicPosPillCell('خصم', _tintOk),
      _ => const PicPosPillCell('حركة', _tintIdle),
    };
  }

  // ═══ ٢أ) أعمار الدين — كشفُ العميل ══════════════════════════════════════
  Future<_TabData> _agingTab() async {
    final pid = partyId!;
    final open =
        await _repo.getPartyOpenInvoices(partyId: pid, supplier: false);
    if (open.isEmpty) return const _TabData();
    final metrics =
        await _repo.getPartyProfileMetrics(partyId: pid, supplier: false);

    const order = ['لم يحن', '١—٣٠', '٣١—٦٠', 'فوق ٦٠'];
    final sums = {for (final b in order) b: 0.0};
    final counts = {for (final b in order) b: 0};
    for (final o in open) {
      sums[o.bucket] = sums[o.bucket]! + o.remaining;
      counts[o.bucket] = counts[o.bucket]! + 1;
    }
    final total = sums.values.fold<double>(0, (a, b) => a + b);

    final terms = party?.paymentTermsDays ?? 0;
    final kpis = <PicPosHubKpi>[
      for (var i = 0; i < order.length; i++)
        PicPosHubKpi(
          icon: switch (i) {
            0 => PhosphorIconsBold.checkCircle,
            1 => PhosphorIconsBold.clock,
            2 => PhosphorIconsBold.clockCountdown,
            _ => PhosphorIconsBold.warningOctagon,
          },
          label: i == 0 ? 'مستحق لم يحن' : '${order[i]} يوماً',
          value: _money(sums[order[i]]!),
          tint: _bucketTint(order[i]),
          vs: '${_pct(_ratio(sums[order[i]]!, total))} من القائم',
        ),
      // ⚠️ التصميمُ يسمّيه «متوسط أيام التحصيل ٣٤» — أي من الإصدار إلى
      //    السداد. والمقيسُ في `getPartyProfileMetrics` هو الفرقُ بين
      //    **الاستحقاق** وآخرِ دفعة، فجمعُ مهلةِ السداد عليه كان سيضخّم
      //    الرقمَ لكلّ فاتورةٍ سابقةٍ لـv164 (‏استحقاقُها = إصدارُها).
      //    فيُعرَض ما قِيس بالضبط، وتُذكَر المهلةُ بجانبه.
      PicPosHubKpi(
        icon: PhosphorIconsBold.timer,
        label: 'متوسط السداد بعد الاستحقاق',
        value: metrics.settledInvoices == 0
            ? 'لا بيانات'
            : '${metrics.avgSettlementDays.toStringAsFixed(0)} يوماً',
        tint: metrics.settledInvoices == 0
            ? _tintIdle
            : (metrics.avgSettlementDays > 0 ? _tintErr : _tintOk),
        vs: terms == 0
            ? 'بلا مهلة متفقة'
            : 'مدة السماح $terms يوماً',
      ),
    ];

    return _TabData(
      badge: '${open.length}',
      blocks: [
        PicPosHubKpiRow(items: kpis),
        PicPosBarList(
          title: 'توزيع الرصيد على أعمار الدين',
          subtitle: 'العمر من تاريخ الاستحقاق',
          items: [
            for (final b in order)
              PicPosBarItem(
                icon: switch (b) {
                  'لم يحن' => PhosphorIconsBold.checkCircle,
                  '١—٣٠' => PhosphorIconsBold.clock,
                  '٣١—٦٠' => PhosphorIconsBold.clockCountdown,
                  _ => PhosphorIconsBold.warningOctagon,
                },
                tint: _bucketTint(b),
                label: b == 'لم يحن' ? 'لم يحن استحقاقه' : 'متأخر $b يوماً',
                sub: _count(counts[b]!, 'فاتورة'),
                value: sums[b]!,
                caption: _pct(_ratio(sums[b]!, total)),
                display: _money(sums[b]!),
              ),
          ],
        ),
        _FilterableTable<PartyOpenInvoiceRow>(
          query: query,
          title: 'الفواتير القائمة وأعمارها',
          subtitle: 'كل فاتورة بما سُدّد منها وما تبقّى وعمر تأخرها',
          // ⚠️ **عمودا إجراءٍ لا واحدٌ كالتصميم.** التصميمُ يضع «تحصيل» وحدَه
          //    ويفتح «متابعة» من مكانٍ لا يظهر في الصورة. والفعلان مختلفان
          //    تماماً — أحدُهما يحرّك مالاً والآخرُ يسجّل مكالمة — فدمجُهما
          //    في زرٍّ واحدٍ كان يُخفي أحدَهما. والحدُّ الأدنى رُفع فيتمرّر
          //    الجدولُ أفقيّاً بدل أن تزدحم تسعةُ أعمدةٍ على شاشةٍ ضيّقة.
          minWidth: 940,
          columns: const [
            PicPosTableColumn('الفاتورة', flex: 1.5),
            PicPosTableColumn('التاريخ', flex: 1.2),
            PicPosTableColumn('الاستحقاق', flex: 1.2),
            PicPosTableColumn('القيمة',
                flex: 1.2, align: PicPosCellAlign.end),
            PicPosTableColumn('المسدَّد',
                flex: 1.2, align: PicPosCellAlign.end),
            PicPosTableColumn('المتبقي',
                flex: 1.2, align: PicPosCellAlign.end),
            PicPosTableColumn('عمر التأخر', flex: 1.3),
            PicPosTableColumn('إجراء', flex: 1.2),
            PicPosTableColumn('متابعة', flex: 1.2),
          ],
          groups: [
            (label: 'القائمة', items: open),
            (
              label: 'متأخرة',
              items: open.where((o) => o.overdue).toList()
            ),
          ],
          buildRow: _openInvoiceRow,
          totals: _openInvoiceTotals,
        ),
      ],
    );
  }

  PicPosTableRow _openInvoiceRow(PartyOpenInvoiceRow o) => PicPosTableRow(
        cells: [
          PicPosTextCell(
            o.invoiceNumber,
            icon: PhosphorIconsBold.receipt,
            tint: _bucketTint(o.bucket),
          ),
          PicPosTextCell(df.format(o.invoiceDate)),
          PicPosTextCell(df.format(o.dueDate)),
          PicPosTextCell(_money(o.total)),
          PicPosTextCell(o.paid == 0 ? '—' : _money(o.paid)),
          PicPosTextCell(_money(o.remaining)),
          PicPosBarCell(
            o.overdue ? _count(o.daysLate, 'يوماً') : 'لم يحن',
            // شريطُ التأخّر يُقاس على ٩٠ يوماً — حدُّ آخرِ شريحةٍ في التقادم،
            // وما فوقَه يمتلئ. ونسبةٌ بلا سقفٍ كانت ستجعل فاتورةً واحدةً
            // قديمةً تسحق باقيَ الصفوف بصريّاً.
            o.overdue ? (o.daysLate / 90).clamp(0.0, 1.0) : 0.0,
            _bucketTint(o.bucket),
          ),
          PicPosButtonCell(
            'تحصيل',
            icon: PhosphorIconsBold.handCoins,
            tint: _tintOk,
            onPressed: openVoucher,
          ),
          PicPosButtonCell(
            'متابعة',
            icon: PhosphorIconsBold.phone,
            tint: _tintBrand,
            onPressed: () => openFollowUp(o),
          ),
        ],
      );

  List<String> _openInvoiceTotals(List<PartyOpenInvoiceRow> rows) {
    var t = 0.0;
    var p = 0.0;
    var r = 0.0;
    for (final o in rows) {
      t += o.total;
      p += o.paid;
      r += o.remaining;
    }
    return [
      _count(rows.length, 'بند'),
      '',
      '',
      _money(t),
      _money(p),
      _money(r),
      '',
      '',
      '',
    ];
  }

  // ═══ ٢ب) المستحق والاستحقاق — كشفُ المورد ═══════════════════════════════
  Future<_TabData> _dueTab() async {
    final pid = partyId!;
    final open =
        await _repo.getPartyOpenInvoices(partyId: pid, supplier: true);
    if (open.isEmpty) return const _TabData();

    // ⚠️ **الشرائحُ الأربعُ متباينةٌ لا متداخلة.** التصميمُ يضع «يستحق خلال ٧
    //    أيام» و«يستحق ٨—٣٠» و«لم يحن» — وثلاثتُها لا تستوعب **المتأخّر**،
    //    فيسقط أعجلُ ما على المنشأة من الكشف. فأُضيفت شريحةُ «متأخّر» أوّلاً.
    double sumWhere(bool Function(PartyOpenInvoiceRow) f) =>
        open.where(f).fold<double>(0, (s, o) => s + o.remaining);

    final overdueSum = sumWhere((o) => o.daysLate > 0);
    final week = sumWhere((o) => o.daysLate <= 0 && o.daysLate >= -7);
    final month = sumWhere((o) => o.daysLate < -7 && o.daysLate >= -30);
    final later = sumWhere((o) => o.daysLate < -30);

    // الخصمُ النقديُّ المتاحُ **يُحسَب من شرطَي v164 معاً**: نسبةٌ بلا مهلةٍ
    // لا معنى لها، فكلتاهما صفرٌ = لا خصمَ معجَّل. والفاتورةُ تدخل الحسابَ
    // إن كان اليومُ لم يتجاوز مهلتَها بعد.
    final pct = party?.earlyPaymentDiscountPct ?? 0;
    final days = party?.earlyPaymentDiscountDays ?? 0;
    final now = DateTime.now();
    final hasDiscount = pct > 0 && days > 0;
    double discountOf(PartyOpenInvoiceRow o) {
      if (!hasDiscount) return 0;
      final deadline = o.invoiceDate.add(Duration(days: days));
      return now.isAfter(deadline) ? 0 : o.remaining * pct / 100;
    }

    final discount =
        open.fold<double>(0, (s, o) => s + discountOf(o));

    final kpis = <PicPosHubKpi>[
      PicPosHubKpi(
        icon: PhosphorIconsBold.warningOctagon,
        label: 'متأخر السداد',
        value: _money(overdueSum),
        tint: overdueSum > 0 ? _tintErr : _tintOk,
        vs: overdueSum > 0 ? 'فات استحقاقه' : 'لا متأخرات',
      ),
      PicPosHubKpi(
        icon: PhosphorIconsBold.clock,
        label: 'يستحق خلال ٧ أيام',
        value: _money(week),
        tint: week > 0 ? _tintErr : _tintOk,
        vs: 'التزام قريب',
      ),
      PicPosHubKpi(
        icon: PhosphorIconsBold.calendarCheck,
        label: 'يستحق ٨—٣٠ يوماً',
        value: _money(month),
        tint: _tintWarn,
        vs: 'ضمن الشهر',
      ),
      PicPosHubKpi(
        icon: PhosphorIconsBold.checkCircle,
        label: 'لم يحن',
        value: _money(later),
        tint: _tintOk,
        vs: 'فوق ٣٠ يوماً',
      ),
      // ⚠️ التصميمُ يضع هنا «الرصيد البنكي 186,400» ليُقارَن بالمستحقّ. وهو
      //    بيانةُ خزينةٍ لا بيانةُ طرف، وقراءتُها تربط كشفَ المورد بمستودعِ
      //    الخزينة كلِّه. فبقي الخصمُ النقديُّ — وهو الرقمُ الذي يغيّر قرارَ
      //    السداد فعلاً — والمقارنةُ بالبنك بندٌ لم يُطلَب.
      PicPosHubKpi(
        icon: PhosphorIconsBold.percent,
        label: 'خصم نقدي متاح',
        value: hasDiscount ? _money(discount) : 'لا خصم متفق',
        tint: hasDiscount && discount > 0 ? _tintOk : _tintIdle,
        vs: hasDiscount
            ? '${pct.toStringAsFixed(pct % 1 == 0 ? 0 : 1)}٪ خلال $days يوماً'
            : '',
      ),
    ];

    return _TabData(
      badge: '${open.length}',
      blocks: [
        PicPosHubKpiRow(items: kpis),
        _FilterableTable<PartyOpenInvoiceRow>(
          query: query,
          title: 'المستحق للمورد وتواريخه',
          subtitle: 'الخصم النقدي المتاح يُقارن بتكلفة الاحتفاظ بالنقد',
          columns: const [
            PicPosTableColumn('المستند', flex: 1.5),
            PicPosTableColumn('التاريخ', flex: 1.2),
            PicPosTableColumn('الاستحقاق', flex: 1.2),
            PicPosTableColumn('القيمة',
                flex: 1.2, align: PicPosCellAlign.end),
            PicPosTableColumn('المسدَّد',
                flex: 1.2, align: PicPosCellAlign.end),
            PicPosTableColumn('المتبقي',
                flex: 1.4, align: PicPosCellAlign.end),
            PicPosTableColumn('خصم نقدي', flex: 1.3),
            PicPosTableColumn('إجراء', flex: 1.2),
          ],
          groups: [
            (label: 'كل المستحق', items: open),
            (
              label: 'خلال ٧ أيام',
              items: open.where((o) => o.daysLate >= -7).toList()
            ),
            (
              label: 'بخصم نقدي',
              items: open.where((o) => discountOf(o) > 0).toList()
            ),
          ],
          buildRow: (o) => PicPosTableRow(cells: [
            PicPosTextCell(
              o.invoiceNumber,
              icon: PhosphorIconsBold.receipt,
              tint: o.overdue ? _tintErr : _tintWarn,
            ),
            PicPosTextCell(df.format(o.invoiceDate)),
            PicPosTextCell(
              df.format(o.dueDate),
              sub: o.overdue
                  ? 'تأخر ${o.daysLate} يوماً'
                  : 'باقٍ ${-o.daysLate} يوماً',
            ),
            PicPosTextCell(_money(o.total)),
            PicPosTextCell(o.paid == 0 ? '—' : _money(o.paid)),
            PicPosTextCell(_money(o.remaining)),
            discountOf(o) > 0
                ? PicPosTrendCell(_money(discountOf(o)), up: true)
                : const PicPosTextCell('—'),
            PicPosButtonCell(
              'سداد',
              icon: PhosphorIconsBold.handCoins,
              tint: _tintOk,
              onPressed: openVoucher,
            ),
          ]),
          totals: (rows) {
            var t = 0.0;
            var p = 0.0;
            var r = 0.0;
            var d = 0.0;
            for (final o in rows) {
              t += o.total;
              p += o.paid;
              r += o.remaining;
              d += discountOf(o);
            }
            return [
              _count(rows.length, 'بند'),
              '',
              '',
              _money(t),
              _money(p),
              _money(r),
              d > 0 ? _money(d) : '',
              '',
            ];
          },
        ),
        PicPosBarList(
          title: 'جدول الالتزامات القادمة',
          subtitle: 'ما علينا للمورد موزَّعاً على الأسابيع',
          items: [
            PicPosBarItem(
              icon: PhosphorIconsBold.warningOctagon,
              tint: _tintErr,
              label: 'متأخر الآن',
              sub: _count(open.where((o) => o.daysLate > 0).length, 'مستند'),
              value: overdueSum,
              caption: _pct(_ratio(overdueSum, overdueSum + week + month + later)),
              display: _money(overdueSum),
            ),
            PicPosBarItem(
              icon: PhosphorIconsBold.clock,
              tint: _tintErr,
              label: 'هذا الأسبوع',
              sub: _count(
                open.where((o) => o.daysLate <= 0 && o.daysLate >= -7).length,
                'مستند',
              ),
              value: week,
              caption: _pct(_ratio(week, overdueSum + week + month + later)),
              display: _money(week),
            ),
            PicPosBarItem(
              icon: PhosphorIconsBold.calendarCheck,
              tint: _tintWarn,
              label: 'خلال الشهر',
              sub: _count(
                open
                    .where((o) => o.daysLate < -7 && o.daysLate >= -30)
                    .length,
                'مستند',
              ),
              value: month,
              caption: _pct(_ratio(month, overdueSum + week + month + later)),
              display: _money(month),
            ),
            PicPosBarItem(
              icon: PhosphorIconsBold.checkCircle,
              tint: _tintOk,
              label: 'بعد الشهر',
              sub: _count(
                open.where((o) => o.daysLate < -30).length,
                'مستند',
              ),
              value: later,
              caption: _pct(_ratio(later, overdueSum + week + month + later)),
              display: _money(later),
            ),
          ],
        ),
      ],
    );
  }

  // ═══ ٣أ) مطابقة الدفعات — كشفُ العميل ═══════════════════════════════════
  Future<_TabData> _matchCustomerTab() async {
    final pid = partyId!;
    final pays = await _repo.getPartyPaymentMatches(
      partyId: pid,
      from: range.start,
      to: range.end,
    );
    if (pays.isEmpty) return const _TabData();
    final open =
        await _repo.getPartyOpenInvoices(partyId: pid, supplier: false);

    final matched = pays.where((p) => p.fullyMatched).toList();
    final loose = pays.where((p) => !p.fullyMatched).toList();
    final partial = open.where((o) => o.paid > 0).toList();

    final kpis = <PicPosHubKpi>[
      PicPosHubKpi(
        icon: PhosphorIconsBold.link,
        label: 'دفعات مطابَقة',
        value: '${matched.length}',
        tint: _tintOk,
        vs: _money(matched.fold<double>(0, (s, p) => s + p.amount)),
      ),
      PicPosHubKpi(
        icon: PhosphorIconsBold.linkBreak,
        label: 'غير مطابَقة',
        value: '${loose.length}',
        tint: loose.isEmpty ? _tintOk : _tintWarn,
        vs: _money(loose.fold<double>(0, (s, p) => s + p.unallocated)),
      ),
      PicPosHubKpi(
        icon: PhosphorIconsBold.receipt,
        label: 'فواتير مسدَّدة جزئياً',
        value: '${partial.length}',
        tint: partial.isEmpty ? _tintOk : _tintWarn,
        vs: _money(partial.fold<double>(0, (s, o) => s + o.remaining)),
      ),
      // ليس رقماً مقيساً بل **وصفُ سلوكِ النظام** — والدفعةُ فعلاً تُخصم من
      // أقدم فاتورةٍ ما لم تُربَط يدويّاً. وذكرُه هنا يشرح عمودَ «المقترحة».
      const PicPosHubKpi(
        icon: PhosphorIconsBold.gear,
        label: 'قاعدة المطابقة',
        value: 'الأقدم أولاً',
        tint: _tintBrand,
        vs: 'ما لم تُربط يدوياً',
      ),
    ];

    return _TabData(
      badge: '${loose.length}',
      blocks: [
        PicPosHubKpiRow(items: kpis),
        const PicPosSectionHeader(
          title: 'حالة مطابقة الدفعات',
          subtitle:
              'الدفعة غير المطابَقة تُنقص الرصيد الكلي لكنها لا تُقفل فاتورة '
              'بعينها — وهذا ما يُربك أعمار الدين',
          icon: PhosphorIconsBold.link,
          showDivider: false,
        ),
        // ⚠️ **تُمرَّر البطاقاتُ كاملةً بلا `take`**: القصُّ يقع في
        //    `_FilterableBoard` **بعد** الترشيح، وإلّا بحث المشغّلُ في ستٍّ
        //    وهو يظنّ أنّه يبحث في الكلّ.
        _FilterableBoard(
          query: query,
          columns: [
            PicPosBoardColumn(
              label: 'دفعات غير مطابَقة',
              icon: PhosphorIconsBold.linkBreak,
              tint: _tintWarn,
              total: loose.length,
              cards: [
                for (final p in loose)
                  PicPosBoardCard(
                    title: '${p.paymentNumber} · ${_money(p.amount)}',
                    subtitle: '${df.format(p.paymentDate)} · ${p.method}',
                    value: _money(p.unallocated),
                    meta: p.invoiceCount == 0
                        ? 'دفعة تحت الحساب بلا فاتورة'
                        : 'مخصَّصة جزئياً على ${p.invoiceCount} فاتورة',
                    metaIcon: p.invoiceCount == 0
                        ? PhosphorIconsBold.question
                        : PhosphorIconsBold.arrowRight,
                    metaTint: _tintWarn,
                  ),
              ],
            ),
            _suggestionColumn(loose, open),
            PicPosBoardColumn(
              label: 'مطابَقة بالفعل',
              icon: PhosphorIconsBold.link,
              tint: _tintOk,
              total: matched.length,
              cards: [
                for (final p in matched)
                  PicPosBoardCard(
                    title: p.paymentNumber,
                    subtitle: '${df.format(p.paymentDate)} · ${p.method}',
                    value: _money(p.amount),
                    meta: 'وُزّعت على ${p.invoiceCount} فاتورة',
                    metaIcon: PhosphorIconsBold.checkCircle,
                    metaTint: _tintOk,
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  /// عمودُ «المطابقةِ المقترحة» — **يُحسَب بقاعدة الأقدمِ أوّلاً** المعلنةِ في
  /// المؤشّر، لا يُنقَل من التصميم.
  ///
  /// ⚠️ **اقتراحٌ يُقرأ لا فعلٌ يُنفَّذ**: الربطُ اليدويُّ للدفعة بفاتورةٍ لم
  /// يُبنَ في هذه الجولة (أمرُ المالك)، فالبطاقةُ تقول ما **سيقع** بالقاعدة
  /// القائمة ولا تحمل زرّاً يوهم بغيرِ ذلك.
  PicPosBoardColumn _suggestionColumn(
    List<PartyPaymentMatchRow> loose,
    List<PartyOpenInvoiceRow> open,
  ) {
    final cards = <PicPosBoardCard>[];
    // نسخةٌ قابلةٌ للاستهلاك من المتبقّي على كلّ فاتورة، بترتيب الاستحقاق
    // (‏الاستعلامُ يعود مرتّباً تصاعديّاً بـ`due_at`).
    final pool = [
      for (final o in open)
        if (o.remaining > 0.01) (row: o, left: o.remaining),
    ].map((e) => _Pending(e.row, e.left)).toList();

    var idx = 0;
    for (final p in loose) {
      var left = p.unallocated;
      while (left > 0.01 && idx < pool.length) {
        final target = pool[idx];
        final take = left < target.left ? left : target.left;
        cards.add(PicPosBoardCard(
          title: '${p.paymentNumber} ← ${target.row.invoiceNumber}',
          subtitle:
              'استحقاق ${df.format(target.row.dueDate)} · ${target.row.bucket}',
          value: _money(take),
          meta: take >= target.left - 0.01
              ? 'يُقفل الفاتورة بالكامل'
              : 'سداد جزئي — يتبقّى ${_money(target.left - take)}',
          metaIcon: take >= target.left - 0.01
              ? PhosphorIconsBold.checkCircle
              : PhosphorIconsBold.arrowRight,
          metaTint: take >= target.left - 0.01 ? _tintOk : _tintBrand,
        ));
        left -= take;
        target.left -= take;
        if (target.left <= 0.01) idx++;
      }
      if (left > 0.01) {
        cards.add(PicPosBoardCard(
          title: '${p.paymentNumber} · متبقٍ',
          subtitle: 'لا فاتورة قائمة تستوعبه',
          value: _money(left),
          meta: 'يبقى تحت الحساب',
          metaIcon: PhosphorIconsBold.question,
          metaTint: _tintWarn,
        ));
      }
    }

    return PicPosBoardColumn(
      label: 'مطابقة مقترحة',
      icon: PhosphorIconsBold.lightbulb,
      tint: _tintBrand,
      total: cards.length,
      // بلا `take` — القصُّ في `_FilterableBoard` بعد الترشيح.
      cards: cards,
    );
  }

  // ═══ ٣ب) مطابقة الفواتير بالاستلام — كشفُ المورد ═════════════════════════
  //
  // ⚠️ **الأعمدةُ كمّيّاتٌ لا مبالغ.** التصميمُ يكتب «62,000» و«57,320» ج.م،
  //    و`getPurchaseOrderMatches` يعود بـ`purchase_order_items.quantity`
  //    و`received_quantity` و`purchase_invoice_items.quantity` — ثلاثُ
  //    **كمّيّات**. وتقييمُها بالسعر يقتضي سعرَ سطرِ الأمر وسعرَ سطرِ الفاتورة
  //    معاً (‏وفرقُهما هو «فرقُ السعر» نفسُه)، وهو استعلامٌ آخر. فالعمودُ
  //    يقول ما قِيس، والعنوانُ يقول إنّه كمّيّة.
  //
  // ⚠️ **والصفُّ سطرُ صنفٍ لا فاتورة**: الاستعلامُ يضمّ `purchase_order_items`
  //    فيعطي سطراً لكلّ صنفٍ في كلّ أمر. والتصميمُ يعدّ فواتير، فالعدّادُ هنا
  //    يقول «سطراً» صراحةً.
  Future<_TabData> _matchSupplierTab() async {
    final pid = partyId!;
    final rows = await _repo.getPurchaseOrderMatches(
      supplierId: pid,
      from: range.start,
      to: range.end,
    );
    if (rows.isEmpty) return const _TabData();

    final clean = rows.where((r) => r.clean).toList();
    final gaps = rows.where((r) => !r.clean).toList();
    final qtyGaps = rows.where((r) => r.qtyGap.abs() >= 0.001).toList();
    final billGaps = rows
        .where((r) => r.qtyGap.abs() < 0.001 && r.billingGap.abs() >= 0.001)
        .toList();
    final orders = rows.map((r) => r.orderId).toSet();

    final kpis = <PicPosHubKpi>[
      PicPosHubKpi(
        icon: PhosphorIconsBold.checkCircle,
        label: 'مطابقة ثلاثية سليمة',
        value: '${clean.length}',
        tint: _tintOk,
        vs: 'من ${rows.length} سطراً في ${orders.length} أمر',
      ),
      PicPosHubKpi(
        icon: PhosphorIconsBold.gitDiff,
        label: 'بها فروق',
        value: '${gaps.length}',
        tint: gaps.isEmpty ? _tintOk : _tintErr,
        vs: _pct(_ratio(gaps.length.toDouble(), rows.length.toDouble())),
      ),
      PicPosHubKpi(
        icon: PhosphorIconsBold.package,
        label: 'فروق استلام',
        value: '${qtyGaps.length}',
        tint: qtyGaps.isEmpty ? _tintOk : _tintWarn,
        vs: 'المستلم يخالف المطلوب',
      ),
      PicPosHubKpi(
        icon: PhosphorIconsBold.tag,
        label: 'فروق فوترة',
        value: '${billGaps.length}',
        tint: billGaps.isEmpty ? _tintOk : _tintErr,
        vs: 'المفوتر يخالف المستلم',
      ),
    ];

    return _TabData(
      badge: '${gaps.length}',
      blocks: [
        PicPosHubKpiRow(items: kpis),
        _FilterableTable<PoMatchRow>(
          query: query,
          title: 'مطابقة أمر الشراء بالمستلم بالمفوتر',
          subtitle: 'الفرق بين المستلم والمفوتر هو ما يُطالَب به المورد · كميات',
          minWidth: 860,
          columns: const [
            PicPosTableColumn('أمر الشراء', flex: 1.4),
            PicPosTableColumn('الصنف', flex: 1.6),
            PicPosTableColumn('المطلوب',
                flex: 1.1, align: PicPosCellAlign.end),
            PicPosTableColumn('المستلم',
                flex: 1.1, align: PicPosCellAlign.end),
            PicPosTableColumn('المفوتر',
                flex: 1.1, align: PicPosCellAlign.end),
            PicPosTableColumn('الفرق',
                flex: 1.2, align: PicPosCellAlign.end),
            PicPosTableColumn('نوع الفرق', flex: 1.5),
            PicPosTableColumn('إجراء', flex: 1.2),
          ],
          groups: [
            (label: 'الكل', items: rows),
            (label: 'بها فروق', items: gaps),
            (label: 'سليمة', items: clean),
          ],
          buildRow: (r) => PicPosTableRow(cells: [
            PicPosTextCell(
              r.orderNumber,
              sub: r.receivedAt == null
                  ? 'لم يُستلم بعد'
                  : 'استُلم ${df.format(r.receivedAt!)}',
              icon: PhosphorIconsBold.receipt,
              tint: r.clean ? _tintOk : _tintErr,
            ),
            PicPosTextCell(r.productName),
            PicPosTextCell(_qty(r.ordered)),
            PicPosTextCell(_qty(r.received)),
            PicPosTextCell(_qty(r.invoiced)),
            r.clean
                ? const PicPosTextCell('—')
                : PicPosTrendCell(
                    _qty(r.billingGap.abs() >= 0.001
                        ? r.billingGap
                        : r.qtyGap),
                    up: false,
                  ),
            PicPosTextCell(
              r.gapKind,
              tint: r.clean ? _tintOk : _tintErr,
            ),
            // ⚠️ **السطرُ السليمُ بلا زرّ**: لا مطالبةَ على ما طابق. والزرُّ
            //    يفتح المطالبةَ على **كلّ** الفروق لا على سطره وحدَه — فهي
            //    مراسلةٌ واحدةٌ تجمعها، وإرسالُ مطالبةٍ لكلّ سطرٍ يُغرق المورد.
            if (r.clean)
              const PicPosTextCell('—')
            else
              PicPosButtonCell(
                'مطالبة',
                icon: PhosphorIconsBold.bell,
                tint: _tintWarn,
                onPressed: () => openClaim(gaps),
              ),
          ]),
          totals: (list) {
            var o = 0.0;
            var rc = 0.0;
            var iv = 0.0;
            for (final r in list) {
              o += r.ordered;
              rc += r.received;
              iv += r.invoiced;
            }
            return [
              _count(list.length, 'سطراً'),
              '',
              _qty(o),
              _qty(rc),
              _qty(iv),
              _qty(iv - rc),
              '',
              '',
            ];
          },
        ),
      ],
    );
  }

  // ═══ ٤) الأوراق التجارية ════════════════════════════════════════════════
  //
  // ⚠️ **هذه التبويبةُ لا تتبع شريطَ المدى.** `getPartyPapers` يقرأ أوراقَ
  //    الطرف كلَّها بلا نافذةِ تاريخ — عمداً: ورقةٌ حُرِّرت قبل الفترة
  //    وتستحقّ بعدها **التزامٌ قائمٌ الآن**، وقصُّها بالمدى كان سيُخفي أخطرَ
  //    ما في الكشف. والعنوانُ يقول ذلك صراحةً.
  Future<_TabData> _papersTab() async {
    final papers = await _repo.getPartyPapers(partyId!);
    if (papers.isEmpty) return const _TabData();

    const liveStatuses = {
      'pending',
      'in_portfolio',
      'deposited',
      'deposited_for_collection',
    };
    List<CommercialPaperData> where(bool Function(CommercialPaperData) f) =>
        papers.where(f).toList();

    final live = where((p) => liveStatuses.contains(p.status));
    final endorsed = where((p) => p.status == 'endorsed');
    final cashed = where((p) => p.status == 'cashed');
    final bounced = where((p) => p.status == 'bounced');

    double sum(List<CommercialPaperData> l) =>
        l.fold<double>(0, (s, p) => s + p.amount);

    final kpis = <PicPosHubKpi>[
      // ⚠️ **التسميةُ لا تذكر الاتّجاه.** التصميمُ يقول «أوراق صادرة قائمة»
      //    لكشف المورد و«أوراق تحت التحصيل» لكشف العميل، وهو يفترض أنّ أوراقَ
      //    المورد صادرةٌ كلُّها وأوراقَ العميل واردةٌ كلُّها. و`getPartyPapers`
      //    يعود بأوراق الطرف **بالاتّجاهين** (وهو الصحيح: مورّدٌ قد يحمل شيكاً
      //    وارداً عن مرتجَع). فالعدّادُ يقول «قائمة» فقط، والاتّجاهُ يُقرأ في
      //    عمود «النوع» صفّاً صفّاً.
      PicPosHubKpi(
        icon: PhosphorIconsBold.note,
        label: 'أوراق قائمة',
        value: '${live.length}',
        tint: live.isEmpty ? _tintIdle : AppColors.primaryLight,
        vs: _money(sum(live)),
      ),
      PicPosHubKpi(
        icon: PhosphorIconsBold.arrowBendUpLeft,
        label: 'أوراق مُجيَّرة',
        value: '${endorsed.length}',
        tint: endorsed.isEmpty ? _tintIdle : _tintViolet,
        vs: _money(sum(endorsed)),
      ),
      PicPosHubKpi(
        icon: PhosphorIconsBold.warningOctagon,
        label: 'أوراق مرتدة',
        value: '${bounced.length}',
        tint: bounced.isEmpty ? _tintOk : _tintErr,
        vs: bounced.isEmpty ? 'سجل نظيف' : _money(sum(bounced)),
      ),
      PicPosHubKpi(
        icon: PhosphorIconsBold.checkCircle,
        label: isSupplier ? 'مخصومة' : 'محصَّلة',
        value: '${cashed.length}',
        tint: cashed.isEmpty ? _tintIdle : _tintOk,
        vs: _money(sum(cashed)),
      ),
    ];

    return _TabData(
      badge: '${papers.length}',
      blocks: [
        PicPosHubKpiRow(items: kpis),
        _FilterableTable<CommercialPaperData>(
          query: query,
          title: isSupplier
              ? 'الأوراق الصادرة والمقايضات'
              : 'الأوراق التجارية والضمانات',
          subtitle: isSupplier
              ? 'الشيك الصادر التزام قائم حتى يُخصم · كل أوراق المورد بلا حصر بالمدى'
              : 'الشيك تحت التحصيل لا يُنقص الذمة حتى تحصيله · كل أوراق العميل بلا حصر بالمدى',
          columns: const [
            PicPosTableColumn('الورقة', flex: 1.4),
            PicPosTableColumn('النوع', flex: 1.4),
            PicPosTableColumn('البنك', flex: 1.4),
            PicPosTableColumn('الاستحقاق', flex: 1.2),
            PicPosTableColumn('المبلغ',
                flex: 1.2, align: PicPosCellAlign.end),
            PicPosTableColumn('الحالة', flex: 1.4),
          ],
          groups: [
            (label: 'الكل', items: papers),
            (label: 'قائمة', items: live),
            (label: 'مُجيَّرة', items: endorsed),
            (label: isSupplier ? 'مخصومة' : 'محصَّلة', items: cashed),
            (label: 'مرتدة', items: bounced),
          ],
          buildRow: (p) => PicPosTableRow(cells: [
            PicPosTextCell(
              p.paperNumber,
              icon: PhosphorIconsBold.note,
              tint: _paperTint(p.status),
            ),
            PicPosTextCell(
              _paperType(p.type),
              sub: p.direction == 'issued' ? 'صادر' : 'وارد',
            ),
            PicPosTextCell(
              (p.bankName ?? '').isEmpty ? '—' : p.bankName!,
              sub: [
                if ((p.bankBranch ?? '').isNotEmpty) p.bankBranch!,
                if ((p.accountNumber ?? '').isNotEmpty) p.accountNumber!,
              ].join(' · '),
            ),
            PicPosTextCell(df.format(p.dueDate)),
            PicPosTextCell(_money(p.amount)),
            PicPosPillCell(_paperStatus(p.status), _paperTint(p.status)),
          ]),
          totals: (list) => [
            _count(list.length, 'ورقة'),
            '',
            '',
            '',
            _money(sum(list)),
            '',
          ],
        ),
      ],
    );
  }

  String _paperType(String t) => switch (t) {
        'cheque' => 'شيك',
        'promissory_note' => 'سند إذني',
        'bill_of_exchange' => 'كمبيالة',
        _ => t,
      };

  String _paperStatus(String s) => switch (s) {
        'pending' => 'معلق',
        'in_portfolio' => 'في الحافظة',
        'deposited' => 'مودع',
        'deposited_for_collection' => 'برسم التحصيل',
        'cashed' => 'محصَّل',
        'bounced' => 'مرتد',
        'endorsed' => 'مظهَّر',
        'cancelled' => 'ملغي',
        _ => s,
      };

  Color _paperTint(String s) => switch (s) {
        'cashed' => _tintOk,
        'bounced' => _tintErr,
        'endorsed' => _tintViolet,
        'deposited' || 'deposited_for_collection' => AppColors.primaryLight,
        'cancelled' => _tintIdle,
        _ => _tintWarn,
      };

  // ═══ ٥) ملفُّ الطرف ══════════════════════════════════════════════════════
  //
  // رسمُ «سلوك السداد — آخر ٦ فواتير» (عميل) و«الخصم النقدي — المُستغَل مقابلَ
  // المُهدَر» (مورد) صارا مبنيَّين على `getPartySettlementRows`: **صفٌّ لكلّ
  // فاتورةٍ** بتاريخ آخرِ سدادٍ لها. وكان الاثنان متعذّرَين ما دام المصدرُ
  // متوسّطاتٍ مجمَّعة.
  //
  // ⚠️ **والعمودُ لا يُرسَم لفاتورةٍ لم تُسدَّد بعد بقيمةٍ صفريّة**: «لم تُسدَّد»
  //    ليست «سُدّدت في صفرِ يوم». تُرسَم بقيمةِ عمرها الجاري وتُوسَم بذلك،
  //    فيُقرأ الفرق.
  Future<_TabData> _profileTab() async {
    final p = party;
    if (p == null) return const _TabData();
    final metrics =
        await _repo.getPartyProfileMetrics(partyId: p.id, supplier: isSupplier);
    final settlements =
        await _repo.getPartySettlementRows(partyId: p.id, supplier: isSupplier);

    final terms = p.paymentTermsDays;
    final discPct = p.earlyPaymentDiscountPct;
    final discDays = p.earlyPaymentDiscountDays;
    final hasDiscount = discPct > 0 && discDays > 0;
    final usage = _ratio(p.balance.abs(), p.creditLimit);

    final kpis = <PicPosHubKpi>[
      if (!isSupplier)
        PicPosHubKpi(
          icon: PhosphorIconsBold.creditCard,
          label: 'حد الائتمان',
          value: p.creditLimit == 0 ? 'بلا حد' : _money(p.creditLimit),
          tint: p.creditLimit == 0
              ? _tintIdle
              : (usage >= 100 ? _tintErr : (usage >= 80 ? _tintWarn : _tintOk)),
          vs: p.creditLimit == 0 ? 'لم يُحدَّد' : 'المستخدم ${_pct(usage)}',
        ),
      PicPosHubKpi(
        icon: PhosphorIconsBold.calendarCheck,
        label: isSupplier ? 'مدة السداد المتفقة' : 'مدة السماح',
        value: terms == 0 ? 'فوري' : '$terms',
        tint: terms == 0 ? _tintIdle : _tintBrand,
        vs: terms == 0 ? 'بلا أجل متفق' : 'يوماً',
      ),
      if (isSupplier)
        PicPosHubKpi(
          icon: PhosphorIconsBold.percent,
          label: 'خصم السداد المعجَّل',
          value: hasDiscount
              ? '${discPct.toStringAsFixed(discPct % 1 == 0 ? 0 : 1)}٪'
              : 'لا خصم',
          tint: hasDiscount ? _tintOk : _tintIdle,
          vs: hasDiscount ? 'خلال $discDays يوماً' : '',
        ),
      if (isSupplier)
        PicPosHubKpi(
          icon: PhosphorIconsBold.truck,
          label: 'الالتزام بمواعيد التوريد',
          value: _pctOrNone(metrics.onTimeDeliveryPct),
          tint: metrics.onTimeDeliveryPct == null
              ? _tintIdle
              : (metrics.onTimeDeliveryPct! >= 80 ? _tintOk : _tintWarn),
          vs: 'من ${metrics.receivedOrders} أمراً مستلماً',
        )
      else ...[
        PicPosHubKpi(
          icon: PhosphorIconsBold.timer,
          label: 'متوسط السداد بعد الاستحقاق',
          value: metrics.settledInvoices == 0
              ? 'لا بيانات'
              : '${metrics.avgSettlementDays.toStringAsFixed(0)} يوماً',
          tint: metrics.settledInvoices == 0
              ? _tintIdle
              : (metrics.avgSettlementDays > 0 ? _tintErr : _tintOk),
          vs: 'من ${metrics.settledInvoices} فاتورة مسدَّدة',
        ),
        PicPosHubKpi(
          icon: PhosphorIconsBold.star,
          label: 'الالتزام بالسداد',
          value: _pctOrNone(metrics.onTimeSettlementPct),
          tint: metrics.onTimeSettlementPct == null
              ? _tintIdle
              : (metrics.onTimeSettlementPct! >= 80 ? _tintOk : _tintWarn),
          vs: 'سُدِّدت في موعدها',
        ),
      ],
      if (isSupplier)
        PicPosHubKpi(
          icon: PhosphorIconsBold.star,
          label: 'تقييم المورد',
          // `null` = لم يُقيَّم — وهي حالةٌ مختلفةٌ عن «تقييمٌ منخفض».
          value: p.supplierRating == null ? 'لم يُقيَّم' : '${p.supplierRating}/5',
          tint: p.supplierRating == null
              ? _tintIdle
              : (p.supplierRating! >= 4
                  ? _tintOk
                  : (p.supplierRating! >= 3 ? _tintWarn : _tintErr)),
          vs: p.supplierRating == null ? 'حكم بشري لم يُسجَّل' : 'من ٥ درجات',
        ),
    ];

    final rows = <PicPosTableRow>[
      _profileRow(
        isSupplier ? 'اسم المورد' : 'اسم العميل',
        p.name,
        sub: (p.code ?? '').isEmpty ? '' : 'كود ${p.code}',
        icon: isSupplier
            ? PhosphorIconsBold.truck
            : PhosphorIconsBold.storefront,
        status: p.isActive ? 'نشط' : 'موقوف',
        tint: p.isActive ? _tintOk : _tintErr,
      ),
      _profileRow(
        'الهاتف',
        (p.phone ?? '').isEmpty ? '—' : p.phone!,
        icon: PhosphorIconsBold.phone,
        status: (p.phone ?? '').isEmpty ? 'ناقص' : 'مسجَّل',
        tint: (p.phone ?? '').isEmpty ? _tintWarn : _tintOk,
      ),
      _profileRow(
        'العنوان',
        (p.address ?? '').isEmpty ? '—' : p.address!,
        icon: PhosphorIconsBold.mapPin,
        status: (p.address ?? '').isEmpty ? 'ناقص' : 'مسجَّل',
        tint: (p.address ?? '').isEmpty ? _tintWarn : _tintOk,
      ),
      _profileRow(
        'الرقم الضريبي',
        [p.taxId, p.tin].where((v) => (v ?? '').isNotEmpty).join(' · ').isEmpty
            ? '—'
            : [p.taxId, p.tin]
                .where((v) => (v ?? '').isNotEmpty)
                .join(' · '),
        icon: PhosphorIconsBold.identificationCard,
        status: (p.taxId ?? p.tin ?? '').isEmpty ? 'ناقص' : 'موثَّق',
        tint: (p.taxId ?? p.tin ?? '').isEmpty ? _tintWarn : _tintOk,
      ),
      _profileRow(
        'حد الائتمان',
        p.creditLimit == 0 ? 'بلا حد' : _money(p.creditLimit),
        sub: p.creditLimit == 0 ? '' : 'المستخدم ${_pct(usage)}',
        icon: PhosphorIconsBold.creditCard,
        status: p.creditLimit == 0
            ? 'غير محدد'
            : (usage >= 100 ? 'تجاوز' : 'ضمن الحد'),
        tint: p.creditLimit == 0
            ? _tintIdle
            : (usage >= 100 ? _tintErr : _tintOk),
      ),
      _profileRow(
        isSupplier ? 'مدة السداد المتفقة' : 'مدة السماح',
        terms == 0 ? 'فوري' : '$terms يوماً',
        sub: 'يُشتق منها استحقاق كل فاتورة عند إصدارها',
        icon: PhosphorIconsBold.calendarCheck,
        status: terms == 0 ? 'بلا أجل' : 'مفعَّل',
        tint: terms == 0 ? _tintIdle : _tintOk,
      ),
      _profileRow(
        'خصم السداد المعجَّل',
        hasDiscount
            ? '${discPct.toStringAsFixed(discPct % 1 == 0 ? 0 : 1)}٪ خلال $discDays يوماً'
            : 'لا خصم',
        icon: PhosphorIconsBold.percent,
        status: hasDiscount ? 'مفعَّل' : 'غير مفعَّل',
        tint: hasDiscount ? _tintOk : _tintIdle,
      ),
      _profileRow(
        'الرصيد الحالي',
        _money(p.balance),
        sub: p.balance == 0
            ? 'مسوّى'
            : (p.balance > 0 ? 'مدين' : 'دائن'),
        icon: PhosphorIconsBold.scales,
        status: p.balance == 0
            ? 'صفر'
            : (p.balance > 0 ? 'له عليه' : 'عليه له'),
        tint: p.balance == 0 ? _tintIdle : _tintBrand,
      ),
      if (isSupplier)
        _profileRow(
          'تقييم المورد',
          p.supplierRating == null ? 'لم يُقيَّم' : '${p.supplierRating} من ٥',
          sub: 'حكم بشري لا يُشتق من البيانات',
          icon: PhosphorIconsBold.star,
          status: p.supplierRating == null ? 'بلا تقييم' : 'مسجَّل',
          tint: p.supplierRating == null ? _tintIdle : _tintOk,
        )
      else
        _profileRow(
          'تاريخ الإضافة',
          df.format(p.createdAt),
          icon: PhosphorIconsBold.clockCounterClockwise,
          status: p.isActive ? 'نشط' : 'موقوف',
          tint: p.isActive ? _tintOk : _tintErr,
        ),
    ];

    return _TabData(
      blocks: [
        PicPosHubKpiRow(items: kpis),
        // مجموعةٌ واحدةٌ («البيانات» في التصميم) — والحاويةُ هنا لأجل البحث
        // لا لأجل الشرائح: بحثُ الترويسة يجب أن يعمل في كلّ تبويبة، وتبويبةٌ
        // واحدةٌ لا يعمل فيها تجعل المشغّلَ يظنّ البحثَ معطَّلاً.
        _FilterableTable<PicPosTableRow>(
          query: query,
          title: isSupplier
              ? 'ملف المورد وشروط التعامل'
              : 'ملف العميل وشروط التعامل',
          subtitle: isSupplier
              ? 'الشروط المتفقة تُطبَّق تلقائياً على كل أمر شراء'
              : 'حد الائتمان يُفحص لحظياً قبل كل فاتورة آجلة',
          minWidth: 560,
          columns: const [
            PicPosTableColumn('البند', flex: 1.6),
            PicPosTableColumn('القيمة', flex: 2.2),
            PicPosTableColumn('الحالة', flex: 1.4),
          ],
          groups: [(label: 'البيانات', items: rows)],
          buildRow: (r) => r,
        ),
        // التصميمُ يضع الرسمَ **تحتَ** الجدول في هذه التبويبة وحدَها —
        // ولذلك كانت اللبناتُ قائمةً مرتَّبةً لا خاناتٍ مسمّاة.
        if (settlements.isNotEmpty)
          isSupplier
              ? _discountBars(settlements, discPct, discDays)
              : _settlementBars(settlements, terms),
      ],
    );
  }

  /// «سلوك السداد — آخر ٦ فواتير» في كشف العميل.
  ///
  /// العمودُ **أيّامُ السداد الفعليّة**، والمقارنةُ بمهلة السداد المتّفقة.
  /// وفاتورةٌ لم تُسدَّد تُرسَم بعمرها الجاري لا بصفر — فالصفرُ يُقرأ «سُدّدت
  /// فوراً» وهو عكسُ الحقيقة.
  PicPosBarList _settlementBars(List<PartySettlementRow> rows, int terms) {
    final now = DateTime.now();
    return PicPosBarList(
      title: 'سلوك السداد — آخر ${rows.length} فواتير',
      subtitle: terms == 0
          ? 'أيام السداد الفعلية · لا مهلة متفقة'
          : 'أيام السداد الفعلية مقابل مهلة $terms يوماً',
      items: [
        for (final r in rows.reversed)
          () {
            final paidDays = r.daysToPay;
            final ageDays = now.difference(r.invoiceDate).inDays;
            final days = paidDays ?? ageDays;
            final late = terms > 0 && days > terms;
            return PicPosBarItem(
              icon: paidDays == null
                  ? PhosphorIconsBold.clock
                  : (late
                      ? PhosphorIconsBold.warning
                      : PhosphorIconsBold.checkCircle),
              tint: paidDays == null
                  ? _tintIdle
                  : (late ? _tintErr : _tintOk),
              label: r.invoiceNumber,
              sub: paidDays == null
                  ? (r.paid > 0
                      ? 'سُدّد جزء منها — والباقي معلّق'
                      : 'لم تُسدَّد بعد')
                  : 'سُدّدت في ${_count(paidDays, 'يوماً')}',
              value: days.toDouble(),
              caption: _count(days, 'يوماً'),
              display: paidDays == null
                  ? 'جارية'
                  : (late ? 'تجاوز ${days - terms}' : 'داخل المهلة'),
            );
          }(),
      ],
    );
  }

  /// «الخصم النقدي — المُستغَل مقابل المُهدَر» في كشف المورد.
  ///
  /// ⚠️ **بلا شرطِ خصمٍ متّفقٍ لا رسم**: نسبةٌ صفرٌ أو مهلةٌ صفرٌ تعني «لا خصمَ
  /// معجَّل»، ورسمُ «فات الخصم» على فواتيرَ لا خصمَ لها أصلاً اتّهامٌ بلا سبب.
  /// فتُعرَض حينَها أيّامُ السداد وحدَها.
  PicPosBarList _discountBars(
    List<PartySettlementRow> rows,
    double pct,
    int days,
  ) {
    final has = pct > 0 && days > 0;
    if (!has) {
      return PicPosBarList(
        title: 'سلوك السداد — آخر ${rows.length} فواتير',
        subtitle: 'لا خصم معجَّل متفق عليه — تُعرض أيام السداد وحدها',
        items: [
          for (final r in rows.reversed)
            PicPosBarItem(
              icon: r.daysToPay == null
                  ? PhosphorIconsBold.clock
                  : PhosphorIconsBold.checkCircle,
              tint: r.daysToPay == null ? _tintIdle : _tintOk,
              label: r.invoiceNumber,
              sub: r.daysToPay == null
                  ? 'لم تُسدَّد بعد'
                  : 'سُدّدت في ${_count(r.daysToPay!, 'يوماً')}',
              value: (r.daysToPay ?? 0).toDouble(),
              caption: r.daysToPay == null ? '' : _count(r.daysToPay!, 'يوماً'),
              display: r.daysToPay == null ? 'جارية' : _money(r.total),
            ),
        ],
      );
    }

    return PicPosBarList(
      title: 'الخصم النقدي — المُستغَل مقابل المُهدَر',
      subtitle:
          '${pct.toStringAsFixed(pct % 1 == 0 ? 0 : 1)}٪ خلال $days يوماً · آخر ${rows.length} فواتير',
      items: [
        for (final r in rows.reversed)
          () {
            final captured = r.discountCaptured(days);
            final value = r.total * pct / 100;
            return PicPosBarItem(
              icon: captured == null
                  ? PhosphorIconsBold.clock
                  : (captured
                      ? PhosphorIconsBold.checkCircle
                      : PhosphorIconsBold.xCircle),
              tint: captured == null
                  ? _tintIdle
                  : (captured ? _tintOk : _tintErr),
              label: r.invoiceNumber,
              sub: r.daysToPay == null
                  ? 'لم تُسدَّد بعد — الخصم ما زال ممكناً'
                  : 'سُدّدت في ${_count(r.daysToPay!, 'يوماً')}',
              value: value,
              caption: captured == null
                  ? 'متاح'
                  : (captured ? 'استُغل الخصم' : 'فات الخصم'),
              // الإشارةُ تقول الاتّجاه: ما استُغلّ وفرٌ، وما فات خسارةٌ مقيسة.
              display: captured == null
                  ? _money(value)
                  : (captured ? '+${_money(value)}' : '−${_money(value)}'),
            );
          }(),
      ],
    );
  }

  PicPosTableRow _profileRow(
    String label,
    String value, {
    String sub = '',
    required IconData icon,
    required String status,
    required Color tint,
  }) =>
      PicPosTableRow(cells: [
        PicPosTextCell(label, icon: icon, tint: _tintBrand),
        PicPosTextCell(value, sub: sub.isEmpty ? null : sub),
        PicPosPillCell(status, tint),
      ]);
}

/// فاتورةٌ قائمةٌ ومقدارُ ما بقي منها أثناءَ توزيعِ الدفعات — قابلةٌ للتعديل
/// لأنّ توزيعَ الأقدمِ أوّلاً يستهلكها على مراحل.
class _Pending {
  _Pending(this.row, this.left);

  final PartyOpenInvoiceRow row;
  double left;
}

/// هل يطابق الصفُّ نصَّ البحث؟
///
/// يُقرأ **ما يراه المشغّلُ في الصفّ** — نصوصُ الخلايا الستّ كلُّها ومعها
/// أسطرُها الخافتة. والبحثُ في الكائن المصدر بدلاً منها كان سيجد ما لا يظهر
/// ويُخفق فيما يظهر (رقمُ المستند مثلاً مُنسَّقٌ في الخليّة لا في الصفّ).
///
/// و`PicPosCell` مغلقةٌ (`sealed`)، فالتبديلُ شاملٌ بالبناء: خليّةٌ جديدةٌ في
/// اللبنة تكسر الترجمةَ هنا بدل أن تسقط من البحث صامتة.
bool _rowMatches(PicPosTableRow row, String q) {
  for (final c in row.cells) {
    final text = switch (c) {
      PicPosTextCell(:final text, :final sub) => '$text ${sub ?? ''}',
      PicPosPillCell(:final text) => text,
      PicPosBarCell(:final text) => text,
      PicPosTrendCell(:final text) => text,
      PicPosButtonCell(:final text) => text,
      // زرُّ الاختيار لا نصَّ فيه — والبحثُ يقرأ ما يُقرأ.
      PicPosRadioCell() => '',
    };
    if (text.toLowerCase().contains(q)) return true;
  }
  return false;
}

/// جدولٌ شرائحُه **تُرشِّح فعلاً**، ويسمع بحثَ الترويسة.
///
/// `PicPosDataTable` بلا حالة (‏تأخذ `rows` و`selectedChip` جاهزَين)، وتحميلُ
/// التبويبة يقع في دالّةٍ غيرِ متزامنةٍ لا في `build`. فبلا هذه الحاويةِ كانت
/// الشريحةُ ستُرسَم ولا تفعل — وشريحةٌ لا تُرشِّح تكذب كزرٍّ لا يفعل.
class _FilterableTable<T> extends StatefulWidget {
  const _FilterableTable({
    super.key,
    required this.title,
    required this.columns,
    required this.groups,
    required this.buildRow,
    required this.query,
    this.subtitle,
    this.totals,
    this.minWidth = 760,
    this.headerAction,
  });

  final String title;
  final String? subtitle;
  final List<PicPosTableColumn> columns;

  /// ودجتٌ في آخر رأس الجدول — «تخصيص الأعمدة».
  final Widget? headerAction;

  /// شريحةٌ لكلّ مجموعة، وعدّادُها طولُها بعدَ البحث.
  final List<({String label, List<T> items})> groups;

  final PicPosTableRow Function(T) buildRow;

  /// مجاميعُ **المعروض** — تُعاد لكلّ شريحةٍ وبحثٍ على حدة.
  final List<String> Function(List<T>)? totals;

  final ValueListenable<String> query;

  final double minWidth;

  @override
  State<_FilterableTable<T>> createState() => _FilterableTableState<T>();
}

class _FilterableTableState<T> extends State<_FilterableTable<T>> {
  int _sel = 0;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: widget.query,
      builder: (context, raw, _) {
        final q = raw.trim().toLowerCase();
        // مدىً آمنٌ بعد تبديل الطرف أو المدى: عددُ المجموعات قد يتغيّر.
        final sel = _sel < widget.groups.length ? _sel : 0;

        /// يبني صفوفَ المجموعة ويُبقي المطابقَ منها وحدَه.
        List<({T item, PicPosTableRow row})> pairs(List<T> src) {
          final out = <({T item, PicPosTableRow row})>[];
          for (final it in src) {
            final row = widget.buildRow(it);
            if (q.isEmpty || _rowMatches(row, q)) out.add((item: it, row: row));
          }
          return out;
        }

        // النوعُ صريحٌ: `const []` في طرفِ الشرطيّة كانت تُنزل الاستدلالَ إلى
        // `dynamic` فتضيع أنواعُ الخانات في السطرين التاليين.
        final List<({T item, PicPosTableRow row})> shown =
            widget.groups.isEmpty ? [] : pairs(widget.groups[sel].items);

        return PicPosDataTable(
          title: widget.title,
          subtitle: widget.subtitle,
          minWidth: widget.minWidth,
          headerAction: widget.headerAction,
          columns: widget.columns,
          selectedChip: sel,
          chips: [
            for (var i = 0; i < widget.groups.length; i++)
              PicPosTableChip(
                label: widget.groups[i].label,
                // ⚠️ **العدّادُ يُحسَب بعد البحث.** ولو بقي طولَ المجموعة
                //    الكاملةِ لقرأ المشغّلُ «فواتير ١٨» فوقَ ثلاثة صفوف.
                count: q.isEmpty
                    ? '${widget.groups[i].items.length}'
                    : '${pairs(widget.groups[i].items).length}',
                onTap: () => setState(() => _sel = i),
              ),
          ],
          rows: [for (final p in shown) p.row],
          totals: widget.totals?.call([for (final p in shown) p.item]),
          emptyLabel: q.isEmpty
              ? 'لا صفوفَ لعرضها'
              : 'لا نتيجةَ للبحث عن «$raw»',
        );
      },
    );
  }
}

/// هل تطابق بطاقةُ اللوحة نصَّ البحث؟ — نفسُ قاعدةِ الصفّ: ما يُقرأ فيها.
bool _cardMatches(PicPosBoardCard c, String q) =>
    '${c.title} ${c.subtitle} ${c.value} ${c.meta}'.toLowerCase().contains(q);

/// لوحةُ حالاتٍ تسمع بحثَ الترويسة.
///
/// ⚠️ **بلا هذه الحاوية كان البحثُ يبدو معطَّلاً على تبويبةٍ كاملة**: تبويبةُ
/// «مطابقة الدفعات» لوحةٌ لا جدول، فكتابةُ رقمِ سندٍ فيها ما كانت تفعل شيئاً
/// ولا تقول لماذا.
///
/// ⚠️ **والقصُّ يقع هنا لا عند البناء**: تصلها البطاقاتُ **كاملةً** فتُرشِّحها
/// ثمّ تعرض منها [maxCards]. ولو قُصَّت قبلها لبحث المشغّلُ في ستٍّ ظانّاً
/// أنّه يبحث في الكلّ.
class _FilterableBoard extends StatelessWidget {
  const _FilterableBoard({required this.columns, required this.query});

  /// أعمدةٌ تحمل بطاقاتِها **كلَّها**، و`total` عددُها الكلّيّ.
  final List<PicPosBoardColumn> columns;
  final ValueListenable<String> query;

  /// ما يُعرَض من كلّ عمود — والعدّادُ في الرأس يقول الباقي.
  static const int _maxCards = 6;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: query,
      builder: (context, raw, _) {
        final q = raw.trim().toLowerCase();
        return PicPosStatusBoard(
          emptyLabel: q.isEmpty ? 'لا شيءَ هنا' : 'لا نتيجةَ للبحث',
          columns: [
            for (final col in columns)
              () {
                final kept = q.isEmpty
                    ? col.cards
                    : [
                        for (final c in col.cards)
                          if (_cardMatches(c, q)) c,
                      ];
                return PicPosBoardColumn(
                  label: col.label,
                  icon: col.icon,
                  tint: col.tint,
                  // العدّادُ يقول عددَ ما يخصّ الحالةَ الآن: الكلَّ بلا بحثٍ،
                  // والمطابقَ مع بحث.
                  total: q.isEmpty ? col.total : kept.length,
                  cards: kept.take(_maxCards).toList(),
                );
              }(),
          ],
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// جدولُ الكشف — أعمدةٌ تُختار، وصفٌّ يُختار
// ═══════════════════════════════════════════════════════════════════════════
//
// ⚠️ **لا يُعيد الاستعلام.** تبديلُ عمودٍ عرضٌ خالصٌ، فمفتاحُ `_futures` لا
// يحمل الأعمدةَ ولا الاختيار: يسمع الجدولُ مُبلِّغَين ويعيد بناءَ نفسِه.
//
// ⚠️ **والبحثُ يقرأ الظاهرَ وحدَه** بعد التخصيص — وهو عينُ عقد `_rowMatches`:
// «يُقرأ ما يراه المشغّل». فإخفاءُ عمودِ البيان يُخرجه من البحث أيضاً، ولو
// بقي مبحوثاً فيه لأعطى نتائجَ لا يُرى سببُها.
class _LedgerTable extends StatelessWidget {
  const _LedgerTable({
    required this.columnsVN,
    required this.selectedVN,
    required this.query,
    required this.groups,
    required this.subtitle,
    required this.cell,
    required this.total,
    required this.onCustomize,
  });

  final ValueListenable<Set<String>> columnsVN;
  final ValueNotifier<PartyStatementEntry?> selectedVN;
  final ValueListenable<String> query;
  final List<({String label, List<PartyStatementEntry> items})> groups;
  final String subtitle;
  final PicPosCell Function(String columnId, PartyStatementEntry e) cell;
  final String Function(String columnId, List<PartyStatementEntry> rows) total;
  final VoidCallback onCustomize;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: columnsVN,
      builder: (context, visible, _) {
        // الترتيبُ ترتيبُ الكتالوج دائماً — التفضيلُ يحفظ **أيَّها** لا أيُّها
        // أوّل.
        final cols = [
          for (final c in kStatementColumnCatalogue)
            if (visible.contains(c.id)) c,
        ];
        return ValueListenableBuilder<PartyStatementEntry?>(
          valueListenable: selectedVN,
          builder: (context, selected, _) =>
              _FilterableTable<PartyStatementEntry>(
            // ⚠️ **بلا مفتاحٍ عمداً**: حالةُ `_FilterableTable` هي الشريحةُ
            //    المنتقاةُ وحدَها، وهي فهرسٌ في `groups` لا في الأعمدة. ومفتاحٌ
            //    يحمل الأعمدةَ كان سيُعيد بناءَ الحالة عند كلّ تخصيصٍ فيرتدّ
            //    الترشيحُ إلى «كل الحركات» بلا سبب.
            query: query,
            title: 'كشف الحركة — الرصيد الجاري',
            subtitle: subtitle,
            headerAction: _CustomizeColumnsButton(onTap: onCustomize),
            columns: [
              for (final c in cols)
                PicPosTableColumn(c.label, flex: c.flex, align: c.align),
            ],
            groups: groups,
            buildRow: (e) => PicPosTableRow(
              cells: [for (final c in cols) cell(c.id, e)],
              selected: identical(selected, e),
              // نقرةٌ ثانيةٌ على المختار تُلغي الاختيار — وإلّا بقي الشريطُ
              // السفليُّ معلّقاً على صفٍّ لا سبيلَ للتخلّي عنه.
              onTap: () =>
                  selectedVN.value = identical(selected, e) ? null : e,
            ),
            totals: (rows) => [for (final c in cols) total(c.id, rows)],
          ),
        );
      },
    );
  }
}

class _CustomizeColumnsButton extends StatelessWidget {
  const _CustomizeColumnsButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.picposField,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: context.picposHairline),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(PhosphorIconsBold.slidersHorizontal,
                  size: 13, color: context.picposMuted),
              const SizedBox(width: 6),
              Text(
                'تخصيص الأعمدة',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: context.picposText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// شريطُ أفعال الكشف — **مثبَّتٌ أسفلَ التبويبة**.
///
/// ⚠️ **و«عرض المستند» يتبع وجودَ الوجهة لا وجودَ الصفّ**: صفُّ الرصيد
/// الافتتاحيّ بلا مستندٍ أصلاً، وتسويةُ رصيدٍ صفُّ خزنةٍ لا وثيقةَ له. فزرٌّ
/// يُعرَض على كلّ صفٍّ ثمّ لا يقفز في نصفها يُقرأ عطباً — والخريطةُ **مغلقةٌ**
/// بالاسم كما في «المستند المصدر».
class _StatementActionBar extends ConsumerWidget {
  const _StatementActionBar({
    required this.selectedVN,
    required this.onPrint,
    required this.onExport,
  });

  final ValueNotifier<PartyStatementEntry?> selectedVN;
  final Future<void> Function() onPrint;
  final Future<void> Function() onExport;

  /// مفرداتُ الكشف تلتقي مفرداتِ اليومية في خمسٍ وتفترق في واحدة.
  ///
  /// `sales_return_balance` صفُّ `safe_transactions` يحمل أثرَ مردودٍ لا
  /// فاتورةَ له (‏Spec 136 ISS-26) — فوجهتُه وجهةُ صفِّ الخزنة، لا شاشةُ
  /// فواتيرَ لن تجد فيها شيئاً بهذا المعرّف.
  String? _referenceTypeOf(PartyStatementEntry e) =>
      e.referenceType == 'sales_return_balance'
          ? 'safe_transaction'
          : e.referenceType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return ValueListenableBuilder<PartyStatementEntry?>(
      valueListenable: selectedVN,
      builder: (context, selected, _) {
        final target = selected == null
            ? null
            : resolveJournalSourceTarget(
                referenceType: _referenceTypeOf(selected),
                referenceId: selected.referenceId,
                allowedScreenIds: AppConfig.allowedScreenIds.toSet(),
              );

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
          decoration: BoxDecoration(
            color: context.picposCard,
            border: Border(top: BorderSide(color: context.picposHairline)),
          ),
          child: Row(
            children: [
              Icon(
                selected == null
                    ? PhosphorIconsBold.cursorClick
                    : PhosphorIconsBold.fileText,
                size: 15,
                color: context.picposMuted,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  selected == null
                      ? 'اختر سطراً لعرض مستنده'
                      : (target == null
                          ? '${selected.description} — لا مستندَ يُفتَح'
                          : '${selected.invoiceNumber ?? selected.description}'
                              ' · ${target.label}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelMedium?.copyWith(
                    color: context.picposMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () => unawaited(onExport()),
                icon: const Icon(PhosphorIconsBold.downloadSimple, size: 16),
                label: const Text('تصدير'),
                style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.success),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => unawaited(onPrint()),
                icon: const Icon(PhosphorIconsBold.printer, size: 16),
                label: const Text('طباعة الكشف'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                // 🔴 **الفتحُ عبر القناة لا مباشرةً**: مالكُ التابات وحدَه يعرف
                //    الصلاحيّاتِ وتاريخَ الرجوع وسقفَ التابات — وهي نفسُ قناةِ
                //    «المستند المصدر» في اليومية العامة.
                onPressed: target == null
                    ? null
                    : () => ref
                        .read(screenNavigationProvider.notifier)
                        .open(target.screenId.navigationIndex),
                icon: const Icon(PhosphorIconsBold.arrowSquareOut, size: 16),
                label: const Text('عرض المستند'),
              ),
            ],
          ),
        );
      },
    );
  }
}
