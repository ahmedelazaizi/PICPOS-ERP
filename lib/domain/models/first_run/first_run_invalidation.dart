// قواعدُ الإبطال وتبديل المسار (النموذج §0.5) كدوالَّ خالصة.
//
// • تغييرُ المسار يصفّر التحقّقاتِ ويعيد إلى الخطوة الأولى (‏الأسرارُ في
//   [FirstRunSecrets] وتُصفَّر في المتحكّم).
// • تعديلُ مُدخَلِ تحقّقٍ يُبطل نتيجتَه فقط.
library;

import 'first_run_currency.dart';
import 'first_run_draft.dart';
import 'first_run_path.dart';

/// حقولٌ يُبطل تعديلُها نتائجَ تحقّق.
enum FirstRunField {
  endpoint,
  port,
  deviceName,
  pairingCode,
  branchRole,
  adminPassword,
  branchUser,

  /// أيُّ حقلٍ من حقول PostgreSQL (المضيف · المنفذ · القاعدة · المستخدم · الكلمة).
  postgres,

  /// الفرعُ المختار من الفروع المزامَنة.
  branchSelection,
}

/// مسارٌ جديدٌ: يصفّر التحقّقاتِ والتقدّمَ ويعود إلى الخطوة ١.
/// المسارُ نفسُه ⇒ المسودّةُ كما هي.
FirstRunDraft selectPath(FirstRunDraft d, FirstRunPath path) {
  if (d.path == path) return d;
  return d.copyWith(
    path: path,
    step: 0,
    maxStep: 0,
    checks: const FirstRunChecks(),
  );
}

/// يبطل ما يعتمد على [field] (‏ويُبقي الباقي).
FirstRunDraft invalidate(FirstRunDraft d, FirstRunField field) {
  final c = d.checks;
  switch (field) {
    case FirstRunField.endpoint:
    case FirstRunField.port:
    case FirstRunField.deviceName:
    case FirstRunField.pairingCode:
      return d.copyWith(
        checks: c.copyWith(
          linked: false,
          firstSyncDone: false,
          accountVerified: false,
        ),
      );
    case FirstRunField.branchRole:
      return d.copyWith(
        checks: c.copyWith(storageChecked: false, firstSyncDone: false),
      );
    case FirstRunField.branchUser:
    case FirstRunField.branchSelection:
      return d.copyWith(checks: c.copyWith(accountVerified: false));
    case FirstRunField.postgres:
      return d.copyWith(checks: c.copyWith(provisioned: false));
    case FirstRunField.adminPassword:
      return d; // كلمةُ المرور تُفحص مباشرةً من الأسرار، لا علمَ مخزَّن.
  }
}

/// اختيارُ عملة: تضبط الضريبةَ وبلدَ الفوترة ما لم يغيّرهما المستخدمُ بيده
/// (‏JOD ⇒ ١٦٪/JoFotara، EGP ⇒ ١٤٪/ETA). رمزٌ غيرُ معتمد ⇒ المسودّةُ كما هي —
/// لا تحويلَ صامتاً إلى JOD (UX-001).
FirstRunDraft selectCurrency(FirstRunDraft d, String code) {
  final defaults = currencyDefaultsFor(code);
  if (defaults == null) return d;
  return d.copyWith(
    currency: code,
    vatRate: d.vatRateTouched ? d.vatRate : defaults.vatRate,
    eInvoice: d.eInvoiceTouched ? d.eInvoice : defaults.eInvoice,
  );
}
