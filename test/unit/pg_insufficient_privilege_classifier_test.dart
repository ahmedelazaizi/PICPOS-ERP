// ═══════════════════════════════════════════════════════════════════════════
// تصنيف خطأ الصلاحيات في مسار الإقلاع
// ═══════════════════════════════════════════════════════════════════════════
//
// مقيس على PG حيّة 2026-08-03: لما مستخدم قاعدة البيانات مالوش صلاحيات DDL
// على `public`، الفتح بيفشل بـ`ServerException 42501` خام طالع من جوّه آلية
// الترحيل بتاعة drift — **قبل** ما `beforeOpen` يشتغل خالص (متحقَّق بضبط
// موجب: اتصال الأدمن طلّع ١٥١ مدخل سجل، والمقيَّد طلّع صفر).
//
// يعني تمريرة التطابق (المرحلة ٢د) عمرها ما بتتنفّذ في الحالة دي، فمستحيل
// ترمي `PgSchemaParityException` اللي `main.dart` مستنّيها — رغم إن تعليقها
// بيوعد بالحرف إنها بترمي على «DDL permission denied».
//
// وقبل الإصلاح، الخطأ الخام كان بيقع في `catch` العام وبيتسجّل
// «continuing» ⇒ التطبيق بيكمّل على قاعدة مش قادر يستعملها: لا شاشة Fatal
// ولا سبب عربي، وفشل مشوّش بعدين.
//
// الاختبار ده بيثبّت المصنِّف اللي بيوجّه الحالة دي لشاشة Fatal. مقصود إنه
// ضيّق: لازم **ما** يصنّفش أخطاء التشغيل العادية كعطل إقلاع قاتل.

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/main.dart';

void main() {
  group('isPostgresInsufficientPrivilege', () {
    test('بيمسك الشكل الخام اللي اتقاس فعلاً على PG حيّة', () {
      // النص ده منقول حرفياً من مخرجات التشغيل على PostgreSQL 18.4.
      const measured =
          'Severity.error 42501: permission denied for schema public';
      expect(isPostgresInsufficientPrivilege(measured), isTrue);
    });

    test('بيمسك الشكل الملفوف من drift كمان', () {
      const wrapped =
          'DriftWrappedException: ServerException Severity.error 42501: '
          'permission denied for schema public';
      expect(isPostgresInsufficientPrivilege(wrapped), isTrue);
    });

    test('ما بيصنّفش أخطاء التشغيل العادية كعطل إقلاع', () {
      // الحالات دي **لازم** تعدّي للمسار العادي، مش لشاشة Fatal.
      const notPrivilege = [
        'Severity.error 23505: duplicate key value violates unique constraint',
        'Severity.error 42P01: relation "category_station_mappings" does not exist',
        'Severity.error 23502: column "response_payload" contains null values',
        'Severity.error 25P02: current transaction is aborted',
        'SocketException: Connection refused',
        'Bad state: Too many elements',
      ];
      for (final e in notPrivilege) {
        expect(isPostgresInsufficientPrivilege(e), isFalse,
            reason: 'ما ينفعش يتصنّف كعطل صلاحيات: $e');
      }
    });
  });
}
