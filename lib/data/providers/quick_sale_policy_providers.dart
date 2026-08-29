import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/quick_sale_policy.dart';
import 'providers.dart';

/// مفاتيحُ سياسة البيع السريع كلُّها — بما فيها المرايا ومجموعاتُ الاختيار.
///
/// تُشتقُّ من النموذج لا تُكتب يدويّاً: قائمةٌ يدويّةٌ لا تكبر مع الشاشة
/// تترك مفتاحاً لا يُقرأ، فيبدو الإعدادُ محفوظاً وهو لا يعود أبداً.
Set<String> get quickSalePolicyKeys => {
      for (final row in kQuickSaleRows) row.settingKey,
      for (final row in kQuickSaleRows)
        if (row.mirrorKey != null) row.mirrorKey!,
      for (final pick in kQuickSalePicks) pick.settingKey,
    };

/// قيمُ السياسة كما هي في القاعدة.
///
/// ⚠️ **قراءةٌ مباشرةٌ لا مُخزَّنة.** `getSettingValue` يصل الجدولَ في كلِّ
/// نداء، فلا يحتاج مفتاحاً في `preloadKeys` بـ`main.dart`. والقراءةُ
/// المُخزَّنةُ المتزامنةُ تُرجع `null` عند إخفاق الكاش لا عند غياب المفتاح —
/// وهو ما يُميت الميزةَ صامتةً؛ فهذا المسارُ يتجنّبه أصلاً.
///
/// والمفتاحُ الغائبُ **لا يُكتب في الخريطة**: `QuickSalePolicyValues` تفرّق
/// بين «غائبٍ ⇒ افتراضُ التصميم» و«موجودٍ بقيمة».
final quickSalePolicyProvider =
    FutureProvider<QuickSalePolicyValues>((ref) async {
  final db = ref.watch(databaseProvider);
  final raw = <String, String>{};

  for (final key in quickSalePolicyKeys) {
    final value = await db.getSettingValue(key);
    if (value != null) raw[key] = value;
  }

  return QuickSalePolicyValues(raw);
});
