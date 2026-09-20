// شاشةُ «المشتريات الخارجيّة» — بندٌ أضافه المالك 2026-09-18.
//
// ═══ 🔴 ما الذي يجعل فاتورةً «خارجيّةً» أصلاً ═══
//
// **صفُّ `ImportPurchaseDetails` وحدَه** — لا العملةُ ولا المورّد. فشراءٌ
// بالدولار من مورّدٍ محلّيٍّ ليس استيراداً، واستيرادٌ سُعِّر بالعملة
// المحلّيّة يقع. والوسمُ يُكتَب **في معاملة الفاتورة** (راجع
// `createPurchaseInvoice`)، فلا فاتورةَ هنا بلا وسمها ولا وسمَ بلا فاتورته.
//
// ═══ 🔴 والتحويلُ يقع هنا — مرّةً واحدةً ═══
//
// النموذجُ يُدخِل ويعرض بعملةِ المورّد، وهذه الشاشةُ تحوّل قبل أن تسلّم
// المستودعَ. ولا تحويلَ أعمقَ: لمسار الشراء **مساران** (محلّيٌّ، وحمولةُ
// JSON إلى الخادم ثمّ نسخةٌ محلّيّةٌ مخبوءة)، فتحويلٌ في المحرّك يعني
// ثلاثةَ مواضعَ يتفرّق بينها رقمُ الذمّة بلا أن يظهر شيء.
//
// و`currencyId`/`exchangeRate` المخزَّنتان **لقطةٌ للسجلّ** لا مُعامِلٌ
// يُعاد تطبيقُه — ولا قارئَ يضرب بهما. راجع `import_purchase_plan.dart`.
//
// ═══ ⚠️ والتكاليفُ المحمَّلةُ تعيش هنا ولا مدخلَ جانبيَّ لها ═══
//
// قرارُ المالك: تُفعَّل و«تعيش داخلها وحدَها». فـ`ScreenId.landedCost` خرج
// من `picposRetired` ليعمل، وبقي **خارجَ** `kAllNavItemDefs` لـPicPos:
// يُبلَغ من هذه الشاشة وحدَها. وإخفاءُ المدخل وحدَه لا يكفي — النطاقُ هو
// البوّابةُ التي تسبق الصلاحيةَ نفسَها، فالموضعان معاً أو لا شيء.
//
// ═══ ⚠️ ولا استيرادَ لـ`data/database` هنا ═══
//
// حارسُ `presentation_db_import_guard` يمنع كلَّ ملفِّ عرضٍ **جديد** من
// استيرادها وقائمتُه البيضاءُ مقفولة. والأنواعُ تصل عبر
// `data/providers/providers.dart` — وهو استيرادٌ غيرُ مباشرٍ لا يخالفه.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/models/import_purchase_plan.dart';
import '../../../domain/models/picpos_invoice_draft.dart';
import '../../../domain/repositories/purchases_repository.dart';
import '../../invoice_form_picpos/picpos_invoice_form.dart';
import '../../landed_cost_picpos/screens/landed_cost_picpos_screen.dart';
import '../../picpos_shell/picpos_content_card.dart';
import '../../picpos_shell/picpos_data_table.dart';
import '../../picpos_shell/picpos_empty_state.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_section_header.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../../widgets/permission_guard.dart';
import '../../picpos_shell/picpos_attachments_panel.dart';

/// رقمُ الفاتورة يُولَّد **داخلَ معاملة الحفظ** (مواصفة ٠٦٦)، فلا يُدَّعى
/// رقمٌ بعينه قبل أن يُحجَز.
const String kImportInvoiceNumberPlaceholder = 'يُولَّد تلقائياً';

/// وكيلُ تخليصٍ مسجَّلٌ في دليل الأطراف.
typedef ImportAgentOption = ({int id, String name});

/// ما يخرج من لوح الاستيراد.
typedef ImportPanelValue = ({
  int? currencyId,
  double? localPerForeign,
  ImportDocumentFields doc,
});

/// سطرُ فاتورةٍ بعد التحويل إلى المحلّيّة.
typedef ImportSaveLine = ({
  int productId,
  double quantity,
  double unitCost,
  double taxRate,
  double taxAmount,
  double discount,
  String? unitName,
});

