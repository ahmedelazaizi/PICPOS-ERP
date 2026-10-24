// تهيئةُ خادم PostgreSQL للمعالج — منطقٌ منقولٌ حرفياً من
// `setup_wizard/step_provisioning.dart` (‏P0 من خطة إعادة تصميم الإعداد الأول).
//
// ⚠️ لا `setState` ولا `mounted` ولا `exit` هنا: الخدمةُ تُرجع نتائجَ أو تبثّ
// تقدّماً عبر `onStep`، والشاشةُ هي التي ترسم وتقرّر. فسقوطُ الاتصال يُرجع
// رسالةً ولا يُنهي العملية.
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/i18n/tr.dart';
import '../../data/database/connection.dart'
    show openPostgresConnection, testPostgresConnection;
import '../../data/database/database_barrel.dart';
import '../../data/database/pg_config.dart';

/// حالةُ صفٍّ واحدٍ من صفوف التهيئة.
enum ProvisionStatus { pending, running, ok, failed }

/// يفتح اتصالَ PostgreSQL المغلَّف بـDrift — يُحقن في الاختبار.
typedef PgDatabaseOpener = AppDatabase Function(PostgresConfig cfg);

/// يختبر الاتصال: `null` = نجاح، وإلا نصُّ الخطأ.
typedef PgConnectionTester = Future<String?> Function(PostgresConfig cfg);

/// نتيجةُ [ServerProvisioningService.provision].
class ProvisionOutcome {
  const ProvisionOutcome.success() : error = null;
  const ProvisionOutcome.failure(String this.error);

  final String? error;
  bool get ok => error == null;
}

class ServerProvisioningService {
  ServerProvisioningService({
    PgConnectionTester? testConnection,
    PgDatabaseOpener? openDatabase,
  })  : _test = testConnection ?? testPostgresConnection,
        _open = openDatabase ??
            ((cfg) => AppDatabase.withExecutor(
                  openPostgresConnection(cfg),
                  isPostgres: true,
                ));

  final PgConnectionTester _test;
  final PgDatabaseOpener _open;

  /// اختبارُ اتصالٍ منفرد (‏زرّ «اختبار الاتصال»): رسالةُ الخطأ أو `null`.
  /// أيُّ استثناءٍ يتحوّل إلى نصّ — لا يخرج من هنا.
  Future<String?> testConnection(PostgresConfig cfg) async {
    try {
      return await _test(cfg);
    } catch (e) {
      return '$e';
    }
  }

  /// يشغّل خطواتِ التهيئة الستّ بالترتيب. [onStep] يُستدعى عند كلّ انتقالٍ
  /// (‏`running` ثمّ `ok`/`failed`) مع تفصيلٍ اختياريّ. عند أوّل فشلٍ يتوقّف.
  Future<ProvisionOutcome> provision(
    PostgresConfig cfg, {
    void Function(int index, ProvisionStatus status, String? detail)? onStep,
  }) async {
    AppDatabase? db;
    Future<void> step(int i, Future<String?> Function() body) async {
      onStep?.call(i, ProvisionStatus.running, null);
      try {
        final detail = await body();
        onStep?.call(i, ProvisionStatus.ok, detail);
      } catch (e) {
        onStep?.call(i, ProvisionStatus.failed, e.toString());
        rethrow;
      }
    }

    try {
      await step(0, () async {
        final err = await _test(cfg);
        if (err != null) throw Exception('فشل الاتصال: $err');
        return null;
      });

      db = _open(cfg);
      final opened = db;

      await step(1, () async {
        // يلمس القاعدةَ فتعمل onCreate / beforeOpen.
        await opened.customSelect('SELECT 1').get();
        return null;
      });

      // الزرعُ الذرّيّ مرّةً واحدة (‏idempotent) ثمّ يُبلَّغ عن أجزائه.
      SeedResult? result;
      await step(2, () async {
        result = await opened.seedInitialDataPostgresAtomic();
        return null;
      });
      await step(3, () async {
        final r = result;
        if (r == null) throw Exception('الخطوة السابقة لم تُنفذ');
        return tr('{p0} حساب جديد', {'p0': r.accounts});
      });
      await step(4, () async {
        final r = result;
        if (r == null) throw Exception('الخطوة السابقة لم تُنفذ');
        return r.fiscalYear > 0
            ? tr('تم إنشاء السنة المالية')
            : tr('موجودة مسبقاً');
      });
      await step(5, () async {
        final check = await opened.verifyPostgresBaseline();
        final detail = tr('{p0} حساب، {p1} أدوار', {
          'p0': check.counts['accounts'] ?? 0,
          'p1': check.counts['roles'] ?? 0,
        });
        if (!check.ok) {
          throw Exception('باقية جداول ناقصة: ${check.missing.join(', ')}');
        }
        return detail;
      });
      return const ProvisionOutcome.success();
    } catch (e, st) {
      debugPrint('[Provisioning] FAILED: $e\n$st');
      return ProvisionOutcome.failure(e.toString());
    } finally {
      try {
        await db?.close();
      } catch (_) {}
    }
  }

  /// يحفظ إعدادَ PostgreSQL ويُسلّح بوّابةَ الإقلاع: `main.dart` لا يحاول PG ما
  /// لم يكن `pg_provisioned_ok` صحيحاً — ولا يُكتَب إلا بعد نجاح الاختبار
  /// والمخطّط والتحقّق.
  Future<void> armPostgresMode(PostgresConfig cfg) async {
    await cfg.save();
    await PostgresConfig.saveMode(DatabaseMode.postgres);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('pg_provisioned_ok', true);
    } catch (_) {}
  }

  /// يكتب اسمَ الشركة و`setup_completed` و`network_mode=server` في قاعدة
  /// الخادم الجديدة ليراها المستخدمُ بعد إعادة التشغيل. فشلُه غيرُ قاتل
  /// (‏يُسجَّل فقط) كما كان.
  ///
  /// UPDATE ثمّ INSERT-إن-صفر: بلا `ON CONFLICT (key)` الذي يرفع 42P10 على
  /// جدولٍ أُنشئ بترحيلٍ قديمٍ بلا PK — النمطُ يعمل على أيّ لهجة.
  Future<void> persistServerSettings(
    PostgresConfig cfg, {
    required String companyName,
  }) async {
    try {
      final pgDb = _open(cfg);
      if (companyName.isNotEmpty) {
        await pgDb.customStatement(
          "UPDATE settings SET value = ? WHERE key = 'company_name'",
          [companyName],
        );
      }
      await _upsert(pgDb, 'setup_completed', 'true');
      await _upsert(pgDb, 'network_mode', 'server');
      await pgDb.close();
    } catch (e) {
      debugPrint('[SetupWizard] persist company_name to PG: $e');
    }
  }

  Future<void> _upsert(AppDatabase db, String key, String value) async {
    await db.customStatement(
      "UPDATE settings SET value = '$value' WHERE key = '$key'",
    );
    final existing = await db
        .customSelect("SELECT 1 AS x FROM settings WHERE key = '$key'")
        .get();
    if (existing.isEmpty) {
      await db.customStatement(
        "INSERT INTO settings (key, value) VALUES ('$key', '$value')",
      );
    }
  }
}
