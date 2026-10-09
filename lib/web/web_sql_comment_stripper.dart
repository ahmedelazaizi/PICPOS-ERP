// يزيل تعليقات SQL من استعلامات القراءة قبل إرسالها إلى المضيف.
//
// السبب: اعتراضُ سياسة القراءة على المضيف يرفض أيَّ تعليق (`--`/`/* */`) عمداً
// (ثغرة تهريب)، بينما استعلاماتُ التقارير القائمة في طبقة البيانات تحمل
// تعليقاتٍ توثيقيّة. الإزالةُ على العميل لا تُضعف الحماية: المضيف يبقى يفحص
// النصّ الواصل كما هو ويرفض أيَّ تعليقٍ يصله.
//
// الفحص واعٍ بالسلاسل: ما بين `'…'` و`"…"` و`` `…` `` لا يُمَسّ.
import 'package:drift/drift.dart';

/// يرجع [sql] بلا تعليقات (كل تعليق يُستبدل بمسافة).
String stripSqlComments(String sql) {
  final out = StringBuffer();
  final n = sql.length;
  var i = 0;
  while (i < n) {
    final ch = sql[i];
    if (ch == "'" || ch == '"' || ch == '`') {
      final start = i++;
      while (i < n) {
        if (sql[i] == ch) {
          if (i + 1 < n && sql[i + 1] == ch) {
            i += 2; // علامة اقتباس مضاعفة = هروب
            continue;
          }
          i++;
          break;
        }
        i++;
      }
      out.write(sql.substring(start, i));
    } else if (ch == '-' && i + 1 < n && sql[i + 1] == '-') {
      while (i < n && sql[i] != '\n') {
        i++;
      }
      out.write(' ');
    } else if (ch == '/' && i + 1 < n && sql[i + 1] == '*') {
      final end = sql.indexOf('*/', i + 2);
      i = end < 0 ? n : end + 2;
      out.write(' ');
    } else {
      out.write(ch);
      i++;
    }
  }
  return out.toString();
}

/// معترِض عميل: يمرّر استعلامات SELECT بلا تعليقات.
class StripCommentsInterceptor extends QueryInterceptor {
  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) =>
      executor.runSelect(stripSqlComments(statement), args);
}