/// تحويلُ ما يخرج من `PicPosInvoiceForm` إلى المحلّيّة.
///
/// ⚠️ **والكمّيّةُ والنسبةُ لا تُضرَبان**: ليستا مالاً. وضربُ `taxRate`
///    كان يجعل ضريبةَ ١٤٪ ضريبةَ ٠٫٢٨٪ بسعرٍ ٠٫٠٢ — رقمٌ صغيرٌ لا رسالةَ
///    خطأٍ فيه.
///
/// 🔴 **و`taxAmount` يُحوَّل ولا يُعاد حسابُه**: إعادةُ حسابه من الصافي
///    المحوَّل تعطي نفسَ الرقم رياضيّاً وتُقرَّب مرّةً ثانية، فيفترق مجموعُ
///    ضرائبِ السطور عن الضريبة التي عرضها النموذجُ ووافق عليها المستخدم.
List<ImportSaveLine> convertFormItemsToLocal({
  required List<Map<String, dynamic>> items,
  required double localPerForeign,
}) {
  double money(Object? v) => (v as num?)?.toDouble() ?? 0;
  return [
    for (final it in items)
      (
        productId: it['productId'] as int,
        quantity: money(it['quantity']),
        unitCost: foreignToLocal(
            foreign: money(it['unitCost']), localPerForeign: localPerForeign),
        taxRate: money(it['taxRate']),
        taxAmount: foreignToLocal(
            foreign: money(it['taxAmount']), localPerForeign: localPerForeign),
        discount: foreignToLocal(
            foreign: money(it['discount']), localPerForeign: localPerForeign),
        unitName: it['selectedUnitName'] as String?,
      ),
  ];
}

/// العملاتُ النشطةُ للمنتقي — **والمحلّيّةُ ليست منها**.
///
/// ⚠️ اختيارُ العملة المحلّيّة يكتب `currencyId` بسعرِ ١: صفٌّ يقول «عملةٌ
///    أجنبيّة» وهو محلّيّ، ويُرشَّح لاحقاً في تقارير الاستيراد بلا معنى.
///    فالمحلّيّةُ هي **غيابُ** الاختيار لا خيارٌ فيه.
List<ImportCurrencyOption> importCurrencyOptions(List<Currency> all) => [
      for (final c in all)
        if (c.isActive && !c.isDefault)
          (
            id: c.id,
            code: c.code,
            name: c.name,
            symbol: c.symbol,
            localPerForeign: c.exchangeRate,
            isBase: c.isDefault,
          ),
    ];

final importPurchaseRowsProvider =
    FutureProvider.autoDispose<List<ImportPurchaseRow>>((ref) async {
  // ⚠️ **يراقب بثَّ الجدولَين معاً**: الفاتورةُ تتغيّر بلا أن يتغيّر وسمُها
  //    (سدادٌ، إلغاء، ورقةُ تحميلٍ تُطبَّق)، فمراقبةُ الوسم وحدَه تُجمّد
  //    أعمدةَ المبلغ والحالة حتى يُعاد فتحُ الشاشة.
  ref.watch(purchaseInvoicesChangeProvider);
  return ref.read(importPurchasesRepositoryProvider).getRows();
});

final importCurrenciesProvider =
    FutureProvider.autoDispose<List<ImportCurrencyOption>>((ref) async {
  final db = ref.watch(databaseProvider);
  return importCurrencyOptions(await db.getActiveCurrencies());
});

// ════════════════════════════════════════════════════════════════════════
// لوحُ الاستيراد — العملةُ وسعرُها والحقولُ المستنديّة
// ════════════════════════════════════════════════════════════════════════

class ImportDocumentPanel extends StatefulWidget {
  const ImportDocumentPanel({
    super.key,
    required this.currencies,
    required this.agents,
    required this.onChanged,
    this.initial,
    this.enabled = true,
    this.showCurrency = true,
  });

  final List<ImportCurrencyOption> currencies;
  final List<ImportAgentOption> agents;
  final ValueChanged<ImportPanelValue> onChanged;
  final ImportPanelValue? initial;
  final bool enabled;

  /// ‏`false` في تحرير **الأوراق وحدَها** بعد وصولها.
  ///
  /// 🔴 **والعملةُ لا تُحرَّر بعد الترحيل.** المبالغُ المخزَّنةُ محلّيّةٌ
  /// حُوِّلت مرّةً واحدة، فتبديلُ السعر لاحقاً يُبدّل **وصفَ** الصفِّ ولا
  /// يُبدّل مبلغاً — فيصير المستندُ يقول «حُوِّلت من USD @ 0.9» فوق أرقامٍ
  /// حُسبت بـ0.71، وهو كذبٌ لا يُكشَف بأيّ فحصِ اتّزان.
  final bool showCurrency;

  @override
  State<ImportDocumentPanel> createState() => _ImportDocumentPanelState();
}

