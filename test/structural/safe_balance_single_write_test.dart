// حارسٌ بنيويّ — رصيدُ الخزنة يتحرّك **مرّةً واحدة** وبحسابٍ ذرّيّ.
//
// ── لماذا حارسٌ بنيويٌّ لا سلوكيّ ──────────────────────────────────────────
// فئةُ العطب هنا: «مسارٌ نقديٌّ **جديد** كتب الرصيدَ بيده». والاختبارُ
// السلوكيُّ لا يغطّي إلا المسارات التي تذكّر أحدٌ أن يكتب لها اختباراً —
// وهي كانت ستّةً من عشرين. الحارسُ يرى العشرين.
//
// وفيه عطبان مختلفان، ولكلٍّ منهما حارسُه أدناه:
//
// ١) الكتابةُ المطلقة (`updateSafeBalance`) بعد قراءةٍ في مسارٍ روتينيّ —
//    سباقُ «التحديث الضائع» تحت عزل PostgreSQL الافتراضيّ (Read-Committed):
//    عمليّتان تقرآن ١٠٠٠ وتكتبان ٩٠٠ و٩٥٠ ⇒ خصمٌ واحدٌ يضيع بلا أثر.
//    البديلُ `adjustSafeBalance` (‏`SET balance = balance + ?`).
//
// ٢) التعديلُ اليدويُّ **قبل** `createSafeTransaction` — وهذا أسوأ: ليس
//    سباقاً بل خطأٌ حتميّ. الدالّةُ تعدّل الرصيدَ بنفسها
//    (‏`treasury_dao.dart:1464-1485`): `receipt`/`deposit` تزيد،
//    و`payment`/`withdrawal` تنقص، و`closing` تصفّر. فمن يكتب الرصيدَ ثم
//    يناديها يطبّق الحركةَ **مرّتين**.
//
//    ومقيسٌ أنه كان يعيش مستوراً: مسارُ المرتجع كان يخصم مرّتين ومسارُ
//    الإلغاء يضيف مرّتين، فالغلطان يتعادلان ما دام الإلغاءُ يتبع المرتجع.
//    إصلاحُ أحدهما وحدَه كان **يُظهر** فرقاً بقيمة المرتجع كاملةً.
//
// اقرأ `treasury_dao.dart:1406-1445` لتوثيق الدالّتين.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ملفاتٌ يُسمح فيها بالكتابة المطلقة، ولكلٍّ سببُه.
const _absoluteWriteAllowedFiles = <String, String>{
  'lib/data/database/database_stub.dart':
      'تجهيزةٌ فارغة للويب — جسمُ الدالّة `{}`',
  'lib/data/database/database_web.dart':
      'تجهيزةٌ فارغة للويب — جسمُ الدالّة `{}`',
  'lib/data/database/supabase_database.dart':
      'مسارُ الويب (kIsWeb) عبر PostgREST — لا يُحمَّل في PicPos سطحِ المكتب، '
          'والحسابُ الذرّيُّ هناك يحتاج RPC على الخادم لا تعديلَ سطر',
  'lib/data/repositories/treasury_repository_impl.dart':
      'تفويضٌ للـDAO — الواجهةُ تكشف الدالّة، والقرارُ عند المنادي',
  'lib/domain/repositories/treasury_repository.dart':
      'تصريحُ الواجهة لا نداء',
};

/// أسطرٌ بعينها يُسمح بها داخل `treasury_dao.dart` — لا الملفُّ كلُّه، وإلا
/// عاد `createReceiptVoucher`/`createPaymentVoucher` يكتبان مطلقاً بلا حارس.
final _treasuryDaoAllowedLines = <RegExp>[
  // التعريفُ نفسُه.
  RegExp(r'Future<void>\s+updateSafeBalance\('),
  // فرعُ `else` في `createSafeTransaction`: أنواعٌ (transfer/adjustment/memo)
  // لا حسابَ ذرّيَّ لها، فالمنادي يمرّر `balanceAfter` صراحةً.
  RegExp(r'updateSafeBalance\(safeId,\s*trans\.balanceAfter\.value\)'),
];

final _absoluteWrite = RegExp(r'\bupdateSafeBalance\(');
final _anyBalanceWrite = RegExp(r'\b(update|adjust)SafeBalance\(');
final _createTxn = RegExp(r'\bcreateSafeTransaction\(');

