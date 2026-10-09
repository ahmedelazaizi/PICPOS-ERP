// طبقة الدفاع البرمجيّة لقراءة الويب عبر drift remote.
//
// يُلفّ بها منفِّذُ قاعدة المضيف قبل تسليمه إلى `DriftServer`، فلا يصل إلى
// القاعدة من عميل الويب إلا استعلامُ SELECT مفحوصٌ واحد على جداولَ مسموحة:
//
//   * كلُّ أنواع الكتابة (insert/update/delete/custom/batched) والمعاملات
//     مرفوضةٌ صراحةً، و`close` لا يفعل شيئاً (المنفِّذ مشترَك مع المضيف).
//   * `runSelect` يُقبَل فقط إن كان أمراً واحداً يبدأ بـ SELECT أو WITH، بلا
//     PRAGMA/ATTACH/sqlite_master/pg_*/information_schema/INTO، وكلُّ جدولٍ
//     مذكور بعد FROM/JOIN ضمن [allowedTables]. الفحصُ بالتجزئة (tokens)
//     لا بمحلِّل SQL كامل، فالقاعدةُ: **الرفضُ عند الشكّ**.
//   * الأعمدة الحسّاسة تُفرَّغ في النتائج بسلسلة فارغة (لا null) كي لا يختلّ
//     تحليلُ العميل لأعمدة غير القابلة للـnull.
//
// هذه خطُّ الدفاع الأساسيّ؛ دورُ PostgreSQL للقراءة فقط إضافةٌ مستقبليّة.

import 'package:drift/drift.dart';
// ignore: experimental_member_use -- البروتوكول تجريبيّ ومثبَّتٌ على drift 2.32.1 بالضبط.
import 'package:drift/remote.dart';

/// رُفض الاستعلام أو العمليّة بحكم سياسة قراءة الويب.
class WebReadPolicyViolation implements Exception {
  WebReadPolicyViolation(this.reason);

  final String reason;

  @override
  String toString() => 'WebReadPolicyViolation: $reason';
}

/// خادمُ drift لقراءة الويب فوق [executor] المشترَك، مقيَّداً بـ[allowedTables].
///
/// البروتوكول التجريبيّ يشترط نفس إصدار drift على الطرفين.
DriftServer createWebReadDriftServer(
  QueryExecutor executor, {
  required Set<String> allowedTables,
}) {
  return DriftServer(
    executor.interceptWith(
      WebReadPolicyInterceptor(allowedTables: allowedTables),
    ),
    closeConnectionAfterShutdown: false,
    allowRemoteShutdown: false,
  );
}

class WebReadPolicyInterceptor extends QueryInterceptor {
  WebReadPolicyInterceptor({required Iterable<String> allowedTables})
    : allowedTables = {for (final t in allowedTables) t.toLowerCase()};

  /// أسماء الجداول المسموح قراءتها (أحرف صغيرة).
  final Set<String> allowedTables;

  /// أعمدةٌ تُفرَّغ قيمتُها في أيّ نتيجة بغضّ النظر عن الجدول.
  static const Set<String> sensitiveColumns = {
    'password_hash',
    'password_salt',
    'pin',
    'card_code',
    'client_secret',
    'key_hash',
    'ftp_password',
  };

  /// مفاتيح جدول `settings` الحسّاسة: القيمةُ تُفرَّغ.
  static final RegExp _sensitiveSettingKey = RegExp(
    r'password|passwd|secret|token|api_?key|license|private',
    caseSensitive: false,
  );

  static const Set<String> _forbiddenWords = {
    'pragma',
    'attach',
    'detach',
    'into',
    'load_extension',
    'sqlite_master',
    'sqlite_schema',
    'sqlite_temp_master',
    'sqlite_temp_schema',
    'sqlite_sequence',
    'sqlite_stat1',
    'insert',
    'update',
    'delete',
    'drop',
    'create',
    'alter',
    'vacuum',
    'reindex',
    'analyze',
    'begin',
    'commit',
    'rollback',
    'savepoint',
    'release',
  };