class _ImportDocumentPanelState extends State<ImportDocumentPanel> {
  int? _currencyId;
  int? _agentId;
  late final TextEditingController _rate;
  late final TextEditingController _customs;
  late final TextEditingController _bl;
  late final TextEditingController _country;
  late final TextEditingController _port;
  late final TextEditingController _lc;
  late final TextEditingController _agentName;
  late final TextEditingController _notes;

  @override
  void initState() {
    super.initState();
    final v = widget.initial;
    _currencyId = v?.currencyId;
    _agentId = v?.doc.clearingAgentPartyId;
    _rate = TextEditingController(
        text: v?.localPerForeign == null ? '' : '${v!.localPerForeign}');
    _customs = TextEditingController(text: v?.doc.customsDeclarationNo ?? '');
    _bl = TextEditingController(text: v?.doc.billOfLading ?? '');
    _country = TextEditingController(text: v?.doc.countryOfOrigin ?? '');
    _port = TextEditingController(text: v?.doc.port ?? '');
    _lc = TextEditingController(text: v?.doc.letterOfCredit ?? '');
    _agentName = TextEditingController(text: v?.doc.clearingAgentName ?? '');
    _notes = TextEditingController(text: v?.doc.notes ?? '');
  }

  @override
  void dispose() {
    for (final c in [
      _rate,
      _customs,
      _bl,
      _country,
      _port,
      _lc,
      _agentName,
      _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  ImportCurrencyOption? get _picked {
    for (final c in widget.currencies) {
      if (c.id == _currencyId) return c;
    }
    return null;
  }

  double? get _rateValue =>
      _currencyId == null ? null : double.tryParse(_rate.text.trim());

  ImportDocumentFields get _doc => normalizeImportDocument(
        customsDeclarationNo: _customs.text,
        billOfLading: _bl.text,
        countryOfOrigin: _country.text,
        port: _port.text,
        letterOfCredit: _lc.text,
        clearingAgentPartyId: _agentId,
        clearingAgentName: _agentName.text,
        notes: _notes.text,
      );

  /// سببُ منعِ الحفظ، أو `null` إن جاز.
  String? get blockReason => widget.showCurrency
      ? (validateExchangeRate(
            currencyId: _currencyId,
            localPerForeign: _rateValue,
          ) ??
          validateImportDocument(_doc))
      : validateImportDocument(_doc);

  void _emit() {
    setState(() {});
    widget.onChanged(
      (currencyId: _currencyId, localPerForeign: _rateValue, doc: _doc),
    );
  }

  @override
  Widget build(BuildContext context) {
    final picked = _picked;
    final block = blockReason;
    return PicPosContentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PicPosSectionHeader(
            title: 'بيانات الاستيراد',
            subtitle: 'العملة وسعر يومها، وأوراقُ الشحن والتخليص',
            icon: PhosphorIconsBold.globeHemisphereEast,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (widget.showCurrency)
              _box(
                width: 220,
                label: 'العملة',
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int?>(
                    key: const Key('import_currency'),
                    value: _currencyId,
                    isExpanded: true,
                    onChanged: widget.enabled
                        ? (v) {
                            _currencyId = v;
                            // السعرُ يُملأ من العملة عند اختيارها، ويبقى
                            // **قابلاً للتحرير**: سعرُ الصفقة قد يخالف
                            // المسجَّل، والمخزَّنُ هو ما وقّع عليه المشتري.
                            if (v == null) {
                              _rate.text = '';
                            } else {
                              final c = _picked;
                              if (c != null && _rate.text.trim().isEmpty) {
                                _rate.text = '${c.localPerForeign}';
                              }
                            }
                            _emit();
                          }
                        : null,
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        // ⚠️ خيارٌ صريحٌ لا فراغ: «بلا اختيار» يُقرأ
                        //    «نسيتُ»، وهذا قرارٌ يُتّخذ.
                        child: Text('محلّيّة — بلا تحويل'),
                      ),
                      for (final c in widget.currencies)
                        DropdownMenuItem<int?>(
                          value: c.id,
                          child: Text('${c.code} — ${c.name}'),
                        ),
                    ],
                  ),
                ),
              ),
              if (widget.showCurrency && picked != null)
                _box(
                  width: 200,
                  label: 'سعر الصرف (${picked.code} ١ = ؟)',
                  child: TextField(
                    key: const Key('import_rate'),
                    controller: _rate,
                    enabled: widget.enabled,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      hintText: '0.00',
                    ),
                    onChanged: (_) => _emit(),
                  ),
                ),
              _field('import_customs', 'البيان الجمركي', _customs, 200),
              _field('import_bl', 'بوليصة الشحن', _bl, 200),
              _field('import_country', 'بلد المنشأ', _country, 170),
              _field('import_port', 'الميناء', _port, 170),
              _field('import_lc', 'الاعتماد المستندي', _lc, 200),
              _box(
                width: 220,
                label: 'وكيل التخليص',
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int?>(
                    key: const Key('import_agent'),
                    value: _agentId,
                    isExpanded: true,
                    onChanged: widget.enabled
                        ? (v) {
                            _agentId = v;
                            if (v != null) _agentName.clear();
                            _emit();
                          }
                        : null,
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('غير مسجَّل — أكتب الاسم'),
                      ),
                      for (final a in widget.agents)
                        DropdownMenuItem<int?>(
                          value: a.id,
                          child: Text(a.name),
                        ),
                    ],
                  ),
                ),
              ),
              if (_agentId == null)
                _field('import_agent_name', 'اسم الوكيل', _agentName, 220),
              _field('import_notes', 'ملاحظات', _notes, 260),
            ],
          ),
          if (widget.showCurrency && picked != null) ...[
            const SizedBox(height: 8),
            Text(
              'الأسعارُ في الجدول بـ${picked.code}. يُحوَّل الإجماليُّ إلى '
              '${AppConstants.currencySymbolEn} بسعرِ يومِه عند الحفظ، '
              'والذمّةُ محلّيّةٌ — فلا فروقَ صرفٍ لاحقاً.',
              key: const Key('import_rate_hint'),
              style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
            ),
          ],
          if (block != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(PhosphorIconsBold.warningCircle,
                    size: 14, color: AppColors.warning),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    block,
                    key: const Key('import_block_reason'),
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.warning),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _field(
    String key,
    String label,
    TextEditingController c,
    double width,
  ) =>
      _box(
        width: width,
        label: label,
        child: TextField(
          key: Key(key),
          controller: c,
          enabled: widget.enabled,
          decoration: const InputDecoration(
            border: InputBorder.none,
            isDense: true,
          ),
          onChanged: (_) => _emit(),
        ),
      );

  Widget _box({
    required double width,
    required String label,
    required Widget child,
  }) =>
      Builder(builder: (context) => SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: AlignmentDirectional.centerStart,
              decoration: BoxDecoration(
                color: context.picposField,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: context.picposHairline),
              ),
              child: child,
            ),
          ],
        ),
      ));
}

