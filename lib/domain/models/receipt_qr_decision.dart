/// قرارُ رمز الاستجابة السريعة على الإيصال — دالّةٌ خالصةٌ لا تلمس قاعدةً ولا
/// ملفّاً، فتُختبَر بلا تجهيزة.
///
/// قرارُ المالك 2026-09-02: الرمزُ **ضريبيٌّ** على جهازٍ فُعِّلت عليه الفاتورةُ
/// الإلكترونيّة، و**غيرُ ضريبيٍّ** على غيره — بديلاً رقميّاً عن الورق لا يُعترف
/// به ضريبيّاً. والفاصلُ بينهما رايةُ التفعيل، لا وجودُ صفِّ التقديم: فعند
/// الطباعة الأولى لا صفَّ في الحالتين.
library;

/// صنفُ الرمز المطبوع.
enum ReceiptQrKind {
  /// لا رمزَ — الفاتورةُ الإلكترونيّةُ مُفعَّلةٌ ولم يصل اعتمادُ البوّابة بعد.
  none,

  /// رمزٌ ضريبيٌّ رسميٌّ، حمولتُه من البوّابة كما وصلت.
  fiscal,

  /// رمزٌ غيرُ ضريبيٍّ ببيانات البيعة — لا قيمةَ ضريبيّةَ له.
  nonFiscal,
}

/// بياناتُ البيعة التي يحملها الرمزُ غيرُ الضريبيّ.
class ReceiptSaleSummary {
  final String invoiceNumber;
  final String issuedAt;
  final String total;
  final String companyName;

  const ReceiptSaleSummary({
    required this.invoiceNumber,
    required this.issuedAt,
    required this.total,
    required this.companyName,
  });

  /// من بيانات البيعة الخامّ — الصياغةُ هنا في موضعٍ واحدٍ مُختبَر، لا في كلِّ
  /// منادٍ (‏`printing_service` لا يستورد `intl` أصلاً).
  ///
  /// التاريخُ بالدقيقة `yyyy-MM-dd HH:mm` والمبلغُ بمنزلتين.
  factory ReceiptSaleSummary.fromSale({
    required String invoiceNumber,
    required DateTime issuedAt,
    required double total,
    required String companyName,
  }) {
    String two(int n) => n.toString().padLeft(2, '0');
    final d = issuedAt;
    return ReceiptSaleSummary(
      invoiceNumber: invoiceNumber,
      issuedAt: '${d.year}-${two(d.month)}-${two(d.day)} '
          '${two(d.hour)}:${two(d.minute)}',
      total: total.toStringAsFixed(2),
      companyName: companyName,
    );
  }
}

/// وسمُ الرمز غير الضريبيّ — منطوقٌ صريحٌ يمنع تقديمَه على أنّه إيصالٌ ضريبيّ.
const kNonFiscalQrDisclaimer = 'ليس إيصالاً ضريبيّاً';

/// مفتاحُ رايةِ التفعيل في `Settings` — `'true'` أو `'false'`.
///
/// `EInvoiceConfigs.isEnabled` هي الحقيقة، لكنّ جدولَها خارجَ المزامنة لأنّه
/// يحمل السرَّ نصّاً (قرارُ مالك 2026-09-02). فهذه الرايةُ — بلا سرّ — هي ما
/// يصل الكاشير ويفصل بين الرمز الضريبيّ وغير الضريبيّ. تُكتب داخلَ
/// `saveEInvoiceConfig` فلا تنفكّ عن الإعداد، وتُقرأ **لا متزامنةً**
/// (`getSettingValue`) فلا تحتاج مفتاحاً في `preloadKeys`.
const kEInvoiceEnabledSettingKey = 'einvoice_enabled';

/// نتيجةُ القرار.
class ReceiptQr {
  final ReceiptQrKind kind;

  /// حمولةُ الرمز — فارغةٌ حين [ReceiptQrKind.none].
  final String payload;

  /// الوسمُ المطبوع تحت الرمز — فارغٌ لغير [ReceiptQrKind.nonFiscal].
  final String disclaimer;

  const ReceiptQr({
    required this.kind,
    required this.payload,
    required this.disclaimer,
  });
}

/// يقرّر ما يُطبع.
ReceiptQr resolveReceiptQr({
  required bool eInvoiceEnabled,
  required String? submissionStatus,
  required String? gatewayQrCode,
  required ReceiptSaleSummary sale,
}) {
  // جهازٌ مسجَّلٌ ضريبيّاً لا يطبع رمزاً غيرَ ضريبيٍّ أبداً — مهما كانت حالةُ
  // التقديم. فإمّا الرمزُ الرسميُّ وإمّا لا رمز.
  if (eInvoiceEnabled) {
    final accepted = submissionStatus == _acceptedStatus;
    final qr = gatewayQrCode ?? '';
    if (accepted && qr.isNotEmpty) {
      return ReceiptQr(
        kind: ReceiptQrKind.fiscal,
        payload: qr,
        disclaimer: '',
      );
    }
    return const ReceiptQr(
      kind: ReceiptQrKind.none,
      payload: '',
      disclaimer: '',
    );
  }

  return ReceiptQr(
    kind: ReceiptQrKind.nonFiscal,
    payload: _nonFiscalPayload(sale),
    disclaimer: kNonFiscalQrDisclaimer,
  );
}

/// الحالةُ الوحيدةُ التي يُعترف فيها بالمستند لدى البوّابة. وما عداها —
/// معلَّقاً كان أو مرفوضاً أو ملغى — لا يُطبع له رمزٌ ضريبيّ.
const _acceptedStatus = 'valid';

/// حمولةٌ نصّيّةٌ مقروءةٌ بأيّ ماسح — ولا تشبه صيغةَ TLV الضريبيّة إطلاقاً.
String _nonFiscalPayload(ReceiptSaleSummary sale) {
  return 'فاتورة: ${sale.invoiceNumber}\n'
      'التاريخ: ${sale.issuedAt}\n'
      'الإجمالي: ${sale.total}\n'
      'المنشأة: ${sale.companyName}';
}
