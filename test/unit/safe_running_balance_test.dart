// ═══════════════════════════════════════════════════════════════════════════
// §٣-ج — «الرصيد بعد» رصيداً جارياً على النافذة المفلترة · الحسابُ الخالص
// ═══════════════════════════════════════════════════════════════════════════
//
// اليوم: التقريرُ يعرض `safe_transactions.balanceAfter` **المخزَّن**، وهو
// لقطةٌ وقتَ الإدراج:
//   · تحت التصفية (مدىً/خزنة) لا يعني شيئاً — أوّلُ صفٍّ معروضٍ يبدأ من رقمٍ
//     لا علاقةَ له بما فوقه، فالعمودُ يقفز بلا تفسير.
//   · وبعد إلغاء حركةٍ سابقة (حذفٌ ناعم) تبقى لقطاتُ ما بعدها على حالها،
//     فتصير كلُّها خاطئةً صامتةً — الأرقامُ موجودةٌ ومعقولةٌ وغلط.
//
// البديل: رصيدٌ افتتاحيٌّ للنافذة، ثم مشيٌ تصاعديٌّ فوقه.
//
// ⚠️ لا قاعدةَ تصريحيةً واحدةً في المشروع تربط `transactionType` بإشارة
// الحركة — كلُّ موضعٍ يمرّر دلتا صريحةً لـ`adjustSafeBalance`. فالقاعدةُ هنا
// مستنبَطةٌ من المواضع، **ومُتحقَّقٌ منها** بثباتٍ في
// `test/integration/treasury_running_balance_test.dart`: المشيُ فوق كلّ
// الحركات يجب أن ينتهي عند `safes.balance` نفسِه. لو أخطأت الإشارةُ لنوعٍ
// واحدٍ سقط ذلك الاختبار.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/safe_running_balance.dart';

void main() {
  group('signedSafeDelta — إشارةُ كلّ نوع', () {
    test('القبضُ يزيد', () {
      expect(signedSafeDelta('receipt', 100), 100.0);
    });

    test('الصرفُ والسحبُ والإقفالُ والخصمُ والسلفةُ تنقص', () {
      for (final t in const [
        'payment',
        'withdrawal',
        'closing',
        'deduction',
        'advance',
      ]) {
        expect(signedSafeDelta(t, 100), -100.0, reason: t);
      }
    });

    test('`memo` لا يحرّك شيئاً — صفرٌ لا سالب', () {
      // موثَّقٌ عند مواضع كتابته: «صفوفُ المذكّرة تتخطّاها استعلاماتُ
      // التجميع بدل أن تحسبها مرّتين». وكان الجدولُ يعرضها «−المبلغ».
      expect(signedSafeDelta('memo', 100), 0.0);
    });

    test('نوعٌ غير معروفٍ يُعامَل صرفاً — الأحوطُ ألّا نضخّم رصيداً', () {
      expect(signedSafeDelta('something_new', 100), -100.0);
    });
  });

  group('runningBalances — المشيُ فوق الرصيد الافتتاحي', () {
    // الصفوفُ تصل من الاستعلام **الأحدثَ أولاً** (`OrderingTerm.desc`)،
    // فالمشيُ يبدأ من آخر القائمة.
    List<SafeMovementRow> rows() => const [
          SafeMovementRow(id: 3, type: 'payment', amount: 30), // الأحدث
          SafeMovementRow(id: 2, type: 'receipt', amount: 50),
          SafeMovementRow(id: 1, type: 'receipt', amount: 20), // الأقدم
        ];

    test('يبدأ من الافتتاحي ويتراكم صعوداً', () {
      final r = runningBalances(rowsNewestFirst: rows(), openingBalance: 100);
      expect(r[1], 120.0); // 100 + 20
      expect(r[2], 170.0); // +50
      expect(r[3], 140.0); // −30
    });

    test('افتتاحيٌّ صفر ⇒ العمودُ يساوي التراكمَ وحدَه', () {
      final r = runningBalances(rowsNewestFirst: rows(), openingBalance: 0);
      expect(r[1], 20.0);
      expect(r[2], 70.0);
      expect(r[3], 40.0);
    });

    test('افتتاحيٌّ سالبٌ يُحترم — السحبُ على المكشوف واقعٌ لا خطأ', () {
      final r = runningBalances(rowsNewestFirst: rows(), openingBalance: -10);
      expect(r[1], 10.0);
      expect(r[3], 30.0);
    });

    test('`memo` بينها لا يغيّر الرصيدَ ولا يكسر التسلسل', () {
      final r = runningBalances(
        rowsNewestFirst: const [
          SafeMovementRow(id: 2, type: 'memo', amount: 999),
          SafeMovementRow(id: 1, type: 'receipt', amount: 20),
        ],
        openingBalance: 100,
      );
      expect(r[1], 120.0);
      expect(r[2], 120.0, reason: 'المذكّرةُ تمرّ بلا أثر');
    });

    test('قائمةٌ فارغة ⇒ خريطةٌ فارغة', () {
      expect(
        runningBalances(rowsNewestFirst: const [], openingBalance: 100),
        isEmpty,
      );
    });

    test('المجموعُ النهائيُّ = الافتتاحيُّ + صافي الحركة', () {
      final r = runningBalances(rowsNewestFirst: rows(), openingBalance: 100);
      // آخرُ رصيدٍ هو رصيدُ الصفّ الأحدث.
      expect(r[3], 100 + 20 + 50 - 30);
    });
  });
}