// ════════════════════════════════════════════════════════════════════════
// الشاشة
// ════════════════════════════════════════════════════════════════════════

class ImportPurchasesPicposScreen extends ConsumerStatefulWidget {
  const ImportPurchasesPicposScreen({super.key});

  @override
  ConsumerState<ImportPurchasesPicposScreen> createState() =>
      _ImportPurchasesPicposScreenState();
}

class _ImportPurchasesPicposScreenState
    extends ConsumerState<ImportPurchasesPicposScreen> {
  bool _showLanded = false;

  @override
  Widget build(BuildContext context) {
    if (_showLanded) return _landedBody();

    final rows = ref.watch(importPurchaseRowsProvider);
    return PicPosScreenScaffold(
      title: 'المشتريات الخارجيّة',
      subtitle:
          'فواتيرُ استيرادٍ بأوراقها — البيانُ الجمركيُّ وبوليصةُ الشحن والاعتمادُ المستنديّ',
      icon: PhosphorIconsBold.globeHemisphereEast,
      headerActions: [
        OutlinedButton.icon(
          key: const Key('import_open_landed'),
          onPressed: () => setState(() => _showLanded = true),
          icon: const Icon(PhosphorIconsBold.stackPlus, size: 16),
          label: const Text('التكاليف المحمّلة'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          key: const Key('import_new_invoice'),
          onPressed: _openForm,
          icon: const Icon(PhosphorIconsBold.plus, size: 16),
          label: const Text('فاتورة استيراد جديدة'),
        ),
      ],
      body: rows.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => PicPosEmptyState(
          icon: PhosphorIconsBold.warningCircle,
          title: 'تعذّرت القراءة',
          hint: '$e',
        ),
        data: _table,
      ),
    );
  }

  /// شاشةُ التكاليف المحمَّلة كاملةً — بشريطِ رجوعٍ فوقها.
  ///
  /// ⚠️ **ولا نسخةَ مختصرةٌ منها هنا.** المحرّكُ مبنيٌّ والشاشةُ مبنيّةٌ
  ///    ومختبَرة، ونسخةٌ ثانيةٌ للتوزيع أو التطبيق كانت ستفترق عنها عند
  ///    أوّل إصلاح — وهي تقيّد على المخزون وتبدّل متوسّطَ التكلفة.
  Widget _landedBody() => Column(
        children: [
          Material(
            color: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    key: const Key('import_landed_back'),
                    onPressed: () => setState(() => _showLanded = false),
                    icon: const Icon(PhosphorIconsBold.arrowUUpLeft, size: 16),
                    label: const Text('رجوع إلى المشتريات الخارجيّة'),
                  ),
                ],
              ),
            ),
          ),
          const Expanded(child: LandedCostPicposScreen()),
        ],
      );

  Widget _table(List<ImportPurchaseRow> rows) {
    if (rows.isEmpty) {
      return const PicPosEmptyState(
        icon: PhosphorIconsBold.globeHemisphereEast,
        title: 'لا فواتيرَ استيرادٍ بعد',
        hint:
            'الفاتورةُ تصير خارجيّةً بوسمها — وهو يُكتَب مع الفاتورة في هذه الشاشة.',
      );
    }
    return SingleChildScrollView(
      child: PicPosDataTable(
        title: 'فواتير الاستيراد',
        // ⚠️ **والأوراقُ تصل بعد البضاعة.** البيانُ الجمركيُّ يُخلَّص بعد
        //    الوصول، والاعتمادُ يُسوَّى لاحقاً — فتحريرُها بابٌ لازمٌ لا
        //    زينة. والمبالغُ **لا تُحرَّر هنا**: تلك فاتورةٌ تُعاد.
        subtitle: '${rows.length} فاتورة · اضغط الصفَّ لتحرير أوراقه',
        columns: const [
          PicPosTableColumn('الفاتورة', flex: 1.4),
          PicPosTableColumn('المورّد', flex: 1.4),
          PicPosTableColumn('المنشأ / الميناء', flex: 1.4),
          PicPosTableColumn('البيان الجمركي', flex: 1.2),
          PicPosTableColumn('الإجمالي', flex: 1, align: PicPosCellAlign.end),
          PicPosTableColumn('التكاليف المحمّلة',
              flex: 1.2, align: PicPosCellAlign.end),
          PicPosTableColumn('', flex: .9, align: PicPosCellAlign.end),
        ],
        rows: [
          for (final r in rows)
            PicPosTableRow(onTap: () => _editPapers(r), cells: [
              PicPosTextCell(
                r.invoice.invoiceNumber,
                sub: _dateLabel(r.invoice.invoiceDate),
                bold: true,
              ),
              PicPosTextCell(r.supplierName, sub: r.clearingAgent),
              PicPosTextCell(
                [
                  if (r.details.countryOfOrigin != null)
                    r.details.countryOfOrigin!,
                  if (r.details.port != null) r.details.port!,
                ].join(' · '),
                sub: r.details.billOfLading,
              ),
              PicPosTextCell(
                r.details.customsDeclarationNo ?? '—',
                sub: r.details.letterOfCredit == null
                    ? null
                    : 'اعتماد ${r.details.letterOfCredit}',
              ),
              // 🔴 **الإجماليُّ محلّيٌّ دائماً** — وهو ما دخل الذمّةَ
              //    والأستاذ. ورمزُ العملة الأجنبيّة يُعرَض **وصفاً** لا
              //    وحدةً لهذا الرقم.
              PicPosTextCell(
                r.invoice.total.toStringAsFixed(AppConstants.decimalPlaces),
                sub: r.currencyCode == null
                    ? null
                    : 'حُوِّلت من ${r.currencyCode}'
                        '${r.invoice.exchangeRate == null ? '' : ' @ ${r.invoice.exchangeRate}'}',
              ),
              PicPosTextCell(
                r.landedApplied.toStringAsFixed(AppConstants.decimalPlaces),
                // المسوّدةُ **لا تُجمَع** مع المطبَّق: ورقةٌ لم تُقيَّد
                // تكلفةً لم تدخل الدفتر، وجمعُها يقرأ رقماً لم يقع.
                sub: r.landedDraft > 0
                    ? 'مسوّدة ${r.landedDraft.toStringAsFixed(AppConstants.decimalPlaces)}'
                    : null,
                tint: r.landedApplied > 0 ? AppColors.success : null,
              ),
              PicPosButtonCell(
                'تحميل',
                icon: PhosphorIconsBold.stackPlus,
                tint: AppColors.primary,
                onPressed: () => setState(() => _showLanded = true),
              ),
            ]),
        ],
      ),
    );
  }

  /// تحريرُ الحقول المستنديّة لفاتورةٍ موسومةٍ سلفاً.
  ///
  /// 🔴 **ولا عملةَ فيه** — راجع [ImportDocumentPanel.showCurrency]: تبديلُ
  ///    السعر بعد الترحيل يُبدّل وصفَ الصفِّ ولا يُبدّل مبلغاً، فيصير
  ///    المستندُ يقول سعراً لم يُحسَب به.
  Future<void> _editPapers(ImportPurchaseRow r) async {
    if (!await ensurePermission(
      ref,
      context,
      PermissionCodes.purchasesEdit,
      actionName: 'تعديل أوراق الاستيراد',
    )) {
      return;
    }
    if (!mounted) return;

    // ⚠️ **عبر المزوِّد لا القاعدةِ مباشرةً**: قراءةُ drift داخلَ منطقةٍ
    //    وهميّةِ الزمن لا تكتمل أبداً، فبابٌ يقرأ القاعدةَ رأساً يصير
    //    غيرَ قابلٍ للقياس في اختبار ودجت — وهو ما وقع فعلاً في أوّل
    //    صياغةٍ لاختبار التركيب.
    //
    // 🔴 **والمزوِّدُ يُبقى حيّاً طوالَ الانتظار.** `allSuppliersProvider`
    //    ‏`autoDispose`، و`ref.read(p.future)` **لا يُنشئ مستمعاً يُبقيه
    //    حيّاً** — فتُبنى نسختُه ويبدأ البثُّ وتُرمى قبل أن يصل أوّلُ عنصر،
    //    ولا يكتمل المستقبَلُ أبداً. والنتيجةُ **زرٌّ ميّتٌ بصمت**: نقرةٌ لا
    //    يتبعها حوارٌ ولا رسالة. وقد وقع فعلاً وأمسكه اختبارُ التركيب.
    final keepAlive = ref.listenManual(allSuppliersProvider, (_, _) {});
    final List<Party> suppliers;
    try {
      suppliers = await ref
          .read(allSuppliersProvider.future)
          .timeout(const Duration(seconds: 10));
    } finally {
      keepAlive.close();
    }
    if (!mounted) return;

    var value = (
      currencyId: null,
      localPerForeign: null,
      doc: normalizeImportDocument(
        customsDeclarationNo: r.details.customsDeclarationNo,
        billOfLading: r.details.billOfLading,
        countryOfOrigin: r.details.countryOfOrigin,
        port: r.details.port,
        letterOfCredit: r.details.letterOfCredit,
        clearingAgentPartyId: r.details.clearingAgentPartyId,
        clearingAgentName: r.details.clearingAgentName,
        notes: r.details.notes,
      ),
    ) as ImportPanelValue;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('أوراق ${r.invoice.invoiceNumber}'),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ImportDocumentPanel(
                  key: const Key('import_papers_panel'),
                  currencies: const [],
                  showCurrency: false,
                  agents: [
                    for (final s in suppliers) (id: s.id, name: s.name)
                  ],
                  initial: value,
                  onChanged: (v) => value = v,
                ),
                const SizedBox(height: 14),
                // v176 / §٨ — البيانُ الجمركيُّ وبوليصةُ الشحن
                // **ورقٌ بطبيعته** — §٨٫٤ قرار ٢: «والخارجيّةُ أولاها».
                PicPosAttachmentsPanel(
                  entityType: 'import_purchase',
                  entityId: r.details.id,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            key: const Key('import_papers_save'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('حفظ الأوراق'),
          ),
        ],
      ),
    );
    if (saved != true || !mounted) return;

    try {
      await ref.read(importPurchasesRepositoryProvider).updateDetails(
            purchaseInvoiceId: r.invoice.id,
            fields: value.doc,
          );
      ref.invalidate(importPurchaseRowsProvider);
      if (mounted) {
        AppToast.show(context, 'حُفظت الأوراق', type: ToastType.success);
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'فشل الحفظ: $e', type: ToastType.error);
      }
    }
  }

  String _dateLabel(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  Future<void> _openForm() async {
    if (!await ensurePermission(
      ref,
      context,
      PermissionCodes.purchasesCreate,
      actionName: 'فاتورة استيراد جديدة',
    )) {
      return;
    }
    if (!mounted) return;

    // ⚠️ **المزوِّداتُ تُبقى حيّةً طوالَ الانتظار.** `ref.read(p.future)` على
    //    مزوِّدٍ `autoDispose` لا يُنشئ مستمعاً، فتُرمى نسختُه قبل أن يصل
    //    أوّلُ عنصرٍ ولا يكتمل المستقبَلُ أبداً — والزرُّ يموت بصمت. وهو
    //    عينُ العطب المقيس في `purchases_picpos_crud`.
    final keepAlive = <ProviderSubscription<Object?>>[
      ref.listenManual(allWarehousesProvider, (_, _) {}),
      ref.listenManual(allCostCentersProvider, (_, _) {}),
      ref.listenManual(posDefaultTaxPercentProvider, (_, _) {}),
      ref.listenManual(importCurrenciesProvider, (_, _) {}),
    ];
    try {
      final db = ref.read(databaseProvider);
      final suppliers = await db.getSuppliers().timeout(
            const Duration(seconds: 10),
          );
      final products =
          await db.getAllProducts().timeout(const Duration(seconds: 10));
      final warehouses = await ref
          .read(allWarehousesProvider.future)
          .timeout(const Duration(seconds: 10));
      final costCenters = await ref
          .read(allCostCentersProvider.future)
          .timeout(const Duration(seconds: 10));
      final taxRate = await ref
          .read(posDefaultTaxPercentProvider.future)
          .timeout(const Duration(seconds: 10));
      final currencies = await ref
          .read(importCurrenciesProvider.future)
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;

      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierLabel: 'PicPos Import Purchase',
        transitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (dialogContext, _, _) => _ImportInvoiceDialog(
          currencies: currencies,
          agents: [for (final s in suppliers) (id: s.id, name: s.name)],
          suppliers: [
            for (final s in suppliers)
              PicPosPartyOption(
                id: s.id,
                name: s.name,
                meta: s.phone ?? '',
                paymentTermsDays: s.paymentTermsDays,
              ),
          ],
          products: [
            for (final p in products)
              PicPosProductOption(
                id: p.id,
                name: p.name,
                sub: p.barcode ?? '',
                salePrice: p.salePrice,
                costPrice: p.costPrice,
                categoryId: p.categoryId,
                taxRate: p.taxRate,
                barcode: p.barcode ?? '',
              ),
          ],
          warehouses: [
            for (final w in warehouses)
              PicPosWarehouseOption(id: w.id, name: w.name),
          ],
          costCenters: [
            for (final c in costCenters)
              PicPosNamedOption(id: c.id, name: c.name),
          ],
          systemTaxRate: taxRate,
          onSave: _save,
        ),
      );
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'تعذّر فتح النموذج: $e', type: ToastType.error);
      }
    } finally {
      for (final s in keepAlive) {
        s.close();
      }
    }
  }

  Future<void> _save({
    required ImportPanelValue panel,
    required int? partyId,
    required int? warehouseId,
    required int? costCenterId,
    required DateTime date,
    required List<Map<String, dynamic>> items,
    required double discount,
    required double paid,
    required String paymentMethod,
    required String notes,
    required String supplierInvoiceNumber,
  }) async {
    // ⚠️ **ولا صفرَ يُخترَع لمخزنٍ أو مورّد.** النموذجُ يمنع الحفظَ بدونهما
    //    (`_blockingReason`)، وتمريرُ `0` هنا كان يُنتج خطأَ مفتاحٍ خارجيٍّ
    //    غامضاً لو تبدّل ذلك المنعُ يوماً — والرسالةُ تصل المستخدمَ بعد أن
    //    رأى نموذجاً مملوءاً.
    if (partyId == null || warehouseId == null) {
      throw StateError('اختر المورّد والمخزن قبل الحفظ');
    }
    final rate = panel.localPerForeign ?? 1.0;
    // 🔴 **التحويلُ هنا وحدَه.** راجع رأسَ الملفّ.
    final lines = convertFormItemsToLocal(
      items: items,
      localPerForeign: rate,
    );
    final auth = ref.read(authProvider);
    final repo = ref.read(purchasesRepositoryProvider);
    await repo.createInvoice(CreatePurchaseInvoiceParams(
      supplierId: partyId,
      warehouseId: warehouseId,
      items: [
        for (final l in lines)
          PurchaseItemParams(
            productId: l.productId,
            quantity: l.quantity,
            unitCost: l.unitCost,
            salePrice: 0,
            taxRate: l.taxRate,
            taxAmount: l.taxAmount,
            discount: l.discount,
            unitName: l.unitName,
          ),
      ],
      // وخصمُ الترويسة والمدفوعُ يُحوَّلان كذلك: كلاهما بعملة الإدخال.
      discount: foreignToLocal(foreign: discount, localPerForeign: rate),
      paid: foreignToLocal(foreign: paid, localPerForeign: rate),
      paymentMethod: paymentMethod,
      notes: notes.isEmpty ? null : notes,
      supplierInvoiceNumber:
          supplierInvoiceNumber.isEmpty ? null : supplierInvoiceNumber,
      date: date,
      costCenterId: costCenterId,
      userId: auth.user?.id,
      createdByUsername: auth.user?.username,
      currencyId: panel.currencyId,
      exchangeRate: panel.localPerForeign,
      importDetails: panel.doc,
    ));
    ref.invalidate(importPurchaseRowsProvider);
  }
}

