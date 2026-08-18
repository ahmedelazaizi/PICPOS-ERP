/// حصرُ قائمة المخازن بفرع الجهاز — القاعدةُ مصدرُها واحد.
///
/// Spec 103: على جهاز عميلٍ مربوطٍ بفرع، يجب ألّا تعرض نافذةُ الفاتورة مخازنَ
/// فروعٍ أخرى. وإلّا حُفظت الفاتورةُ بـ`warehouseId` يُحلّ إلى `branchId` آخر،
/// فتختفي من قائمة فواتير الفرع الذي أصدرها.
///
/// **لماذا هنا لا في الودجت:** كانت القاعدةُ مكتوبةً سطراً بسطر داخل
/// `sales_invoice_dialogs.dart` وحدَه، فبقيت نافذةُ فاتورة المشتريات بلا حصرٍ
/// إطلاقاً — وهي تتقاسم النموذجَ نفسَه بين ملفَّي PicPos والكامل. ونسخُ
/// القاعدة في موضعٍ ثانٍ يعني نسختين تُصانان وتتباعدان، وهو بعينه ما فعلته
/// `_effectiveTotal` ثلاثَ مرّاتٍ قبل أن تُجمع. ودالّةٌ خالصةٌ هنا تُقاس
/// باختبار وحدةٍ بلا فتح شاشة — واختباراتُ الودجت في هذا المستودع تتعلّق عند
/// فتح الشاشات.
///
/// **الجزءُ غيرُ الخالص يبقى عند المستدعي:** `SyncInterceptor.isClientMode`
/// وقراءةُ `client_branch_id` من `SharedPreferences`. تمرَّر النتيجةُ هنا
/// كـ[clientBranchId]‏ — و`null` تعني «لا حصر».
library;

/// يُرجع المخازنَ التابعةَ لـ[clientBranchId]، أو [warehouses] كما هي.
///
/// [branchIdOf] تُستخرج بها هُويّةُ الفرع، فتصلح للنوعين معاً: `WarehouseData`
/// في مسار المبيعات و`Warehouse` المولَّد في مسار المشتريات.
///
/// **والرجوعُ إلى القائمة كاملةً عند عدم التطابق مقصودٌ لا إهمال:** فرعٌ بلا
/// مخزنٍ واحدٍ يجعل الحصرَ الصارمَ قائمةً فارغةً — أيْ نافذةً لا تُحفَظ منها
/// فاتورةٌ إطلاقاً. والقاعدةُ منقولةٌ بحرفها من مسار المبيعات العامل، لا
/// مخترَعةً هنا.
List<T> narrowWarehousesToClientBranch<T>({
  required List<T> warehouses,
  required int? clientBranchId,
  required int? Function(T warehouse) branchIdOf,
}) {
  if (clientBranchId == null) return warehouses;
  final matches =
      warehouses.where((w) => branchIdOf(w) == clientBranchId).toList();
  return matches.isEmpty ? warehouses : matches;
}