  static const Set<String> _endsFromList = {
    'where',
    'group',
    'order',
    'limit',
    'having',
    'union',
    'intersect',
    'except',
    'window',
    'offset',
  };

  // ─── العمليّات المرفوضة ────────────────────────────────────────────────

  Never _deny(String what) =>
      throw WebReadPolicyViolation('$what is not allowed on the web read path');

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async => _deny('insert');

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async => _deny('update');

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async => _deny('delete');

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async => _deny('custom statement');

  @override
  Future<void> runBatched(
    QueryExecutor executor,
    BatchedStatements statements,
  ) async => _deny('batched statements');

  @override
  TransactionExecutor beginTransaction(QueryExecutor parent) =>
      _deny('transaction');

  @override
  QueryExecutor beginExclusive(QueryExecutor parent) =>
      _deny('exclusive executor');

  /// المنفِّذ مشترَك مع المضيف: إغلاقُ عميل ويب لا يُغلق القاعدة.
  @override
  Future<void> close(QueryExecutor inner) async {}

  // ─── القراءة ───────────────────────────────────────────────────────────

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final check = _validate(statement);
    final rows = await executor.runSelect(statement, args);
    return _mask(rows, touchesSettings: check.touchesSettings);
  }

  _Check _validate(String sql) {
    final tokens = _tokenize(sql);
    if (tokens.isEmpty) throw WebReadPolicyViolation('empty statement');

    final first = tokens.first;
    if (!first.isWord || (first.text != 'select' && first.text != 'with')) {
      throw WebReadPolicyViolation('only SELECT/WITH statements are allowed');
    }

    for (final t in tokens) {
      if (t.kind == _Kind.literal || t.kind == _Kind.punct) continue;
      final text = t.text;
      if (_forbiddenWords.contains(text) && (t.isWord || _isNameLike(text))) {
        throw WebReadPolicyViolation('forbidden token: $text');
      }
      if (text.startsWith('pg_') ||
          text.startsWith('sqlite_') ||
          text.contains('information_schema')) {
        throw WebReadPolicyViolation('system catalog access: $text');
      }
    }

    final cteNames = _cteNames(tokens);
    final referenced = _referencedTables(tokens);
    for (final name in referenced) {
      if (cteNames.contains(name)) continue;
      if (!allowedTables.contains(name)) {
        throw WebReadPolicyViolation('table not allowed: $name');
      }
    }

    _checkSensitiveColumns(tokens);
    return _Check(touchesSettings: referenced.contains('settings'));
  }

  /// الكلمات المحجوزة لا تُعتبَر أسماءَ معرِّفاتٍ مقتبسة (مثل عمود `"update"`
  /// نادرٌ) — لكنّ أسماء الكتالوج تُفحَص للنوعين.
  static bool _isNameLike(String text) =>
      text.startsWith('sqlite_') || text.startsWith('pg_');

  Set<String> _cteNames(List<_Tok> t) {
    final names = <String>{};
    var depth = 0;
    for (var i = 0; i < t.length; i++) {
      final tok = t[i];
      if (tok.isPunct('(')) {
        depth++;
      } else if (tok.isPunct(')')) {
        depth--;
      } else if (depth == 0 && tok.isName) {
        var j = i + 1;
        if (j < t.length && t[j].isPunct('(')) {
          var d = 0;
          for (; j < t.length; j++) {
            if (t[j].isPunct('(')) d++;
            if (t[j].isPunct(')') && --d == 0) {
              j++;
              break;
            }
          }
        }
        if (j < t.length && t[j].isWord && t[j].text == 'as') {
          j++;
          if (j < t.length && t[j].isWord && t[j].text == 'not') j++;
          if (j < t.length && t[j].isWord && t[j].text == 'materialized') j++;
          if (j < t.length && t[j].isPunct('(')) names.add(tok.text);
        }
      }
    }
    return names;
  }

  /// أسماء الجداول بعد FROM/JOIN وبعد الفاصلة داخل قائمة FROM.
  Set<String> _referencedTables(List<_Tok> t) {
    final tables = <String>{};
    final inFromList = <int, bool>{};
    var depth = 0;
    var expectTable = false;

    for (var i = 0; i < t.length; i++) {
      final tok = t[i];

      if (expectTable) {
        expectTable = false;
        if (tok.isPunct('(')) {
          // استعلام فرعيّ فقط؛ أيُّ شكلٍ آخر (مجموعة joins) يُرفَض.
          final next = i + 1 < t.length ? t[i + 1] : null;
          if (next == null ||
              !next.isWord ||
              (next.text != 'select' && next.text != 'with')) {
            throw WebReadPolicyViolation('unsupported FROM construct');
          }
          // يُعالَج القوس في الدورة التالية كالمعتاد.
        } else if (tok.isName) {
          final after = i + 1 < t.length ? t[i + 1] : null;
          if (after != null && (after.isPunct('.') || after.isPunct('('))) {
            throw WebReadPolicyViolation(
              'qualified name or table function in FROM: ${tok.text}',
            );
          }
          tables.add(tok.text);
          continue;
        } else {
          throw WebReadPolicyViolation('unsupported FROM construct');
        }
      }

      if (tok.isPunct('(')) {
        depth++;
        continue;
      }
      if (tok.isPunct(')')) {
        inFromList.remove(depth);
        depth--;
        continue;
      }
      if (tok.isWord) {
        if (tok.text == 'from') {
          expectTable = true;
          inFromList[depth] = true;
        } else if (tok.text == 'join') {
          expectTable = true;
        } else if (_endsFromList.contains(tok.text)) {
          inFromList[depth] = false;
        }
      } else if (tok.isPunct(',') && (inFromList[depth] ?? false)) {
        expectTable = true;
      }
    }
    if (expectTable) throw WebReadPolicyViolation('dangling FROM');
    return tables;
  }

  /// الأعمدة الحسّاسة تظهر فقط في قائمة SELECT كما هي (أو بتسميةٍ تنتهي
  /// بنفس الاسم)، فلا تُحوَّل ولا تُرشَّح ولا يُرتَّب بها، وإلا لأمكن تسريبها
  /// بتغيير اسم العمود في النتيجة أو بالاستدلال.
  void _checkSensitiveColumns(List<_Tok> t) {
    var firstFrom = t.length;
    for (var i = 0; i < t.length; i++) {
      if (t[i].isWord && t[i].text == 'from') {
        firstFrom = i;
        break;
      }
    }
    for (var i = 0; i < t.length; i++) {
      final tok = t[i];
      if (!tok.isName || !sensitiveColumns.contains(tok.text)) continue;

      var ok = i < firstFrom;
      if (ok) {
        var j = i - 1;
        while (j >= 1 && t[j].isPunct('.')) {
          j -= 2;
        }
        ok =
            j >= 0 &&
            (t[j].isPunct(',') ||
                (t[j].isWord &&
                    (t[j].text == 'select' || t[j].text == 'distinct')));
      }
      if (ok) {
        final next = i + 1 < t.length ? t[i + 1] : null;
        if (next == null) {
          ok = false;
        } else if (next.isPunct(',') || (next.isWord && next.text == 'from')) {
          ok = true;
        } else if (next.isWord && next.text == 'as') {
          final alias = i + 2 < t.length ? t[i + 2] : null;
          ok =
              alias != null &&
              alias.isName &&
              (alias.text == tok.text || alias.text.endsWith('.${tok.text}'));
        } else {
          ok = false;
        }
      }
      if (!ok) {
        throw WebReadPolicyViolation(
          'sensitive column used outside the select list: ${tok.text}',
        );
      }
    }
  }

  // ─── إخفاء النتائج ─────────────────────────────────────────────────────

  static String _bare(String column) {
    final c = column.toLowerCase();
    final dot = c.lastIndexOf('.');
    return dot < 0 ? c : c.substring(dot + 1);
  }

  List<Map<String, Object?>> _mask(
    List<Map<String, Object?>> rows, {
    required bool touchesSettings,
  }) {
    if (rows.isEmpty) return rows;

    String? keyColumn;
    if (touchesSettings) {
      for (final c in rows.first.keys) {
        if (_bare(c) == 'key') {
          keyColumn = c;
          break;
        }
      }
      if (keyColumn == null) {
        throw WebReadPolicyViolation(
          'settings must be read together with its key column',
        );
      }
    }

    return [
      for (final row in rows)
        () {
          final out = Map<String, Object?>.of(row);
          if (keyColumn != null) {
            final key = row[keyColumn];
            if (key is String && _sensitiveSettingKey.hasMatch(key)) {
              for (final c in out.keys.toList()) {
                if (c != keyColumn) out[c] = '';
              }
            }
          }
          for (final c in out.keys.toList()) {
            if (sensitiveColumns.contains(_bare(c))) out[c] = '';
          }
          return out;
        }(),
    ];
  }
}