typedef ImportInvoiceSave = Future<void> Function({
  required ImportPanelValue panel,
  required int? partyId,
  required int? warehouseId,
  required int? costCenterId,
  required DateTime date,
  required List<Map<String, dynamic>> items,
  required double discount,
  required double paid,
  required String paymentMethod,
  required String notes,
  required String supplierInvoiceNumber,
});

class _ImportInvoiceDialog extends StatefulWidget {
  const _ImportInvoiceDialog({
    required this.currencies,
    required this.agents,
    required this.suppliers,
    required this.products,
    required this.warehouses,
    required this.costCenters,
    required this.systemTaxRate,
    required this.onSave,
  });

  final List<ImportCurrencyOption> currencies;
  final List<ImportAgentOption> agents;
  final List<PicPosPartyOption> suppliers;
  final List<PicPosProductOption> products;
  final List<PicPosWarehouseOption> warehouses;
  final List<PicPosNamedOption> costCenters;
  final double systemTaxRate;
  final ImportInvoiceSave onSave;

  @override
  State<_ImportInvoiceDialog> createState() => _ImportInvoiceDialogState();
}

class _ImportInvoiceDialogState extends State<_ImportInvoiceDialog> {
  ImportPanelValue _panel = (
    currencyId: null,
    localPerForeign: null,
    doc: normalizeImportDocument(),
  );
  bool _busy = false;

