// ═══════════════════════════════════════════════════════════════════════════
// سياسةُ المرفقات — حسابٌ خالصٌ بلا قاعدةٍ ولا واجهة (§٨ / ح‑٤)
// ═══════════════════════════════════════════════════════════════════════════
//
// 🔴 **ولماذا هنا لا في الودجت ولا في الـDAO؟**
//
// لأنّ للسقف والأنواعِ **ثلاثةَ حرّاسٍ لا واحداً**: الواجهةُ تمنع الاختيار،
// والمستودعُ يمنع الكتابةَ المحلّيّة، والخادمُ يمنع ما يصله عبر السلك. ولو
// عاش الحسابُ في الودجت لصار للخادم قانونٌ آخر — **وعميلٌ مُعدَّلٌ يتجاوز
// الودجتَ فيكتب ما يشاء**.
//
// فالنصُّ واحدٌ هنا، والثلاثةُ يقرؤونه.

import '../../core/i18n/tr.dart';
import '../../core/permissions/permission_codes.dart';

/// سقفُ حجم الملفّ الواحد — **٥ ميغا** (قرارُ المالك §٨٫٤).
///
/// ⚠️ والخدمةُ الميّتةُ التي حلّت هذه الخطّةُ محلَّها كانت تقول ٢٥ ميغا —
/// رقمٌ بلا مُنادٍ. و٢٥ ميغا × مستنداتِ سنةٍ تُنتج قاعدةً تُنسَخ
/// احتياطيّاً كلَّ ليلة، والنسخةُ **ملفُّ القاعدة كلُّه** لا فرقٌ.
const int kAttachmentMaxBytes = 5 * 1024 * 1024;

/// وسقفُ العدد للمستند الواحد — **عشرةُ ملفّات**.
const int kAttachmentMaxPerDocument = 10;

/// الأنواعُ المسموحة — **صورةٌ وPDF فقط** (قرارُ المالك §٨٫٤).
///
/// ⚠️ **وليست قائمةَ راحة**: ملفٌّ تنفيذيٌّ مرفقٌ في قاعدةٍ تُوزَّع على
/// كلّ جهازٍ في المنشأة **سطحُ هجومٍ لا ميزة** — يصل الأجهزةَ كلَّها
/// بالمزامنة بلا أن يمرّ بمضادّ فيروساتٍ ولا بقرار.
const Set<String> kAttachmentAllowedMimeTypes = {
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/gif',
  'image/bmp',
  'application/pdf',
};

/// والامتدادُ يُحوَّل إلى نوعٍ — الاسمُ وحدَه ما يعطيه `file_picker` أحياناً.
const Map<String, String> kAttachmentMimeByExtension = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'gif': 'image/gif',
  'bmp': 'image/bmp',
  'pdf': 'application/pdf',
};

/// الامتداداتُ التي تُعرَض في مُنتقي الملفّات.
List<String> get kAttachmentAllowedExtensions =>
    kAttachmentMimeByExtension.keys.toList(growable: false);

/// تصنيفُ الورقة — نُقل من `document_attachment_service.dart` قبل حذفها:
/// المفرداتُ صالحةٌ وإن كان تصميمُها مرفوضاً.
enum AttachmentDocType {
  scannedInvoice,
  receipt,
  contract,
  deliveryNote,
  bankStatement,
  taxDocument,
  customsDeclaration,
  billOfLading,
  warranty,
  other;

  /// الرمزُ المخزَّن في العمود — **ثابتٌ لا يُشتقُّ من `name`**: إعادةُ
  /// تسميةِ عضوٍ في enum لا يجوز أن تُبطل صفوفاً مخزَّنة.
  String get code => switch (this) {
        AttachmentDocType.scannedInvoice => 'scanned_invoice',
        AttachmentDocType.receipt => 'receipt',
        AttachmentDocType.contract => 'contract',
        AttachmentDocType.deliveryNote => 'delivery_note',
        AttachmentDocType.bankStatement => 'bank_statement',
        AttachmentDocType.taxDocument => 'tax_document',
        AttachmentDocType.customsDeclaration => 'customs_declaration',
        AttachmentDocType.billOfLading => 'bill_of_lading',
        AttachmentDocType.warranty => 'warranty',
        AttachmentDocType.other => 'other',
      };