class _Check {
  _Check({required this.touchesSettings});
  final bool touchesSettings;
}

// ─── التجزئة ───────────────────────────────────────────────────────────────

enum _Kind { word, quoted, literal, punct }

class _Tok {
  _Tok(this.kind, this.text);

  final _Kind kind;

  /// بأحرف صغيرة؛ لمحرف الترقيم هو المحرف نفسه.
  final String text;

  bool get isWord => kind == _Kind.word;

  /// اسمٌ (كلمة أو معرّف مقتبس).
  bool get isName => kind == _Kind.word || kind == _Kind.quoted;

  bool isPunct(String p) => kind == _Kind.punct && text == p;
}

List<_Tok> _tokenize(String sql) {
  final out = <_Tok>[];
  final n = sql.length;
  var i = 0;

  bool isWordChar(int c) =>
      (c >= 0x30 && c <= 0x39) ||
      (c >= 0x41 && c <= 0x5a) ||
      (c >= 0x61 && c <= 0x7a) ||
      c == 0x5f ||
      c == 0x24 ||
      c > 0x7f;

  while (i < n) {
    final ch = sql[i];
    final c = sql.codeUnitAt(i);
    if (c == 0) throw WebReadPolicyViolation('NUL character');
    if (ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' || ch == '\f') {
      i++;
    } else if (ch == '-' && i + 1 < n && sql[i + 1] == '-') {
      throw WebReadPolicyViolation('comments are not allowed');
    } else if (ch == '/' && i + 1 < n && sql[i + 1] == '*') {
      throw WebReadPolicyViolation('comments are not allowed');
    } else if (ch == "'") {
      i = _skipQuoted(sql, i, "'");
      out.add(_Tok(_Kind.literal, ''));
    } else if (ch == '"' || ch == '`') {
      final end = _skipQuoted(sql, i, ch);
      final body = sql.substring(i + 1, end - 1).replaceAll('$ch$ch', ch);
      out.add(_Tok(_Kind.quoted, body.toLowerCase()));
      i = end;
    } else if (ch == '[') {
      final end = sql.indexOf(']', i + 1);
      if (end < 0) throw WebReadPolicyViolation('unterminated identifier');
      out.add(_Tok(_Kind.quoted, sql.substring(i + 1, end).toLowerCase()));
      i = end + 1;
    } else if (isWordChar(c)) {
      var j = i;
      while (j < n && isWordChar(sql.codeUnitAt(j))) {
        j++;
      }
      out.add(_Tok(_Kind.word, sql.substring(i, j).toLowerCase()));
      i = j;
    } else {
      out.add(_Tok(_Kind.punct, ch));
      i++;
    }
  }

  // فاصلةٌ منقوطة أخيرة وحيدة مسموحة؛ أيُّ غيرها = أكثر من أمر.
  if (out.isNotEmpty && out.last.isPunct(';')) out.removeLast();
  if (out.any((t) => t.isPunct(';'))) {
    throw WebReadPolicyViolation('multiple statements');
  }
  return out;
}

/// يرجع فهرس ما بعد علامة الإغلاق؛ المحرف المكرَّر يهرِّب نفسه.
int _skipQuoted(String s, int start, String q) {
  var i = start + 1;
  while (i < s.length) {
    if (s[i] == q) {
      if (i + 1 < s.length && s[i + 1] == q) {
        i += 2;
        continue;
      }
      return i + 1;
    }
    i++;
  }
  throw WebReadPolicyViolation('unterminated quoted text');
}
