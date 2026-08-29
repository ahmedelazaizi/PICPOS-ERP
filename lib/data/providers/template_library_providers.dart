// مزوّداتُ مكتبة النماذج — الوصلُ بين المستودع والشاشة.
//
// الشاشةُ ممنوعةٌ من `data/database`، فكلُّ صفٍّ يصلها هنا يتحوّل إلى
// [TemplateCard] الخالصة.
//
// ── والمصغَّرةُ تُبنى بمحرّك الطباعة نفسِه ────────────────────────────────
// لا «رسمٌ تخطيطيٌّ» مكتوبٌ باليد كما في ملفّ التصميم: تلك صورةٌ ثانيةٌ
// للقالب تنحرف عن الورق ولا تشكو. المصغَّرةُ هنا تمرّ بنفس السلسلة —
// `buildDocument` ⇐ `paginate` ⇐ `planPage` — فتُصبح **عاجزةً بنيويّاً** عن
// أن تفترق عمّا يُطبع.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/picpos_template_card.dart';
import '../../domain/printing/print_values.dart';
import '../../services/printing/layout_engine.dart';
import '../../services/printing/paint_plan.dart';
import '../../services/printing/template_render_pipeline.dart';
import '../../services/templated_invoice_service.dart';
import '../database/database.dart';
import 'repository_providers.dart';

// ⚠️ `Notifier` لا `StateProvider`: الأخيرةُ ليست ضمن Riverpod 3 المستعملةِ
// هنا، وهذا هو نمطُ الحالة البسيطة في المستودع كلِّه.

/// المرشّحُ المختار.
class TemplateFilterNotifier extends Notifier<TemplateFilter> {
  @override
  TemplateFilter build() => TemplateFilter.all;
  void set(TemplateFilter f) => state = f;
}

final templateFilterProvider =
    NotifierProvider<TemplateFilterNotifier, TemplateFilter>(
        TemplateFilterNotifier.new);

/// نصُّ البحث.
class TemplateQueryNotifier extends Notifier<String> {
  @override
  String build() => '';
  void set(String q) => state = q;
}

final templateQueryProvider =
    NotifierProvider<TemplateQueryNotifier, String>(
        TemplateQueryNotifier.new);

/// القالبُ المحدَّد — `null` قبل أوّل اختيار.
class SelectedTemplateNotifier extends Notifier<int?> {
  @override
  int? build() => null;
  void set(int? id) => state = id;
}

final selectedTemplateIdProvider =
    NotifierProvider<SelectedTemplateNotifier, int?>(
        SelectedTemplateNotifier.new);

/// عدّادٌ يُزاد بعد كلِّ كتابةٍ فتُعاد القراءة.
///
/// وهذا هو «إبطالُ الذاكرة بعد الحفظ» في عقد الأزرار: بدونه يعدّل
/// المستخدمُ ويرى القديم، فيظنّ أنّ الحفظَ لم يعمل — وهو أسوأُ عطبٍ ممكن.
class TemplateLibraryRefreshNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state = state + 1;
}

final templateLibraryRefreshProvider =
    NotifierProvider<TemplateLibraryRefreshNotifier, int>(
        TemplateLibraryRefreshNotifier.new);

/// بطاقاتُ المكتبة كلُّها.
final templateCardsProvider =
    FutureProvider.autoDispose<List<TemplateCard>>((ref) async {
  ref.watch(templateLibraryRefreshProvider);
  final repo = ref.watch(invoiceTemplatesRepositoryProvider);

  final templates = await repo.getAllTemplates();
  final bindings = await repo.getAllBindings();

  final cards = <TemplateCard>[];
  for (final t in templates) {
    // الملصقاتُ مسارُ رسمٍ آخرُ بالكامل — ليست من هذه المكتبة.
    if (t.templateCategory == 'barcode') continue;

    final elements = await repo.getTemplateElements(t.id);
    final settings = await repo.getTableSettings(t.id);

    final own = bindings.where((b) => b.templateId == t.id);
    cards.add(
      TemplateCard(
        id: t.id,
        name: t.name,
        type: t.type,
        category: t.templateCategory,
        paperWidthMm: t.paperWidth,
        paperHeightMm: t.paperHeight,
        paperLabel: paperLabelFor(t.paperWidth, t.paperHeight),
        elementCount: elements.length,
        columnCount: _columnCount(settings),
        layoutVersion: t.layoutVersion,
        isDefault: t.isDefault,
        bindings: [
          for (final b in own)
            TemplateBindingView(
              documentLabel: documentTypeLabel(b.documentType),
              documentType: b.documentType,
              scope: _scopeLabel(b),
            ),
        ],
        thumbnail: buildTemplateThumbnail(t, elements, settings),
      ),
    );
  }
  return cards;
});

/// البطاقاتُ بعد الترشيح والبحث.
final visibleTemplateCardsProvider =
    Provider.autoDispose<List<TemplateCard>>((ref) {
  final all = ref.watch(templateCardsProvider).value ?? const <TemplateCard>[];
  return filterTemplateCards(
    all,
    filter: ref.watch(templateFilterProvider),
    query: ref.watch(templateQueryProvider),
  );
});

