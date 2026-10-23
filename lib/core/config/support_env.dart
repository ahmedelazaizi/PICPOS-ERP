import 'package:picpos_erp/core/config/brand.dart';

/// متغيرات البيئة الخاصة بالدعم الفني (إعادة ضبط كلمة المرور… إلخ).
///
/// البادئة تتبع العلامة وقت الترجمة: PicPos يقرأ `PICPOS_<NAME>` فقط، فلا يظهر
/// اسم المنتج الآخر في حزمته (BRAND-005)؛ والعلامة البديلة تحتفظ باسمها القديم.
/// الشرط ثابت وقت الترجمة فيُحذف الفرع الآخر من الحزمة.
const String _kSupportEnvPrefix = Brand.isPicPos ? 'PICPOS' : 'URAL';

/// هل ضُبط `<PREFIX>_<name>=1` في [env]؟
bool supportEnvFlag(Map<String, String> env, String name) =>
    env['${_kSupportEnvPrefix}_$name'] == '1';
