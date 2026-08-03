// ═══════════════════════════════════════════════════════════════════════════
// عدّاد أرقام المستندات بيتقري بلا قفل ⇒ رقمين فاتورة متطابقين على PostgreSQL
// ═══════════════════════════════════════════════════════════════════════════
//
// `generateInvoiceNumber` بيعمل جوه ترانزاكشن:
//
//     SELECT next_value FROM document_sequences WHERE prefix = ?   ← بلا قفل
//     ... احسب ...
//     UPDATE document_sequences SET next_value = next_value + 1
//
// مافيش `SELECT ... FOR UPDATE`. على SQLite قفل الكتابة العام بيسلسل ده
// ضمنياً فالعطل مستخبي. على PostgreSQL تحت `READ COMMITTED`:
//
//     T1: SELECT → N
//     T2: SELECT → N          ← لسه ماحدش قفل الصف
//     T1: UPDATE → N+1 (بيقفل الصف) ، commit
//     T2: UPDATE → N+1 (كان مستني القفل) ، commit
//     ⇒ الاتنين رجّعوا الرقم N
//
// والتعليق في `database.dart` بيقول إن الوحدانية «مضمونة بـ… الـUNIQUE index
// على invoice_number». **مافيش أي فهرس أو قيد كده على أي باكيند** — الفهرس
// الفريد الجزئي اتأجّل عن قصد (شوف client_issue_m4_duplicate_invoice_no_test)
// لأن قواعد العملاء ممكن تكون فيها تكرارات قايمة. فمفيش أي شبكة أمان خلف
// العدّاد.
//
// الاختبار ده بيحتاج **اتصالين** — `PgDatabase` اتصال واحد ودرايفت بيسلسل
// كل الجُمل عليه بقفل داخلي، فالسباق مش قابل للتكاثر جوه نسخة واحدة. الحالة
// الحقيقية: سيرفر + مرآة/سيرفر تاني على نفس القاعدة.

@Tags(['pg'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/connection_io.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/database/pg_config.dart';

import '_support/pg_fixture.dart';

PostgresConfig _readDsnFromEnv() {
  final dsn = Platform.environment['PG_TEST_DSN']!;
  final uri = Uri.parse(dsn);
  final userInfo = uri.userInfo.split(':');
  return PostgresConfig(
    host: uri.host,
    port: uri.port == 0 ? 5432 : uri.port,
    database: uri.pathSegments.isNotEmpty ? uri.pathSegments.first : 'postgres',
    username: userInfo.isNotEmpty ? userInfo.first : 'postgres',
    password: userInfo.length > 1 ? userInfo[1] : '',
  );
}

void main() {
  group('document_sequences تحت التزامن على PostgreSQL', () {
    late PgTestFixture fx;
    late AppDatabase dbB;

    setUpAll(() async {
      fx = await bootPgTestSchema();
      await fx.db.customSelect('SELECT 1').get();
      // اتصال تاني مستقل على نفس القاعدة — ده اللي بيخلّي السباق ممكن أصلاً.
      final config = _readDsnFromEnv();
      dbB = AppDatabase.withExecutor(
        openPostgresConnection(config),
        isPostgres: true,
      );
      await dbB.customSelect('SELECT 1').get();
    });

    tearDownAll(() async {
      await dbB.close();
      await fx.tearDown();
    });

    test('نداءان متزامنان على اتصالين ما يرجّعوش نفس الرقم', () async {
      const prefix = 'RACEPROBE';
      const rounds = 8;

      // `generateInvoiceNumber` بيفرض إنه يتنادى جوه ترانزاكشن الطالب
      // (‏066 D5-001) عشان تقدّم العدّاد وإدخال المستند يبقوا ذرّة واحدة.
      // ده بالظبط شكل النداء الحقيقي في كل مسارات البيع والشراء.
      Future<String> alloc(AppDatabase db) =>
          db.transaction(() => db.generateInvoiceNumber(prefix));

      // نداء واحد الأول عشان صف العدّاد يتعمل. من غير ده الاتنين بيدخلوا
      // فرع «أول استعمال» وبيصطدموا على INSERT (‏23505 على
      // document_sequences_pkey) — سباق حقيقي بردو، بس مش اللي بنقيسه هنا.
      await alloc(fx.db);

      final issued = <String>[];
      for (var i = 0; i < rounds; i++) {
        // نداءان في نفس اللحظة، واحد على كل اتصال.
        final results = await Future.wait<String>([
          alloc(fx.db),
          alloc(dbB),
        ]);
        issued.addAll(results);
      }

      final unique = issued.toSet();
      expect(
        unique.length,
        issued.length,
        reason: 'اتصرف ${issued.length} رقم والمتفرّد منهم ${unique.length}. '
            'التكرارات: '
            '${issued.where((n) => issued.where((m) => m == n).length > 1).toSet()}. '
            'القراءة من document_sequences بلا SELECT ... FOR UPDATE، '
            'فاتنين بيقروا نفس next_value قبل ما أي واحد فيهم يقفل الصف.',
      );
    });
  });
}
