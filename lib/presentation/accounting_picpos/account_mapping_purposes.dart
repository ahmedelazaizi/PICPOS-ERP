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
const accountMappingPurposeGroups = <AccountMappingPurposeGroup>[
  // ── المجموعة 1: النقدية والذمم ──────────────────────────────────────────
  AccountMappingPurposeGroup(
    title: 'النقدية والذمم المدينة',
    icon: PhosphorIconsBold.bank,
    color: Color(0xFF2563EB),
    items: [
      AccountMappingPurpose('cash',                'الصندوق الرئيسي',              '1111', 'حساب النقد الافتراضي للمبيعات والمصروفات النقدية'),
      AccountMappingPurpose('petty_cash',          'صندوق العهدة',                 '1112', 'صندوق النقد الصغير والعهد'),
      AccountMappingPurpose('bank',                'البنك الرئيسي',                '1113', 'حساب البنك للمدفوعات بالبطاقات والتحويلات'),
      AccountMappingPurpose('bank2',               'البنك الثاني',                 '1114', 'حساب البنك الاحتياطي الثاني'),
      AccountMappingPurpose('click',               'حساب Click / إلكتروني',        '1116', 'حساب المدفوعات الإلكترونية (Click/KNET)'),
      AccountMappingPurpose('receivables',         'ذمم العملاء المحليون',         '1121', 'حساب الذمم المدينة للعملاء المحليين'),
      AccountMappingPurpose('foreign_receivables', 'ذمم العملاء الخارجيون',        '1122', 'حساب الذمم المدينة للعملاء الخارجيين'),
      AccountMappingPurpose('notes_receivable',    'أوراق القبض',                  '1123', 'حساب الشيكات وأوراق القبض من العملاء'),
    ],
  ),
  // ── المجموعة 2: المخزون والأصول المتداولة ───────────────────────────────
  AccountMappingPurposeGroup(
    title: 'المخزون والأصول المتداولة',
    icon: PhosphorIconsBold.package,
    color: Color(0xFF7C3AED),
    items: [
      AccountMappingPurpose('inventory',           'مخزون البضاعة للبيع',          '1136', 'الحساب الرئيسي لمخزون بضاعة التجارة'),
      AccountMappingPurpose('raw_materials',       'مخزون المواد الخام',           '1131', 'مخزون المواد الخام للإنتاج'),
      AccountMappingPurpose('wip',                 'مخزون تحت التشغيل',            '1133', 'منتجات تحت الإنتاج (WIP)'),
      AccountMappingPurpose('applied_overhead',    'تحميل صناعي مطبّق',            '5138', 'الطرف الدائن لتحميل التكاليف غير المباشرة على أوامر التصنيع'),
      AccountMappingPurpose('goods_in_transit',    'بضاعة تامة / عبور',            '1134', 'المنتجات النهائية والبضاعة في الطريق'),
      AccountMappingPurpose('input_vat',           'ضريبة القيمة المضافة مدفوعة', '1141', 'ضريبة القيمة المضافة على المشتريات'),
      AccountMappingPurpose('prepaid_expenses',    'مصروفات مقدمة',                '1143', 'المصروفات المدفوعة مسبقاً'),
      AccountMappingPurpose('employee_advances',   'سلف الموظفين',                 '1146', 'السلف المدفوعة للموظفين'),
      AccountMappingPurpose('fixed_assets',        'الأصول الثابتة',               '1211', 'حساب الأصول الثابتة والمعدات'),
    ],
  ),
  // ── المجموعة 3: الخصوم والالتزامات ──────────────────────────────────────
  AccountMappingPurposeGroup(
    title: 'الخصوم والالتزامات',
    icon: PhosphorIconsBold.handCoins,
    color: Color(0xFFDC2626),
    items: [
      AccountMappingPurpose('payables',            'ذمم الموردون المحليون',         '2111', 'حساب الذمم الدائنة للموردين المحليين'),
      AccountMappingPurpose('foreign_payables',    'ذمم الموردون الخارجيون',        '2112', 'حساب الذمم الدائنة للموردين الخارجيين'),
      AccountMappingPurpose('notes_payable',       'أوراق الدفع',                  '2113', 'الشيكات وأوراق الدفع للموردين'),
      AccountMappingPurpose('output_vat',          'ضريبة القيمة المضافة محصلة',   '2121', 'ضريبة القيمة المضافة على المبيعات'),
      AccountMappingPurpose('income_tax',          'ضريبة الدخل',                  '2122', 'ضريبة الدخل المستحقة'),
      AccountMappingPurpose('accrued_salaries',    'رواتب مستحقة',                 '2131', 'الرواتب المستحقة غير المدفوعة'),
      AccountMappingPurpose('deferred_revenue',    'إيرادات مقدمة / مؤجلة',        '2133', 'الإيرادات المحصلة قبل التسليم (IFRS 15)'),
      AccountMappingPurpose('loans_payable',       'قروض بنكية',                   '2141', 'القروض البنكية وطويلة الأجل'),
    ],
  ),
  // ── المجموعة 4: الإيرادات ────────────────────────────────────────────────
  AccountMappingPurposeGroup(
    title: 'الإيرادات',
    icon: PhosphorIconsBold.trendUp,
    color: Color(0xFF059669),
    items: [
      AccountMappingPurpose('sales',               'مبيعات محلية',                 '4121', 'حساب إيرادات المبيعات المحلية الرئيسي'),
      AccountMappingPurpose('export_sales',        'مبيعات تصدير',                 '4122', 'حساب إيرادات مبيعات التصدير'),
      AccountMappingPurpose('delivery_revenue',    'إيرادات التوصيل',              '414',  'حساب إيرادات خدمات التوصيل'),
      AccountMappingPurpose('service_revenue',     'إيرادات الخدمات',              '4131', 'حساب إيرادات الخدمات ما بعد البيع'),
      AccountMappingPurpose('sales_return',        'مردودات المبيعات',             '4211', 'حساب مردودات وإرجاع المبيعات'),
      AccountMappingPurpose('sales_discount',      'خصم المبيعات الممنوح',         '4212', 'خصومات الفاتورة الممنوحة للعملاء'),
      AccountMappingPurpose('purchase_discount',   'خصم المشتريات المكتسب',        '4316', 'الخصم المحصل من الموردين عند الدفع المبكر'),
      AccountMappingPurpose('discount_received',   'خصم مكتسب (تسوية)',            '4316', 'خصم التسوية المكتسب عند استيفاء الديون'),
      AccountMappingPurpose('other_income',        'إيرادات متنوعة',               '4315', 'الإيرادات غير التشغيلية والمتنوعة'),
      AccountMappingPurpose('inventory_surplus',   'فائض مخزون',                   '4317', 'إيراد فائض الجرد عند زيادة المخزون الفعلي'),
      AccountMappingPurpose('cash_surplus',        'فائض نقدي',                    '4318', 'إيراد فائض الصندوق عند إغلاق الوردية'),
    ],
  ),
  // ── المجموعة 5: تكلفة البضاعة ───────────────────────────────────────────
  AccountMappingPurposeGroup(
    title: 'تكلفة البضاعة المباعة',
    icon: PhosphorIconsBold.shoppingCartSimple,
    color: Color(0xFFB45309),
    items: [
      AccountMappingPurpose('cogs',                'تكلفة البضاعة المباعة',        '5211', 'حساب تكلفة المبيعات (COGS) الرئيسي'),
      AccountMappingPurpose('purchases',           'مشتريات',                      '5211', 'حساب المشتريات الرئيسي'),
      AccountMappingPurpose('purchase_return',     'مردودات مشتريات',              '5214', 'حساب مردودات وإرجاع المشتريات'),
    ],
  ),
  // ── المجموعة 6: المصروفات التشغيلية ─────────────────────────────────────
  AccountMappingPurposeGroup(
    title: 'المصروفات التشغيلية',
    icon: PhosphorIconsBold.trendDown,
    color: Color(0xFFF59E0B),
    items: [
      AccountMappingPurpose('salary_expense',      'رواتب — إدارة',                '621',  'حساب مصروفات الرواتب والأجور الإدارية'),
      AccountMappingPurpose('rent_expense',        'مصروف إيجار',                  '623',  'حساب مصروفات الإيجار'),
      AccountMappingPurpose('discount_allowed',    'خصم مسموح للعملاء',            '6215', 'خصم التسوية الممنوح عند استيفاء الديون'),
      AccountMappingPurpose('inventory_shrinkage', 'عجز مخزون',                    '6216', 'مصروف النقص والتلف في المخزون'),
      AccountMappingPurpose('cash_shortage',       'عجز نقدي',                     '6217', 'مصروف العجز النقدي عند إغلاق الوردية'),
      AccountMappingPurpose('misc_expense',        'مصروفات متنوعة',               '6214', 'حساب المصروفات العامة والمتنوعة'),
    ],
  ),
];
