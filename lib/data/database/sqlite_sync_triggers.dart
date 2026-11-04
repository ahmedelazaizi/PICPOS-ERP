part of 'database.dart';

// ═══ INT-03 (الجولة الثانية، v198): مُشغِّلا ختمِ المزامنة على SQLite ═══
//
// سحبُ الدلتا (`GET /api/sync/pull`) يرشّح بـ`last_modified_at IS NOT NULL
// AND >= since`. على PostgreSQL يختم `fn_bump_row_version` (BEFORE INSERT OR
// UPDATE، `database_pg_sync_infra.dart`) كلَّ جدولٍ في
// [AppDatabase._syncHardenedTables]. أمّا SQLite فكان فيه:
//   • مُشغِّلُ التعديل `{t}_bump_version` من v129/v166/v167/v173 — يُنشأ في
//     `onUpgrade` **وحده**، فالقاعدةُ المنشأةُ من الصفر (`onCreate`) بلا أيّ
//     مُشغِّل: التعديلُ على خادم SQLite حديث لا يصل بالدلتا أبداً.
//   • وختمُ الإدراج كان داخل `AppDatabase.into()` (الجولة الأولى)، فلا يغطّي
//     `batch.insert` ولا SQL الخامّ (`customStatement('INSERT …')`).
//
// الحلّ هنا على مستوى القاعدة نفسها، فيغطّي كلَّ مسارات الكتابة:
//   `{t}_bump_version`      AFTER UPDATE — **الـSQL نفسُه** (سوى المسافات) الذي تُنشئه
//                           v129/v166/v167/v173، فالقاعدةُ الجديدة والمُرقّاة
//                           متطابقتان، و`IF NOT EXISTS` يُبقي مُشغِّلَ القاعدة
//                           المُرقّاة كما هو. الشرطُ `NEW.row_version =
//                           OLD.row_version` يقابل فرعَ UPDATE في PG: الكاتبُ
//                           الذي يرفع النسخةَ بنفسه (سحبٌ يعيد نسخةً بعينها،
//                           `wh_stock_guard`) لا يُمَسّ، وغيرُه يُرفع ويُختم.
//                           ولا تكرارَ: التعديلُ الداخليُّ يغيّر `row_version`
//                           فيبطل الشرطُ عليه.
//   `{t}_sync_stamp_insert` AFTER INSERT WHEN NEW.last_modified_at IS NULL —
//                           يختم بثواني "الآن" (القيمةُ التي يقارنها السحبُ
//                           و`serverTime`، وهي ما يخزّنه drift لـDateTime).
//                           والقيمةُ الصريحةُ تُحترم (صفٌّ مسحوبٌ يُطبَّق بختم
//                           الخادم) — وهذا عقدُ الجولة الأولى نفسُه. ⚠️ يخالف
//                           PG عمداً في هذه النقطة فقط: PG يكتب ختمَ الخادم فوق
//                           أيّ قيمة، وعلى SQLite يكون العميلُ نفسُه SQLite
//                           ويجب أن يحفظ ختمَ الخادم المسحوب.
//
// ⚠️ لماذا تعديلان داخل مُشغِّل الإدراج لا تعديلٌ واحد: SQLite لا يملك BEFORE
// INSERT يعدّل NEW، فالختمُ تعديلٌ لاحق — وذاك التعديلُ يُطلق `_bump_version`
// (المُشغِّلُ لا يُطلق نفسَه فقط حين `recursive_triggers` مطفأ؛ يُطلق غيرَه)،
// فيصير `row_version = 1` بينما PG يُبقيه 0 عند الإدراج. فالأوّلُ يختم ويغيّر
// النسخةَ (فيبطل شرطُ `_bump_version`)، والثاني يُعيدها إلى قيمة الإدراج (وهو
// تغييرٌ أيضاً فلا يُطلقه). النتيجة: ختمٌ + `row_version` كما أُدرج (0 افتراضاً،
// وCOALESCE لـNULL كما يفعل PG).
//
// ⚠️ وأُزيل ختمُ الجولة الأولى (`sync_insert_stamp.dart`: `AppDatabase.into()`
// كان يُرجع `InsertStatement` يضيف `last_modified_at = DateTime.now()` إلى قيم
// الإدراج على SQLite). صار مكرَّراً بلا فائدة: مُشغِّلُ الإدراج يعطي القيمةَ
// نفسَها (ثواني الساعة نفسِها)، ويحترم القيمةَ الصريحةَ مثله، ويُبقي
// `row_version` 0 مثله — ويغطّي فوقه `batch.insert` والـSQL الخامّ. أثبت ذلك
// `test/integration_devices/sqlite_sync_stamp_triggers_test.dart` (مسارُ DAO
// يمرّ بـ`into()`) و`device_to_device_sync_test` بعد الإزالة. الفرقُ الوحيد:
// `insertReturning` يُرجع الصفَّ قبل المُشغِّل AFTER (‏`lastModifiedAt` null
// في الكائن المُرجَع، مختومٌ في القاعدة)؛ والمستدعي الوحيدُ له على جدولٍ
// مزامَن (`attachments_dao`) يمرّر الختمَ صريحاً.
//
// متى تُنشأ: نهايةَ `onCreate`، وفي ترقية v198، وفي كلّ إقلاعٍ بعد
// `runBeforeOpen` (شفاءٌ ذاتيّ رخيص: جدولٌ مزامَنٌ يُنشأ لاحقاً بـSQL خامّ —
// مثل جداول المعدِّلات — أو أُعيد بناؤه يأخذ مُشغِّليه في الإقلاع التالي).
// الجدولُ الغائبُ أو الذي لا يملك `id`/`last_modified_at` يُتخطّى: مُشغِّلٌ يذكر
// عموداً غائباً يُنشأ بلا خطأ ثم يُسقط **كلَّ** إدراجٍ في الجدول.