  PicPosEntryCurrency? get _entryCurrency {
    final id = _panel.currencyId;
    final rate = _panel.localPerForeign;
    if (id == null || rate == null || rate <= 0) return null;
    for (final c in widget.currencies) {
      if (c.id == id) {
        return (
          id: c.id,
          code: c.code,
          symbol: c.symbol,
          localPerForeign: rate,
        );
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final block = validateExchangeRate(
          currencyId: _panel.currencyId,
          localPerForeign: _panel.localPerForeign,
        ) ??
        validateImportDocument(_panel.doc);

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: ImportDocumentPanel(
              currencies: widget.currencies,
              agents: widget.agents,
              enabled: !_busy,
              onChanged: (v) => setState(() => _panel = v),
            ),
          ),
          Expanded(
            child: PicPosInvoiceForm(
              kind: PicPosInvoiceKind.purchase,
              entryCurrency: _entryCurrency,
              parties: widget.suppliers,
              products: widget.products,
              warehouses: widget.warehouses,
              costCenters: widget.costCenters,
              systemTaxRate: widget.systemTaxRate,
              invoiceNumberPreview: kImportInvoiceNumberPlaceholder,
              initialWarehouseId: widget.warehouses.length == 1
                  ? widget.warehouses.first.id
                  : null,
              onCancel: () => Navigator.of(context).pop(),
              onSave: ({
                required partyId,
                required supplierInvoiceNumber,
                required date,
                required subtotal,
                required discount,
                required tax,
                required net,
                required paid,
                required notes,
                required items,
                required warehouseId,
                required costCenterId,
                required paymentMethod,
                required printAfterSave,
                required sourceOrderId,
              }) async {
                // 🔴 **وحارسُ اللوح يُفحَص هنا كذلك لا في اللوح وحدَه.**
                //    زرُّ الحفظ يعيش في النموذج ولا يرى اللوح، فسعرٌ فارغٌ
                //    كان يمرّ فيُقيَّد الدولارُ على أنّه محلّيّ.
                if (block != null) {
                  AppToast.show(context, block, type: ToastType.error);
                  return;
                }
                setState(() => _busy = true);
                try {
                  await widget.onSave(
                    panel: _panel,
                    partyId: partyId,
                    warehouseId: warehouseId,
                    costCenterId: costCenterId,
                    date: date,
                    items: items,
                    discount: discount,
                    paid: paid,
                    paymentMethod: paymentMethod,
                    notes: notes,
                    supplierInvoiceNumber: supplierInvoiceNumber,
                  );
                  if (!context.mounted) return;
                  AppToast.show(context, 'حُفظت فاتورةُ الاستيراد',
                      type: ToastType.success);
                  Navigator.of(context).pop();
                } catch (e) {
                  if (!context.mounted) return;
                  AppToast.show(context, 'فشل الحفظ: $e',
                      type: ToastType.error);
                } finally {
                  if (context.mounted) setState(() => _busy = false);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