  String get labelAr => switch (this) {
        AttachmentDocType.scannedInvoice => 'فاتورة ممسوحة',
        AttachmentDocType.receipt => 'إيصال',
        AttachmentDocType.contract => 'عقد',
        AttachmentDocType.deliveryNote => 'إذن تسليم',
        AttachmentDocType.bankStatement => 'كشف حساب بنكي',
        AttachmentDocType.taxDocument => 'مستند ضريبي',
        AttachmentDocType.customsDeclaration => 'بيان جمركي',
        AttachmentDocType.billOfLading => 'بوليصة شحن',
        AttachmentDocType.warranty => 'شهادة ضمان',
        AttachmentDocType.other => 'أخرى',
      };

  String get displayLabel => tr(labelAr);

  static AttachmentDocType fromCode(String? code) {
    for (final t in AttachmentDocType.values) {
      if (t.code == code) return t;
    }
    return AttachmentDocType.other;
  }
}

/// المستنداتُ التي تقبل مرفقاً — **تسعةٌ بقرار المالك (§٨٫٤ قرار ٢)**.
///
/// ⚠️ **ولكلٍّ صلاحيتُه لا صلاحيةٌ واحدةٌ للمرفقات كلِّها.** من يملك تعديلَ
/// فاتورة مشترياتٍ يملك إرفاقَ ورقةٍ بها — وصلاحيةٌ واحدةٌ عامّةٌ
/// (`attachments_manage`) كانت تعني أنّ أمينَ المخزن يرفع أوراقاً على
/// قيود اليوميّة.
class AttachmentEntity {
  const AttachmentEntity({
    required this.type,
    required this.labelAr,
    required this.tableName,
    required this.viewPermission,
    required this.attachPermission,
  });

  /// الرمزُ المخزَّن في `attachments.entity_type`.
  final String type;
  final String labelAr;

  String get displayLabel => tr(labelAr);

  /// جدولُ المستند في SQL — **به يُحوِّل الخادمُ الهُويّةَ العالميّةَ
  /// إلى رقمِه المحلّيّ**.
  ///
  /// ⚠️ ومصدرُه واحدٌ هنا لا خريطةٌ ثانيةٌ في الخادم: خريطتان
  ///    تفترقان بعد شهرٍ فيُرفِق العميلُ بمستندٍ ويكتبُ الخادمُ على غيرِه.
  final String tableName;

  /// من يقرأ المستندَ يقرأ أوراقَه.
  final String viewPermission;

  /// ومن يكتبه يُرفق به ويحذف.
  final String attachPermission;
}

const List<AttachmentEntity> kAttachmentEntities = [
  AttachmentEntity(
    type: 'purchase_invoice',
    labelAr: 'فاتورة مشتريات',
    tableName: 'purchase_invoices',
    viewPermission: PermissionCodes.purchasesView,
    attachPermission: PermissionCodes.purchasesEdit,
  ),
  AttachmentEntity(
    type: 'import_purchase',
    labelAr: 'مشتريات خارجيّة',
    tableName: 'import_purchase_details',
    viewPermission: PermissionCodes.purchasesView,
    attachPermission: PermissionCodes.purchasesCreate,
  ),
  AttachmentEntity(
    type: 'purchase_return',
    labelAr: 'مردود مشتريات',
    tableName: 'purchase_returns',
    viewPermission: PermissionCodes.purchasesReturnView,
    attachPermission: PermissionCodes.purchasesReturnEdit,
  ),
  AttachmentEntity(
    type: 'sales_invoice',
    labelAr: 'فاتورة مبيعات',
    tableName: 'sales_invoices',
    viewPermission: PermissionCodes.salesView,
    attachPermission: PermissionCodes.salesEdit,
  ),
  AttachmentEntity(
    type: 'journal_entry',
    labelAr: 'قيد يوميّة',
    tableName: 'journal_entries',
    viewPermission: PermissionCodes.accountingView,
    attachPermission: PermissionCodes.accountingJournal,
  ),
  AttachmentEntity(
    type: 'receipt_voucher',
    labelAr: 'سند قبض',
    tableName: 'safe_transactions',
    viewPermission: PermissionCodes.treasuryView,
    attachPermission: PermissionCodes.treasuryReceiptsCreate,
  ),
  AttachmentEntity(
    type: 'payment_voucher',
    labelAr: 'سند صرف',
    tableName: 'safe_transactions',
    viewPermission: PermissionCodes.treasuryView,
    attachPermission: PermissionCodes.treasuryPaymentsCreate,
  ),
  AttachmentEntity(
    type: 'fixed_asset',
    labelAr: 'بطاقة أصل',
    tableName: 'fixed_assets',
    viewPermission: PermissionCodes.assetsView,
    attachPermission: PermissionCodes.assetsManage,
  ),
  AttachmentEntity(
    type: 'asset_disposal',
    labelAr: 'طلب استبعاد أصل',
    tableName: 'asset_disposals',
    viewPermission: PermissionCodes.assetsView,
    attachPermission: PermissionCodes.assetsManage,
  ),
];

