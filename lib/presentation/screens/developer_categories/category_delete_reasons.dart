import 'package:picpos_erp/core/i18n/tr.dart';

import '../../../data/providers/providers.dart'
    show CategoryDeleteAnalysis, CategoryDeleteBlock;

/// نصُّ سببِ منعِ الحذف بأعدادٍ واضحة — يُعرض للمستخدم كما هو.
String categoryDeleteBlockText(
  CategoryDeleteBlock reason,
  CategoryDeleteAnalysis a,
) {
  switch (reason) {
    case CategoryDeleteBlock.systemDefault:
      return tr('تصنيف افتراضي للنظام — لا يمكن حذفه.');
    case CategoryDeleteBlock.locked:
      return tr('التصنيف مقفل — افتح قفله أولاً ثم أعد المحاولة.');
    case CategoryDeleteBlock.hasChildren:
      return tr(
        'يحتوي على {n} تصنيف فرعي نشط — احذف التصنيفات الفرعية أو انقلها أولاً.',
        {'n': a.activeChildren},
      );
    case CategoryDeleteBlock.hasProducts:
      return tr(
        'يحتوي على {n} صنف ({active} نشط و{inactive} غير نشط) — انقل الأصناف إلى تصنيف آخر أولاً.',
        {
          'n': a.totalProducts,
          'active': a.activeProducts,
          'inactive': a.inactiveProducts,
        },
      );
    case CategoryDeleteBlock.badDestination:
      return tr('تصنيف الوجهة غير صالح.');
  }
}

/// نصُّ سجلّ النشاط عند الحذف من أدوات المطوّر: المنفِّذ يُسجَّل بحقل المستخدم،
/// والنصُّ يحمل الاسمَ والمعرّفَ العالميَّ والأعداد.
String categoryDeleteAuditText(CategoryDeleteAnalysis a) {
  final c = a.category!;
  return tr(
    'حذف تصنيف من أدوات المطوّر: {name} (المعرّف العالمي: {gid}) — أصناف: {n}، فواتير مرتبطة: {inv}',
    {
      'name': c.name,
      'gid': c.globalId ?? '-',
      'n': a.totalProducts,
      'inv': a.invoicedItems,
    },
  );
}
