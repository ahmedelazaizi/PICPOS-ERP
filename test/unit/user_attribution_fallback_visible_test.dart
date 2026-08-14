// إسنادُ سجلٍّ إلى «admin» لأن صاحبَه مجهولٌ لا يقع صامتاً.
//
// ── البلاغ (المالك، 2026-08-14) ─────────────────────────────────────────────
// «تقريرُ المبيعات حسب المستخدم غيرُ دقيق.»
//
// ── آليّةٌ مقيسةٌ تُنتج بالضبط هذا العَرَض ────────────────────────────────
// `_resolveUserId` في `api_data_handler.dart` و`api_sales_handler.dart`:
// حين لا يجد السيرفرُ المستخدمَ الوارد من العميل — لا بالمعرِّف ولا باسم
// المستخدم — **يُسنِد السجلَّ إلى admin** كي لا يضيع. والقرارُ نفسُه سليم
// (فقدُ فاتورةٍ أسوأُ من إسنادها خطأً)، لكنه كان يقع بـ`debugPrint` وحدَه:
// أثرٌ يختفي في الإصدار، فلا أحدَ يعلم أن رقماً في «حسب الكاشير» ليس رقمَ
// صاحبِه. والمرشِّحُ نفسُه سليم (`s.userId.equals(userId)` في
// `sales_dao.dart`)، فالعطبُ في البيانات لا في الاستعلام.
//
// ── ما يقيسه هذا الملفّ ──────────────────────────────────────────────────
// أن مسارَ السقوط إلى admin يكتب أثراً **باقياً** (`DiagnosticLogger`) لا
// `debugPrint` وحدَه. لا يقيس أن العطبَ هو سببُ شكوى المالك بعينِه — ذلك
// يُقاس على قاعدته بعد أن يصير المسارُ مرئياً.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _handlersWithFallback = <String>[
  'lib/services/api/api_data_handler.dart',
  'lib/services/api/api_sales_handler.dart',
];

/// جسمُ `_resolveUserId` — من توقيعِها إلى نهاية الدالّة (تقريبٌ بالأقواس).
///
/// ⚠️ البدءُ من `async` لا من التوقيع: التوقيعُ نفسُه فيه
/// `{String? fallbackUsername}`، فأوّلُ `{` بعده هو قوسُ المعامل الاختياريّ
/// لا قوسُ الجسم — والعدُّ منه يغلق فوراً فيُرجِع الحارسُ نصَّ المعامل
/// ويقيس فراغاً (وقع فعلاً في أوّل تشغيلٍ لهذا الملفّ).
String _resolveUserIdBody(String src) {
  final start = src.indexOf('Future<int> _resolveUserId(');
  if (start == -1) return '';
  final asyncAt = src.indexOf('async', start);
  if (asyncAt == -1) return '';
  var depth = 0;
  var i = src.indexOf('{', asyncAt);
  if (i == -1) return '';
  final begin = i;
  for (; i < src.length; i++) {
    if (src[i] == '{') depth++;
    if (src[i] == '}') {
      depth--;
      if (depth == 0) return src.substring(begin, i + 1);
    }
  }
  return src.substring(begin);
}

void main() {
  for (final path in _handlersWithFallback) {
    group(path.split('/').last, () {
      late String body;

      setUpAll(() {
        body = _resolveUserIdBody(File(path).readAsStringSync());
      });

      test('الدالّةُ موجودةٌ ولها جسمٌ يُقرأ — وإلا فالحارسُ يقيس فراغاً', () {
        // `indexOf` يرجع -1 وهو «أصغرُ من» كلِّ شيء: حارسٌ يمرّ لأن ما يقيسه
        // غيرُ موجودٍ هو أسوأُ من حارسٍ يسقط.
        expect(body, isNotEmpty);
        expect(body.contains("username.equals('admin')"), isTrue,
            reason: 'مسارُ السقوط إلى admin تغيّر شكلُه — راجِع الحارس');
      });

      test('ومسارُ السقوط يكتب أثراً باقياً لا debugPrint وحدَه', () {
        expect(
          body.contains('DiagnosticLogger'),
          isTrue,
          reason: 'الإسنادُ إلى admin يقع بلا أثرٍ يبقى بعد الإصدار — '
              'فرقمٌ في «حسب الكاشير» يكذب ولا سبيلَ لكشفِه',
        );
      });
    });
  }
}
