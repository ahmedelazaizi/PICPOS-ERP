// بديل الويب لـ`api_handler.dart` (م3-9).
//
// `network_service.dart` يستورد `ApiHandler` ليشغّل خادم الـAPI المضمَّن —
// وهذا لا يعمل في المتصفح أصلاً (لا خادم). الاستيراد الأصلي كان يسحب إلى
// حزمة الويب كلَّ معالجات السيرفر (و`cfd_service` ← `cart_controller` من POS).
// هذا البديل يُختار بالاستيراد الشرطي (`dart.library.js_interop`)؛ الديسكتوب
// (io) يبقى على `ApiHandler` الفعلي دون تغيير.
import 'package:shelf_router/shelf_router.dart';

import '../../data/database/database.dart';

class ApiHandler {
  // ignore: avoid_unused_constructor_parameters
  ApiHandler(AppDatabase db, {String? webStaticDir});

  Router buildRouter() =>
      throw UnsupportedError('ApiHandler is not available on web');

  void broadcastChange(String table, {int? branchId}) {}
}
