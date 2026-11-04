part of 'database.dart';

/// ترجمةُ SQLite→PostgreSQL (`PgCompatSql`) **عند المصدر** لكلّ مداخل SQL
/// الخامّ في drift، لا عند `_PgCompatInterceptor` وحدَه.
///
/// السببُ الجذريُّ المقيس (42601 «syntax error at or near ","» عند الإقلاع):
/// ما يعمل داخلَ `beforeOpen` يصل `_PgDelegate` مباشرةً دون المُعترِض
/// (انظر `database_pg_create.dart`). وكان `customStatement` و`customSelect`
/// وحدَهما مُترجَمَين عند المصدر، أمّا `customUpdate` و`customInsert`
/// و`customWriteReturning` فتمرّ خامّةً، فتصل `?` إلى الخادم كما هي
/// (`UPDATE location_stock SET quantity = ?, …` من `syncDefaultBinStock`
/// أثناء `ProvisioningApplier.ensure`).
///
/// الدالّتان محايدتان (idempotent): مرورُهما ثانيةً عبر المُعترِض بلا أثر،
/// وعلى SQLite تُترك الجملةُ والوسائطُ كما هي.
mixin PgSourceSqlTranslation on DatabaseConnectionUser {
  bool get isPostgres;

  String _pgSql(String sql) => isPostgres ? PgCompatSql.fixSql(sql) : sql;

  @override
  Future<void> customStatement(String statement, [List<dynamic>? args]) {
    if (!isPostgres) return super.customStatement(statement, args);
    return super.customStatement(
      PgCompatSql.fixSql(statement),
      args == null ? null : PgCompatSql.fixArgs(args),
    );
  }

  @override
  Selectable<QueryRow> customSelect(
    String query, {
    List<Variable> variables = const [],
    Set<ResultSetImplementation> readsFrom = const {},
  }) {
    // المتغيّراتُ تبقى كما هي — الترتيبُ الموضعيُّ نفسُه، و`fixSql` ترقّم
    // العلاماتِ من اليسار لليمين فتبقى المطابقةُ صحيحة.
    return super.customSelect(
      _pgSql(query),
      variables: variables,
      readsFrom: readsFrom,
    );
  }

  @override
  Future<int> customUpdate(
    String query, {
    List<Variable> variables = const [],
    Set<ResultSetImplementation>? updates,
    UpdateKind? updateKind,
  }) {
    return super.customUpdate(
      _pgSql(query),
      variables: variables,
      updates: updates,
      updateKind: updateKind,
    );
  }

  @override
  Future<int> customInsert(
    String query, {
    List<Variable> variables = const [],
    Set<ResultSetImplementation>? updates,
  }) {
    return super.customInsert(
      _pgSql(query),
      variables: variables,
      updates: updates,
    );
  }

  @override
  Future<List<QueryRow>> customWriteReturning(
    String query, {
    List<Variable> variables = const [],
    Set<ResultSetImplementation>? updates,
    UpdateKind? updateKind,
  }) {
    return super.customWriteReturning(
      _pgSql(query),
      variables: variables,
      updates: updates,
      updateKind: updateKind,
    );
  }
}
