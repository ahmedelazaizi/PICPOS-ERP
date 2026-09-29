import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// تعريفاتُ أغراض الربط المحاسبيّ — ستُّ مجموعاتٍ تغطّي أغراضَ النظام.
///
/// مستخرَجةٌ من `account_mapping_settings_screen.dart` كما هي حرفاً بحرف:
/// الرمزُ (`purpose`) هو المفتاحُ الذي تقرأ به محرّكاتُ الترحيل، فتبديلُ
/// حرفٍ فيه يقطع الربطَ صامتاً. والتسمياتُ والأكوادُ الافتراضيّةُ تُعرض
/// للمستخدم ولا تُشتقّ من القاعدة.
///
/// ⚠️ نسخةٌ لا مرجع: الأصلُ يحتفظ بتعريفاته لأنّ UralCash تشغّل نفسَ
/// الشاشة، ونسخُ الودجت المشتركة إلى `*_picpos/` هو عرفُ هذا المستودع.
class AccountMappingPurposeGroup {
  final String title;
  final IconData icon;
  final Color color;
  final List<AccountMappingPurpose> items;

  const AccountMappingPurposeGroup({
    required this.title,
    required this.icon,
    required this.color,
    required this.items,
  });
}

class AccountMappingPurpose {
  final String purpose;
  final String label;
  final String defaultCode;
  final String description;

  const AccountMappingPurpose(
    this.purpose,
    this.label,
    this.defaultCode,
    this.description,
  );
}

