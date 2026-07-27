// ═══════════════════════════════════════════════════════════════════════════
// تفريغ الـ WAL قبل أخذ نسخة احتياطية
// ═══════════════════════════════════════════════════════════════════════════
//
// الاتصال بيشتغل `PRAGMA journal_mode = WAL`، يعني المعاملات بتتكتب في ملف
// `<db>-wal` جنب الداتابيز، وما بتتنقلش لملف الداتابيز نفسه غير عند الـ
// checkpoint. و`wal_autocheckpoint = 500` صفحة بيخلّي ده يحصل تلقائياً، بس
// **مش فوراً** — في أي لحظة بيبقى فيه شغل موجود في الـ WAL بس.
//
// ونسخ الاحتياطي بينسخ ملف `.db` **لوحده**. فمن غير checkpoint، النسخة
// بتعكس آخر نقطة تفريغ مش الحالة دلوقتي. على جهاز تجريبي واحد كان الـ WAL
// ٢ ميجا والداتابيز ١.٨ ميجا — يعني ممكن يبقى أكبر من الداتابيز نفسها.
//
// وde بيبقى خطير تحديداً مع **أدوات تصفير البيانات**: النسخة الإجبارية اللي
// بتتاخد قبل الحذف هي طريق الرجوع الوحيد، ونسخة ناقصة معناها إن اللي هيرجع
// أقل من اللي اتحذف.
//
// ليه ملف منفصل، وليه بيتبعت لـ `createDatabaseBackup` كـ callback:
// دوال النسخ في `connection_io.dart` **مالهاش مقبض داتابيز** — هي بتشتغل
// على المسارات بس. وتمرير `AppDatabase` ليها كان معناه إن `connection_io`
// يستورد `database.dart`، وده بيقفل دورة استيراد لأن `database.dart`
// بيستورده هو عبر `connection.dart` — نفس المشكلة المكتوبة في
// `sync_interceptor.dart`. الدالة هنا بتاخد نوع drift عام، فمفيش دورة.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

/// بينفّذ `PRAGMA wal_checkpoint(TRUNCATE)` وبيرجع `true` لو الـ WAL اتنقل
/// بالكامل لملف الداتابيز.
///
/// الـ PRAGMA بيرجع صف `(busy, log, checkpointed)`. `busy = 0` معناها إن
/// الـ checkpoint خلص من غير ما يتعارض مع قارئ تاني — وهي الحالة الوحيدة
/// اللي نقدر نقول بعدها إن ملف الـ `.db` لوحده كامل.
///
/// بيرجع `false` بدل ما يرمي: على PostgreSQL الـ PRAGMA مش موجود أصلاً،
/// وعلى SQLite ممكن يفشل لو فيه اتصال تاني ماسك قفل قراءة.
Future<bool> walCheckpointTruncate(DatabaseConnectionUser db) async {
  try {
    final rows = await db.customSelect('PRAGMA wal_checkpoint(TRUNCATE)').get();
    if (rows.isEmpty) return false;

    final data = rows.first.data;
    // بالاسم لو متاح، وبالترتيب لو الـ driver مسمّاش الأعمدة.
    final busy = data['busy'] ?? (data.isEmpty ? null : data.values.first);
    final ok = busy == 0;
    if (!ok) {
      debugPrint('[WAL] checkpoint(TRUNCATE) busy — result: $data');
    }
    return ok;
  } catch (e) {
    debugPrint('[WAL] checkpoint(TRUNCATE) failed: $e');
    return false;
  }
}