/// سطرٌ تعليقيٌّ — التوثيقُ يذكر الأسماءَ عمداً.
bool _isComment(String line) {
  final t = line.trimLeft();
  return t.startsWith('//') || t.startsWith('///') || t.startsWith('*');
}

Iterable<File> _libDartFiles() sync* {
  for (final e in Directory('lib').listSync(recursive: true)) {
    if (e is File && e.path.endsWith('.dart')) yield e;
  }
}

String _rel(File f) => f.path.replaceAll(r'\', '/');

void main() {
  test('لا كتابةَ رصيدٍ مطلقةً في مسارٍ نقديٍّ روتينيّ', () {
    final offenders = <String>[];

    for (final file in _libDartFiles()) {
      final rel = _rel(file);
      final allowedFile =
          _absoluteWriteAllowedFiles.keys.any((k) => rel.endsWith(k));
      if (allowedFile) continue;

      final isTreasuryDao = rel.endsWith('lib/data/database/daos/treasury_dao.dart');
      final lines = file.readAsLinesSync();

      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (_isComment(line) || !_absoluteWrite.hasMatch(line)) continue;
        if (isTreasuryDao &&
            _treasuryDaoAllowedLines.any((r) => r.hasMatch(line))) {
          continue;
        }
        offenders.add('$rel:${i + 1}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'استعمل `adjustSafeBalance(safeId, delta)` — حسابٌ على مستوى '
          'SQL مناعتُه من «التحديث الضائع». والكتابةُ المطلقة تبقى مشروعةً '
          'للمصالحة ولتصحيح المحاسب اليدويّ فقط. المواضع:\n  '
          '${offenders.join('\n  ')}',
    );
  });

  test('لا تعديلَ رصيدٍ يدويّاً قبل `createSafeTransaction`', () {
    // الدالّةُ تطبّق الحركةَ بنفسها، فأيُّ تعديلٍ قبلها في نفس الكتلة
    // يطبّقها مرّتين. النافذةُ ١٢ سطراً — تكفي لتغطية حسابِ `newBalance`
    // وقراءةِ الخزنة بينهما بلا أن تعبر إلى كتلةٍ أخرى.
    const window = 12;
    final offenders = <String>[];

    for (final file in _libDartFiles()) {
      final rel = _rel(file);
      // التعريفُ نفسُه ينادي `updateSafeBalance` داخلَه — لا قبلَه.
      if (rel.endsWith('lib/data/database/daos/treasury_dao.dart')) continue;
      // ملفاتُ التصريح والتجهيزات الفارغة: `updateSafeBalance` و
      // `createSafeTransaction` فيها **تصريحان متجاوران** لا نداءان
      // متتاليان، فالجوارُ فيها لا يدلّ على تطبيقٍ مزدوج.
      if (_absoluteWriteAllowedFiles.keys.any((k) => rel.endsWith(k))) continue;

      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (_isComment(lines[i]) || !_createTxn.hasMatch(lines[i])) continue;

        for (var j = i - 1; j >= 0 && j >= i - window; j--) {
          if (_isComment(lines[j])) continue;
          if (_anyBalanceWrite.hasMatch(lines[j])) {
            offenders.add('$rel:${j + 1} → createSafeTransaction عند :${i + 1}');
            break;
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: '`createSafeTransaction` تعدّل الرصيدَ بنفسها بحسب '
          '`transactionType`. احذف التعديلَ اليدويّ وأبقِ `newBalance` '
          'لقطةً لـ`balanceAfter` وحدَها. المواضع:\n  '
          '${offenders.join('\n  ')}',
    );
  });

  test('ضابط: الحارسان يقيسان شيئاً فعلاً', () {
    // بلا هذا الضابط، خطأٌ في المسار أو في التعبير النمطيّ يجعل الحارسَين
    // يمرّان على صفرِ ملفات ويُقرآن خُضرةً.
    final files = _libDartFiles().toList();
    expect(files.length, greaterThan(100),
        reason: 'مسحُ lib/ رجع بلا ملفات — المسارُ غلط');

    final dao = File('lib/data/database/daos/treasury_dao.dart');
    expect(dao.existsSync(), isTrue);
    final src = dao.readAsStringSync();
    expect(_absoluteWrite.hasMatch(src), isTrue,
        reason: 'لو اختفى التعريفُ فالحارسُ الأوّل ما بيقيسش حاجة');
    expect(src.contains('adjustSafeBalance'), isTrue,
        reason: 'البديلُ الذرّيُّ لازم يفضل موجوداً');
  });
}
