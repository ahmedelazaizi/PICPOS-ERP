// العملاتُ المعتمدة في الإعداد الأول — **بالضبط ما يدعمه التطبيق فعلاً** (UX-001).
//
// ⚠️ `CurrencyInfo.all` في `core/constants/app_constants.dart` هو المصدر:
// JOD وEGP فقط. أيُّ رمزٍ آخر كان يتحوّل صامتاً إلى JOD. وهذا الملفُّ خالصٌ بلا
// Flutter، فالمطابقةُ مع `CurrencyInfo.all` يحرسها اختبارٌ لا استيراد.
// ولا اختيارَ مسبقاً للعملة (UX-004): القرارُ نهائيٌّ بعد أوّل فاتورة.
library;

const List<String> kFirstRunCurrencies = ['JOD', 'EGP'];

/// بلدُ الفوترة الإلكترونيّة.
enum FirstRunEInvoice { jordan, egypt, none }

/// افتراضاتُ الضريبة والفوترة المشتقّةُ من العملة.
class FirstRunCurrencyDefaults {
  const FirstRunCurrencyDefaults(this.vatRate, this.eInvoice, this.decimals);

  final double vatRate;
  final FirstRunEInvoice eInvoice;
  final int decimals;
}

/// JOD ⇒ ١٦٪ وJoFotara وثلاث خانات · EGP ⇒ ١٤٪ وETA وخانتان.
/// `null` لعملةٍ غير معتمدة.
FirstRunCurrencyDefaults? currencyDefaultsFor(String code) => switch (code) {
      'JOD' => const FirstRunCurrencyDefaults(16, FirstRunEInvoice.jordan, 3),
      'EGP' => const FirstRunCurrencyDefaults(14, FirstRunEInvoice.egypt, 2),
      _ => null,
    };

/// النسبُ المسموحة — نفسُ سلّم `TaxRatePolicy.defaultAllowedRates`.
const List<double> kFirstRunVatRates = [0, 1, 2, 4, 5, 10, 14, 15, 16];