/// Suffix of the SQLite AFTER INSERT stamping trigger (`{table}<suffix>`).
const String kSqliteSyncStampInsertSuffix = '_sync_stamp_insert';

extension SqliteSyncStampTriggers on AppDatabase {
  /// Installs the AFTER INSERT / AFTER UPDATE sync-stamp triggers on every
  /// existing table of [AppDatabase._syncHardenedTables]. Idempotent; no-op
  /// on PostgreSQL (its `fn_bump_row_version` trigger does the same job).
  Future<void> ensureSqliteSyncStampTriggers() async {
    if (_isPostgres) return;
    const tables = AppDatabase._syncHardenedTables;

    // Fast path: both triggers already on every table.
    final counts = (await customSelect(
      "SELECT "
      "SUM(name LIKE '%$kSqliteSyncStampInsertSuffix') AS ins, "
      "SUM(name LIKE '%_bump_version') AS upd "
      "FROM sqlite_master WHERE type = 'trigger'",
    ).getSingle()).data;
    if (((counts['ins'] as int?) ?? 0) >= tables.length &&
        ((counts['upd'] as int?) ?? 0) >= tables.length) {
      return;
    }

    // One query for the sync columns of every table.
    final columns = <String, Set<String>>{};
    for (final r in await customSelect(
      "SELECT m.name AS t, p.name AS c "
      "FROM sqlite_master m, pragma_table_info(m.name) p "
      "WHERE m.type = 'table' "
      "AND p.name IN ('id', 'last_modified_at', 'row_version')",
    ).get()) {
      columns.putIfAbsent(r.data['t'] as String, () => {}).add(
        r.data['c'] as String,
      );
    }

    for (final t in tables) {
      final cols = columns[t];
      if (cols == null ||
          !cols.contains('id') ||
          !cols.contains('last_modified_at')) {
        debugPrint('[SyncStamp] $t: missing table/columns — skipped');
        continue;
      }
      final hasVersion = cols.contains('row_version');
      try {
        if (hasVersion) {
          // Same SQL as the v129/v166/v167/v173 trigger.
          await customStatement('''
            CREATE TRIGGER IF NOT EXISTS ${t}_bump_version
            AFTER UPDATE ON $t FOR EACH ROW
            WHEN NEW.row_version = OLD.row_version
            BEGIN
              UPDATE $t SET
                last_modified_at = strftime('%s', 'now'),
                row_version = OLD.row_version + 1
              WHERE id = NEW.id;
            END
          ''');
        }
        await customStatement(_insertTriggerSql(t, hasVersion: hasVersion));
      } catch (e) {
        debugPrint('[SyncStamp] $t: $e');
      }
    }
  }

  String _insertTriggerSql(String t, {required bool hasVersion}) {
    const now = "CAST(strftime('%s', 'now') AS INTEGER)";
    final body = hasVersion
        ? 'UPDATE $t SET last_modified_at = $now, '
              'row_version = COALESCE(NEW.row_version, 0) + 1 '
              'WHERE id = NEW.id; '
              'UPDATE $t SET row_version = COALESCE(NEW.row_version, 0) '
              'WHERE id = NEW.id;'
        : 'UPDATE $t SET last_modified_at = $now WHERE id = NEW.id;';
    return 'CREATE TRIGGER IF NOT EXISTS $t$kSqliteSyncStampInsertSuffix '
        'AFTER INSERT ON $t FOR EACH ROW '
        'WHEN NEW.last_modified_at IS NULL '
        'BEGIN $body END';
  }
}
