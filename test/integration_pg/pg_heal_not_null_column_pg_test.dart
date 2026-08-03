// ═══════════════════════════════════════════════════════════════════════════
// تمريرة الإصلاح الذاتي بترمي في مسار الإقلاع — فئة v132 حرفياً
// ═══════════════════════════════════════════════════════════════════════════
//
// `_buildPgColumnDef` (database.dart) بيطلّع `NOT NULL` من `col.$nullable`
// و**بلا `DEFAULT`** لو العمود مالوش قيمة افتراضية في drift. وتمريرة التطابق
// بتستعمل نفس الجملة دي في `ALTER TABLE ... ADD COLUMN IF NOT EXISTS`.
//
// PostgreSQL **بترفض** `ADD COLUMN ... NOT NULL` بلا default على جدول فيه
// صفوف. الاستثناء بيتجمّع في `fatalErrors` ⇒ `PgSchemaParityException` ⇒
// `database_startup` بيعمل rethrow ⇒ شاشة Fatal / Block-all.
//
// وأسوأ من كده: زرار «إعادة المحاولة» بينفّذ `SELECT 1` اللي بيعيد تشغيل
// `beforeOpen` ⇒ نفس الـALTER ⇒ نفس الاستثناء. تطبيق متبهدل بشكل دائم،
// مالوش مخرج غير `--use-sqlite`.
//
// السيناريو ده مش افتراضي: `onUpgrade` بيتخطّى بالكامل على PG
// (`database.dart` — «PG uses fresh schema»)، فتمريرة التطابق هي **الآلية
// الوحيدة** اللي بتضيف عمود لجدول PG قايم. أي سيرفر اتبنى قبل ما عمود
// مطلوب يتضاف للسكيما بيعدّي من المسار ده بالظبط.
//
// المطلوب: مسار الإقلاع **ما يرميش أبداً**. العمود يتضاف nullable مع تحذير،
// وترقيته لـNOT NULL شغل سكربت تسوية خارج الإقلاع.

@Tags(['pg'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postgres/postgres.dart' as pg;
import 'package:ural_erp/core/logging/diagnostic_logger.dart';
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

Future<void> _admin(PostgresConfig config, List<String> statements) async {
  final conn = await pg.Connection.open(
    pg.Endpoint(
      host: config.host,
      port: config.port,
      database: config.database,
      username: config.username,
      password: config.password,
    ),
    settings: const pg.ConnectionSettings(
      sslMode: pg.SslMode.disable,
      connectTimeout: Duration(seconds: 10),
    ),
  );
  try {
    for (final s in statements) {
      await conn.execute(s);
    }
  } finally {
    await conn.close();
  }
}

void main() {
  group('تمريرة التطابق: عمود NOT NULL ناقص على جدول فيه صفوف', () {
    late PgTestFixture fx;

    setUpAll(() async {
      DiagnosticLogger.enableTestMode();
      fx = await bootPgTestSchema();
      await fx.db.customSelect('SELECT 1').get();
      await fx.tearDown();
    });

    test('الإقلاع بيعدّي بلا استثناء والعمود بيرجع', () async {
      final config = _readDsnFromEnv();

      // نحاكي سيرفر قايم اتبنى قبل ما العمود ده يدخل السكيما:
      // صف موجود + العمود مش موجود. `response_payload` معرَّف `text()`
      // مطلوب وبلا default — فالجملة المولَّدة هتبقى NOT NULL بلا DEFAULT.
      await _admin(config, [
        'ALTER TABLE processed_messages DROP COLUMN IF EXISTS response_payload',
        // صف واحد يكفي: PG بترفض ADD COLUMN NOT NULL بلا default على أي
        // جدول **مش فاضي**.
        "INSERT INTO processed_messages (idempotency_key, created_at) "
            "VALUES ('heal-not-null-probe', 0) "
            "ON CONFLICT (idempotency_key) DO NOTHING",
      ]);

      // شرط مسبق صريح: لازم يكون فيه صف فعلاً، وإلا الاختبار بيعدّي وهو
      // مش بيقيس حاجة (الـALTER بينجح على جدول فاضي).
      final probe = await pg.Connection.open(
        pg.Endpoint(
          host: config.host,
          port: config.port,
          database: config.database,
          username: config.username,
          password: config.password,
        ),
        settings: const pg.ConnectionSettings(sslMode: pg.SslMode.disable),
      );
      final rowCount = await probe
          .execute('SELECT count(*) FROM processed_messages');
      await probe.close();
      expect(rowCount.first.first, isNot(0),
          reason: 'الشرط المسبق: الجدول لازم يكون فيه صف — على جدول فاضي '
              'الـALTER بينجح والاختبار ما بيقيسش العطل.');

      DiagnosticLogger.enableTestMode();
      final db = AppDatabase.withExecutor(
        openPostgresConnection(config),
        isPostgres: true,
      );
      addTearDown(() async => db.close());

      // ده هو الادعاء: مسار الإقلاع ما بيرميش.
      await expectLater(
        db.customSelect('SELECT 1').get(),
        completes,
        reason: 'تمريرة التطابق بترمي PgSchemaParityException لأن '
            'ADD COLUMN NOT NULL بلا default مرفوضة على جدول فيه صفوف — '
            'وده بيقفل التطبيق على شاشة Fatal بلا مخرج.',
      );

      // والعمود لازم يكون رجع فعلاً (nullable مقبول — الغرض إن الأعمدة
      // ترجع من غير ما نكسّر الإقلاع).
      final cols = await db.customSelect(
        "SELECT is_nullable FROM information_schema.columns "
        "WHERE table_name = 'processed_messages' "
        "AND column_name = 'response_payload'",
      ).get();
      expect(cols, isNotEmpty,
          reason: 'العمود المفقود لازم يترجّع بتمريرة التطابق، مش يتساب.');
    });
  });
}
