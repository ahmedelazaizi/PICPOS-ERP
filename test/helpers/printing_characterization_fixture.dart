// مدخلٌ ثابتٌ واحدٌ لكلّ القوالب — كي يكون الفرقُ في الراسم لا في البيانات.
//
// كلُّ قيمةٍ هنا مُختارةٌ لتُفعِّل فرعاً: خصمٌ غيرُ صفريّ، وضريبةٌ، ورسمُ
// توصيل، ومتبقٍّ موجب، وصنفٌ باسمٍ عربيٍّ طويلٍ يلتفّ، وآخرُ بلاتينيٍّ
// وأرقام، وثالثٌ بملاحظةٍ وإضافات. فما لا يظهر في البصمة لم يكن ليظهر.

import 'package:picpos_erp/domain/entities/shift_closing_snapshot.dart';
import 'package:picpos_erp/services/printing/printing_models.dart';
import 'package:picpos_erp/services/printing/template_pdf_renderer.dart';

/// تاريخٌ **ثابت** — لا `DateTime.now()`: البصمةُ تتغيّر كلَّ يومٍ فتفقد معناها.
final kFixtureDate = DateTime.utc(2026, 3, 14, 9, 26, 53);

const kFixtureItems = <Map<String, dynamic>>[
  {
    'name': 'جبنة رومي صبري قديمة درجة أولى',
    'code': 'P-001',
    'quantity': 2.0,
    'price': 125.5,
    'discount': 0.0,
    'tax': 0.0,
    'total': 251.0,
  },
  {
    'name': 'Olive Oil 1L Extra Virgin',
    'code': 'P-002',
    'quantity': 3.0,
    'price': 90.0,
    'discount': 5.0,
    'tax': 0.0,
    'total': 265.0,
    'note': 'بدون ثلج|زيادة صوص 5.00',
  },
  {
    'name': 'أرز مصري ٥ كجم',
    'code': 'P-003',
    'quantity': 1.0,
    'price': 84.0,
    'discount': 0.0,
    'tax': 11.76,
    'total': 95.76,
  },
];

const kFixtureSubtotal = 611.76;
const kFixtureDiscount = 5.0;
const kFixtureTax = 11.76;
const kFixtureDeliveryFee = 20.0;
const kFixtureTotal = 626.76;
const kFixturePaid = 500.0;

const kFixtureCompanyName = 'مؤسسة النور التجارية';
const kFixtureCompanyAddress = 'شارع الجمهورية — المنصورة';
const kFixtureCompanyPhone = '0100 123 4567';
const kFixtureCompanyTaxId = '310-123-456-789';

const kFixtureCustomerName = 'أحمد عبد الرحمن';
const kFixtureCustomerPhone = '0111 987 6543';
const kFixtureCustomerAddress = 'ميت غمر — الدقهلية';

const kFixtureInvoiceNumber = 'SINV-2026-0417';
const kFixtureCashier = 'سالم بدري';
const kFixtureNotes = 'يُسلَّم خلال ٤٨ ساعة';

/// لقطةُ وردية — القالبُ `shift_closing` وحدَه يقرؤها، وبدونها تخرج عناصرُ
/// `shift_*` فارغةً فلا تُقاس.
final kFixtureShift = ShiftClosingSnapshot(
  invoiceCount: 37,
  totalSales: 4820.5,
  systemCash: 3120.5,
  systemCard: 900.0,
  systemClick: 180.0,
  actualCash: 3100.0,
  actualCard: 900.0,
  actualClick: 180.0,
  cashVariance: -20.5,
  cardVariance: 0.0,
  clickVariance: 0.0,
  totalVariance: -20.5,
  totalExpenses: 90.0,
  cashRefunds: 40.0,
  cashIncome: 150.0,
  creditSales: 620.0,
  creditSalesCount: 4,
  openingBalance: 300.0,
  employeeName: 'سالم بدري',
  companyName: kFixtureCompanyName,
  closedAt: DateTime.utc(2026, 3, 14, 18),
);

/// نفسُ الأصناف كما يطلبها `TemplatePdfRenderer` — نموذجٌ مُصنَّفٌ لا خريطة.
/// مشتقٌّ من [kFixtureItems] كي لا ينفصل المدخلان فيفترق الراسمان بلا سبب.
final kFixtureRendererItems = [
  for (final m in kFixtureItems)
    InvoiceItem(
      name: m['name'] as String,
      quantity: m['quantity'] as double,
      price: m['price'] as double,
      total: m['total'] as double,
      barcode: m['code'] as String?,
      note: m['note'] as String?,
    ),
];

/// نفسُ المدخل كما يطلبه `TemplatePdfRenderer` — نموذجٌ مُصنَّفٌ لا خرائط.
final kFixtureRendererData = TemplateInvoiceData(
  invoiceNumber: kFixtureInvoiceNumber,
  date: kFixtureDate,
  items: kFixtureRendererItems,
  subtotal: kFixtureSubtotal,
  discount: kFixtureDiscount,
  tax: kFixtureTax,
  total: kFixtureTotal,
  paid: kFixturePaid,
  remaining: kFixtureTotal - kFixturePaid,
  deliveryFee: kFixtureDeliveryFee,
  companyName: kFixtureCompanyName,
  companyPhone: kFixtureCompanyPhone,
  companyAddress: kFixtureCompanyAddress,
  taxId: kFixtureCompanyTaxId,
  customerName: kFixtureCustomerName,
  customerPhone: kFixtureCustomerPhone,
  customerAddress: kFixtureCustomerAddress,
  employeeName: kFixtureCashier,
  salesType: 'delivery',
  notes: kFixtureNotes,
);
