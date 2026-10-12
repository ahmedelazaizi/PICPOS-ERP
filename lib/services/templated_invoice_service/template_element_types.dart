// TemplatedInvoiceService - template element-type sets used by the renderer and its guards.
part of '../templated_invoice_service.dart';

/// أنواعُ **الحاويات** — لا تحمل معنًى بذاتها، بل يُحسم محتواها في
/// `_resolveType` من حقل `content`.
///
/// تمرُّ دائماً إلى الراسم لأنّ محتواها قد يكون نصّاً حرّاً (عنوانٌ ثابتٌ
/// كتبه المستخدم) لا نوعاً معروفاً — ولو رُشِّحت بمعرفة الراسم لسقط كلُّ نصٍّ
/// ثابتٍ في كلِّ قالب.
const kTemplateContainerElementTypes = <String>{
  'variable',
  'text',
  'line',
  'image',
  'rectangle',
};

/// كلُّ نوعٍ **يعرف الراسمُ كيف يرسمه** — مستخرَجٌ من مُصيِّر
/// `TemplatedInvoiceService._buildElementContent`.
///
/// ⚠️ **مصدرٌ واحدٌ لا نسخةٌ ثانية.** كانت هنا قائمةٌ يدويّةٌ بخمسةِ أنواعٍ
/// داخلَ `layoutSequenceForPrint` تُسقط سبعةً وثلاثين نوعاً يفهمها الراسمُ —
/// فخمسةُ قوالبَ مشحونةٍ كانت تُطبع جدولَ أصنافٍ عارياً (§٦‑١).
///
/// ويحرس تطابقَها مع المُصيِّر `printing_element_types_lockstep_test`: أيُّ
/// `case` يُضاف أو يُحذف هناك ولا يقابله تغييرٌ هنا يُسقط الاختبار — فلا
/// تعود الفجوةُ صامتةً.
const kRenderableElementTypes = <String>{
  'adhoc_customer_name',
  'adhoc_customer_phone',
  'barcode',
  'cashier_name',
  'company_address',
  'company_cr_number',
  'company_name',
  'company_name_en',
  'company_phone',
  'company_tax_id',
  'custom_text',
  'customer',
  'customer_address',
  'customer_phone',
  'date',
  'delivery_fee',
  'discount',
  'divider',
  'footer',
  'invoice_number',
  'invoice_title',
  'invoice_type_label',
  'item_additions',
  'item_options',
  'items_table',
  'logo',
  'notes',
  'order_number',
  'paid',
  'payment_method',
  'qr_code',
  'remaining',
  'sale_type',
  'spacer',
  'subtotal',
  'supplier_name',
  'table_number',
  'tax',
  'text',
  'time',
  'total',
};

/// الأنواعُ التي **تتكرّر عمداً** على الورقة: فاصلٌ وفراغٌ ونصٌّ ثابت.
///
/// ما عداها حقلُ بياناتٍ يُحلّ من الحمولة، فلا يُطبع مرّتين ولو كتبه القالبُ
/// بالصيغتَين معاً (‏`total` القديمة و`variable/total_amount` الجديدة).
const kRepeatableElementTypes = <String>{
  'divider',
  'spacer',
  'text',
  'custom_text',
};