/// المجموعاتُ الستُّ بأغراضها — منقولةٌ حرفاً بحرف عن الأصل.
///
/// ⚠️ **خمسةٌ وأربعون غرضاً لا سبعةٌ وأربعون.** تعليقُ الأصل يقول ٤٧،
/// والعدُّ الفعليُّ ‎8+9+8+11+3+6 = 45. نُقل العددُ مقيساً لا منسوخاً.
List<AccountMappingPurposeGroup> get accountMappingPurposeGroups => <AccountMappingPurposeGroup>[
  // ── المجموعة 1: النقدية والذمم ──────────────────────────────────────────
  AccountMappingPurposeGroup(
    title: tr('النقدية والذمم المدينة'),
    icon: PhosphorIconsBold.bank,
    color: const Color(0xFF2563EB),
    items: [
      AccountMappingPurpose('cash',                tr('الصندوق الرئيسي'),              '1111', tr('حساب النقد الافتراضي للمبيعات والمصروفات النقدية')),
      AccountMappingPurpose('petty_cash',          tr('صندوق العهدة'),                 '1112', tr('صندوق النقد الصغير والعهد')),
      AccountMappingPurpose('bank',                tr('البنك الرئيسي'),                '1113', tr('حساب البنك للمدفوعات بالبطاقات والتحويلات')),
      AccountMappingPurpose('bank2',               tr('البنك الثاني'),                 '1114', tr('حساب البنك الاحتياطي الثاني')),
      AccountMappingPurpose('click',               tr('حساب Click / إلكتروني'),        '1116', tr('حساب المدفوعات الإلكترونية (Click/KNET)')),
      AccountMappingPurpose('receivables',         tr('ذمم العملاء المحليون'),         '1121', tr('حساب الذمم المدينة للعملاء المحليين')),
      AccountMappingPurpose('foreign_receivables', tr('ذمم العملاء الخارجيون'),        '1122', tr('حساب الذمم المدينة للعملاء الخارجيين')),
      AccountMappingPurpose('notes_receivable',    tr('أوراق القبض'),                  '1123', tr('حساب الشيكات وأوراق القبض من العملاء')),
    ],
  ),
  // ── المجموعة 2: المخزون والأصول المتداولة ───────────────────────────────
  AccountMappingPurposeGroup(
    title: tr('المخزون والأصول المتداولة'),
    icon: PhosphorIconsBold.package,
    color: const Color(0xFF7C3AED),
    items: [
      AccountMappingPurpose('inventory',           tr('مخزون البضاعة للبيع'),          '1136', tr('الحساب الرئيسي لمخزون بضاعة التجارة')),
      AccountMappingPurpose('raw_materials',       tr('مخزون المواد الخام'),           '1131', tr('مخزون المواد الخام للإنتاج')),
      AccountMappingPurpose('wip',                 tr('مخزون تحت التشغيل'),            '1133', tr('منتجات تحت الإنتاج (WIP)')),
      AccountMappingPurpose('applied_overhead',    tr('تحميل صناعي مطبّق'),            '5138', tr('الطرف الدائن لتحميل التكاليف غير المباشرة على أوامر التصنيع')),
      AccountMappingPurpose('goods_in_transit',    tr('بضاعة تامة / عبور'),            '1134', tr('المنتجات النهائية والبضاعة في الطريق')),
      AccountMappingPurpose('input_vat',           tr('ضريبة القيمة المضافة مدفوعة'), '1141', tr('ضريبة القيمة المضافة على المشتريات')),
      AccountMappingPurpose('prepaid_expenses',    tr('مصروفات مقدمة'),                '1143', tr('المصروفات المدفوعة مسبقاً')),
      AccountMappingPurpose('employee_advances',   tr('سلف الموظفين'),                 '1146', tr('السلف المدفوعة للموظفين')),
      AccountMappingPurpose('fixed_assets',        tr('الأصول الثابتة'),               '1211', tr('حساب الأصول الثابتة والمعدات')),
    ],
  ),
  // ── المجموعة 3: الخصوم والالتزامات ──────────────────────────────────────
  AccountMappingPurposeGroup(
    title: tr('الخصوم والالتزامات'),
    icon: PhosphorIconsBold.handCoins,
    color: const Color(0xFFDC2626),
    items: [
      AccountMappingPurpose('payables',            tr('ذمم الموردون المحليون'),         '2111', tr('حساب الذمم الدائنة للموردين المحليين')),
      AccountMappingPurpose('foreign_payables',    tr('ذمم الموردون الخارجيون'),        '2112', tr('حساب الذمم الدائنة للموردين الخارجيين')),
      AccountMappingPurpose('notes_payable',       tr('أوراق الدفع'),                  '2113', tr('الشيكات وأوراق الدفع للموردين')),
      AccountMappingPurpose('output_vat',          tr('ضريبة القيمة المضافة محصلة'),   '2121', tr('ضريبة القيمة المضافة على المبيعات')),
      AccountMappingPurpose('income_tax',          tr('ضريبة الدخل'),                  '2122', tr('ضريبة الدخل المستحقة')),
      AccountMappingPurpose('accrued_salaries',    tr('رواتب مستحقة'),                 '2131', tr('الرواتب المستحقة غير المدفوعة')),
      AccountMappingPurpose('deferred_revenue',    tr('إيرادات مقدمة / مؤجلة'),        '2133', tr('الإيرادات المحصلة قبل التسليم (IFRS 15)')),
      AccountMappingPurpose('loans_payable',       tr('قروض بنكية'),                   '2141', tr('القروض البنكية وطويلة الأجل')),
    ],
  ),
  // ── المجموعة 4: الإيرادات ────────────────────────────────────────────────
  AccountMappingPurposeGroup(
    title: tr('الإيرادات'),
    icon: PhosphorIconsBold.trendUp,
    color: const Color(0xFF059669),
    items: [
      AccountMappingPurpose('sales',               tr('مبيعات محلية'),                 '4121', tr('حساب إيرادات المبيعات المحلية الرئيسي')),
      AccountMappingPurpose('export_sales',        tr('مبيعات تصدير'),                 '4122', tr('حساب إيرادات مبيعات التصدير')),
      AccountMappingPurpose('delivery_revenue',    tr('إيرادات التوصيل'),              '414',  tr('حساب إيرادات خدمات التوصيل')),
      AccountMappingPurpose('service_revenue',     tr('إيرادات الخدمات'),              '4131', tr('حساب إيرادات الخدمات ما بعد البيع')),
      AccountMappingPurpose('sales_return',        tr('مردودات المبيعات'),             '4211', tr('حساب مردودات وإرجاع المبيعات')),
      AccountMappingPurpose('sales_discount',      tr('خصم المبيعات الممنوح'),         '4212', tr('خصومات الفاتورة الممنوحة للعملاء')),
      AccountMappingPurpose('purchase_discount',   tr('خصم المشتريات المكتسب'),        '4316', tr('الخصم المحصل من الموردين عند الدفع المبكر')),
      AccountMappingPurpose('discount_received',   tr('خصم مكتسب (تسوية)'),            '4316', tr('خصم التسوية المكتسب عند استيفاء الديون')),
      AccountMappingPurpose('other_income',        tr('إيرادات متنوعة'),               '4315', tr('الإيرادات غير التشغيلية والمتنوعة')),
      AccountMappingPurpose('inventory_surplus',   tr('فائض مخزون'),                   '4317', tr('إيراد فائض الجرد عند زيادة المخزون الفعلي')),
      AccountMappingPurpose('cash_surplus',        tr('فائض نقدي'),                    '4318', tr('إيراد فائض الصندوق عند إغلاق الوردية')),
    ],
  ),
  // ── المجموعة 5: تكلفة البضاعة ───────────────────────────────────────────
  AccountMappingPurposeGroup(
    title: tr('تكلفة البضاعة المباعة'),
    icon: PhosphorIconsBold.shoppingCartSimple,
    color: const Color(0xFFB45309),
    items: [
      AccountMappingPurpose('cogs',                tr('تكلفة البضاعة المباعة'),        '5211', tr('حساب تكلفة المبيعات (COGS) الرئيسي')),
      AccountMappingPurpose('purchases',           tr('مشتريات'),                      '5211', tr('حساب المشتريات الرئيسي')),
      AccountMappingPurpose('purchase_return',     tr('مردودات مشتريات'),              '5214', tr('حساب مردودات وإرجاع المشتريات')),
    ],
  ),
  // ── المجموعة 6: المصروفات التشغيلية ─────────────────────────────────────
  AccountMappingPurposeGroup(
    title: tr('المصروفات التشغيلية'),
    icon: PhosphorIconsBold.trendDown,
    color: const Color(0xFFF59E0B),
    items: [
      AccountMappingPurpose('salary_expense',      tr('رواتب — إدارة'),                '621',  tr('حساب مصروفات الرواتب والأجور الإدارية')),
      AccountMappingPurpose('rent_expense',        tr('مصروف إيجار'),                  '623',  tr('حساب مصروفات الإيجار')),
      AccountMappingPurpose('discount_allowed',    tr('خصم مسموح للعملاء'),            '6215', tr('خصم التسوية الممنوح عند استيفاء الديون')),
      AccountMappingPurpose('inventory_shrinkage', tr('عجز مخزون'),                    '6216', tr('مصروف النقص والتلف في المخزون')),
      AccountMappingPurpose('cash_shortage',       tr('عجز نقدي'),                     '6217', tr('مصروف العجز النقدي عند إغلاق الوردية')),
      AccountMappingPurpose('misc_expense',        tr('مصروفات متنوعة'),               '6214', tr('حساب المصروفات العامة والمتنوعة')),
    ],
  ),
];