/// البطاقةُ المحدَّدة — أو الأولى حين لا اختيار.
final selectedTemplateCardProvider =
    Provider.autoDispose<TemplateCard?>((ref) {
  final visible = ref.watch(visibleTemplateCardsProvider);
  if (visible.isEmpty) return null;
  final id = ref.watch(selectedTemplateIdProvider);
  if (id == null) return visible.first;
  for (final c in visible) {
    if (c.id == id) return c;
  }
  // اختيارٌ خرج من المرشَّح — لا تُفرَّغ اللوحةُ بل تعود لأوّل مرئيّ.
  return visible.first;
});

// ═══════════════════════════════════════════════════════════════════════════

/// مصغَّرةُ القالب من محرّك الطباعة نفسِه.
///
/// ببياناتٍ **رمزيّةٍ قصيرة**: المصغَّرةُ تُقرأ بالشكل لا بالقيمة، وثلاثةُ
/// صفوفٍ تكفي لإظهار الجدول. وبيانٌ حقيقيٌّ هنا يعني قراءةَ فاتورةٍ لكلِّ
/// بطاقةٍ في كلِّ إعادةِ بناء.
TemplateThumbnail buildTemplateThumbnail(
  InvoiceTemplate template,
  List<InvoiceTemplateElement> elements,
  InvoiceTableSetting? settings,
) {
  try {
    final doc = TemplateRenderPipeline.buildDocument(
      template: template,
      // ⚠️ **مرتَّبةً كما يرتّبها الطبعُ لا كما تخرج من القاعدة**: الـDAO
      //    يفرز بـ`sortOrder` وحدَه، و`orderElementsForPrint` تُسقط المخفيَّ
      //    وتنقّي تكرارَ المتغيّرات فوقَ ذلك. فبدونها تعرض المصغَّرةُ عنصراً
      //    لا يُطبع — وهو عينُ «المصغَّرةُ تفترق عن الورق» الذي بُنيت لمنعه.
      orderedElements:
          TemplatedInvoiceService.orderElementsForPrint(elements),
      tableSettings: settings,
    );
    final pages = LayoutEngine.paginate(
      document: doc,
      rows: TemplateRenderPipeline.buildRows(_sampleItems, doc.table, 2),
      values: TemplateRenderPipeline.buildValues(doc, _samplePayload),
    );
    if (pages.isEmpty) return TemplateThumbnail.empty;
    final page = pages.first;
    return TemplateThumbnail(
      widthMm: page.widthMm,
      heightMm: page.heightMm,
      ops: planPage(page),
    );
  } catch (_) {
    // مصغَّرةٌ فاشلةٌ تُظهر بطاقةً بلا صورة — ولا تُسقط المكتبةَ كلَّها.
    return TemplateThumbnail.empty;
  }
}

const _sampleItems = <Map<String, dynamic>>[
  {'name': 'صنف تجريبي', 'code': 'P-1', 'quantity': 2.0, 'price': 50.0,
   'discount': 0.0, 'tax': 0.0, 'total': 100.0},
  {'name': 'صنف آخر', 'code': 'P-2', 'quantity': 1.0, 'price': 75.0,
   'discount': 0.0, 'tax': 0.0, 'total': 75.0},
  {'name': 'صنف ثالث', 'code': 'P-3', 'quantity': 3.0, 'price': 25.0,
   'discount': 0.0, 'tax': 0.0, 'total': 75.0},
];

final _samplePayload = PrintPayload(
  invoiceNumber: 'INV-0001',
  date: DateTime.utc(2026, 1, 1),
  companyName: 'اسم الشركة',
  companyAddress: 'العنوان',
  companyPhone: '0100 000 0000',
  companyTaxId: '000-000-000',
  customerName: 'اسم العميل',
  customerPhone: '0111 111 1111',
  customerAddress: 'عنوان العميل',
  cashierName: 'الكاشير',
  subtotal: 250,
  discount: 0,
  tax: 0,
  deliveryFee: 0,
  total: 250,
  paid: 250,
  remaining: 0,
);

int _columnCount(InvoiceTableSetting? s) {
  if (s == null) return 0;
  var n = 0;
  if (s.showIndex) n++;
  if (s.showProductName) n++;
  if (s.showProductCode) n++;
  if (s.showQuantity) n++;
  if (s.showUnitPrice) n++;
  if (s.showDiscount) n++;
  if (s.showTax) n++;
  if (s.showTotal) n++;
  return n;
}

String _scopeLabel(TemplateBinding b) {
  final parts = <String>[
    b.branchId == null ? 'كل الفروع' : 'فرع ${b.branchId}',
    if (b.printerId != null) 'طابعة ${b.printerId}',
    b.locale == null ? 'كل اللغات' : (b.locale == 'ar' ? 'عربي' : b.locale!),
  ];
  return parts.join(' · ');
}

/// تسميةُ نوع المستند بالعربيّة.
///
/// وما لا يُعرف يُعاد كما هو لا يُبتلع: نوعٌ جديدٌ يظهر فيُرى بدل أن يختفي.
String documentTypeLabel(String type) => const {
      'sales_invoice': 'فاتورة مبيعات',
      'sales_return': 'مرتجع مبيعات',
      'purchase_invoice': 'فاتورة مشتريات',
      'purchase_return': 'مرتجع مشتريات',
      'sales_receipt': 'إيصال بيع',
      'quotation': 'عرض سعر',
      'kitchen_order': 'طلب مطبخ',
      'shift_closing': 'إقفال وردية',
      'party_statement': 'كشف حساب',
      'report': 'تقرير',
    }[type] ??
    type;