Map<String, AttachmentEntity> get kAttachmentEntityByType =>
    {for (final e in kAttachmentEntities) e.type: e};

AttachmentEntity? attachmentEntityFor(String? entityType) =>
    entityType == null ? null : kAttachmentEntityByType[entityType];

/// نوعُ المحتوى من اسم الملفّ — `null` لامتدادٍ غيرِ معروف.
String? attachmentMimeForFileName(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) return null;
  return kAttachmentMimeByExtension[fileName.substring(dot + 1).toLowerCase()];
}

bool isAttachmentImage(String mimeType) => mimeType.startsWith('image/');

bool isAttachmentPdf(String mimeType) => mimeType == 'application/pdf';

/// عرضُ الحجم بالعربيّة — **أرقامٌ لاتينيّةٌ عمداً** كسائر الأرقام في
/// الشاشات، والوحدةُ عربيّة.
String formatAttachmentSize(int bytes) {
  if (bytes < 0) return '—';
  if (bytes < 1024) return tr('{p0} بايت', {'p0': bytes});
  if (bytes < 1024 * 1024) {
    return tr('{p0} ك.ب', {'p0': (bytes / 1024).toStringAsFixed(1)});
  }
  return tr('{p0} م.ب', {'p0': (bytes / (1024 * 1024)).toStringAsFixed(1)});
}

/// 🔴 **الحارسُ الواحدُ الذي يقرؤه الثلاثة.**
///
/// يعيد رسالةَ خطأٍ عربيّةً أو `null` إن كان المرفقُ مقبولاً.
///
/// ⚠️ و[existingCount] هو عددُ المرفقات **الحيّة** (غيرِ المحذوفة) على
/// المستند: الحذفُ ناعمٌ، فعدُّ المحذوفاتِ كان يُقفل المستندَ بعد عشرِ
/// عمليّاتِ رفعٍ وحذفٍ وإن لم تبقَ ورقةٌ واحدة.
String? validateAttachment({
  required String entityType,
  required String fileName,
  required String mimeType,
  required int byteSize,
  required int existingCount,
}) {
  if (attachmentEntityFor(entityType) == null) {
    return tr('نوعُ المستند غيرُ مدعومٍ للمرفقات: {p0}', {'p0': entityType});
  }
  if (fileName.trim().isEmpty) return tr('اسمُ الملفّ مفقود');
  if (fileName.length > 255) return tr('اسمُ الملفّ أطولُ من ٢٥٥ محرفاً');
  if (!kAttachmentAllowedMimeTypes.contains(mimeType)) {
    return tr('نوعٌ غيرُ مسموحٍ — الصورُ وملفّاتُ PDF فقط');
  }
  if (byteSize <= 0) return tr('الملفُّ فارغ');
  if (byteSize > kAttachmentMaxBytes) {
    return tr('الملفُّ أكبرُ من {p0}', {'p0': formatAttachmentSize(kAttachmentMaxBytes)});
  }
  if (existingCount >= kAttachmentMaxPerDocument) {
    return tr('بلغ المستندُ سقفَ {p0} مرفقاتٍ', {'p0': kAttachmentMaxPerDocument});
  }
  return null;
}

/// تحقّقُ البصمة — تُنادى **عند كلّ استقبالِ بايتاتٍ من السلك**.
///
/// ⚠️ **وليست تجميلاً**: بايتاتٌ وصلت ناقصةً تُعرَض صورةً مكسورةً بلا رسالة،
/// والمستخدمُ يظنُّ أنّ الورقةَ ضاعت من المنشأة لا من النقل.
String? validateAttachmentBytes({
  required int expectedSize,
  required String expectedSha,
  required int actualSize,
  required String actualSha,
}) {
  if (actualSize != expectedSize) {
    return tr('حجمُ المرفق لا يطابق الوصف ({p0} ≠ {p1})', {'p0': actualSize, 'p1': expectedSize});
  }
  if (actualSha.toLowerCase() != expectedSha.toLowerCase()) {
    return tr('بصمةُ المرفق لا تطابق الوصف — وصل ناقصاً أو تبدّل');
  }
  return null;
}
