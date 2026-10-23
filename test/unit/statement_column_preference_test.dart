// «تخصيص الأعمدة» — تفضيلٌ يُحفَظ لكلّ مستخدم (قرارُ المالك على الصورة `(7)`).
//
// ═══ ما يُقاس هنا ═══
//
// التخزينُ نصٌّ في `settings`، والنصُّ يعود بعد شهورٍ وقد تغيّر الكتالوجُ
// تحته. فالمقيسُ هو **ما يفعله المحلِّل بما لا يتوقّعه**:
//
// ‏• اسمُ عمودٍ لم يعد موجوداً — يُسقَط. و`PicPosDataTable` تؤكّد على تساوي
//   طولِ صفِّ المجاميع وعددِ الأعمدة، فاسمٌ مجهولٌ لم يكن ليُزيح خانةً بل
//   ليُسقط الشاشةَ عند أوّل فتح.
// ‏• نصٌّ فارغٌ أو كلُّه مجهول — `null`، أي «خُذِ الافتراضَ» لا «لا أعمدة».
// ‏• وعمودُ التاريخ يعود **دائماً**: كشفٌ بلا تاريخٍ لا يُقرأ ولا يُرتَّب،
//   وتفضيلٌ قديمٌ أو محرَّرٌ بيدٍ لا يجوز أن يصنعه.
//
// ‏• والمفتاحُ **يحمل معرِّفَ المستخدم**: «لكلّ مستخدم» شرطٌ لا زينة — مفتاحٌ
//   مشتركٌ يجعل تفضيلَ آخرِ من فتح الشاشةَ يحكم الجميعَ على نفس الجهاز.

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/presentation/party_statement_picpos/screens/party_statement_picpos_screen.dart';

void main() {
  group('كتالوجُ الأعمدة', () {
    test('الرموزُ فريدةٌ — رمزان متطابقان يبنيان عمودَين بنفس الخليّة', () {
      final ids = [for (final c in kStatementColumnCatalogue) c.id];
      expect(ids.toSet().length, ids.length);
    });

    test('والافتراضُ داخلَ الكتالوج ويحوي التاريخ', () {
      expect(kDefaultStatementColumns.difference(kStatementColumnIds), isEmpty,
          reason: 'افتراضٌ خارجَ الكتالوج يُبنى عموداً بلا تعريف');
      expect(kDefaultStatementColumns.contains(kStatementColumnDate), isTrue);
    });
  });

  group('قراءةُ المحفوظ', () {
    test('يُقاطَع مع الكتالوج — والمجهولُ يُسقَط', () {
      final got = parseStatementColumnPreference(
          '$kStatementColumnDate,$kStatementColumnDebit,عمودٌ_محذوف');
      expect(got, {kStatementColumnDate, kStatementColumnDebit});
    });

    test('🔴 وعمودُ التاريخ يعود ولو غاب عن المحفوظ', () {
      final got = parseStatementColumnPreference(kStatementColumnBalance);
      expect(got, contains(kStatementColumnDate),
          reason: 'كشفٌ بلا تاريخٍ لا يُقرأ — والمنتقي يمنع إطفاءه، '
              'لكنّ النصَّ المخزَّن قد يسبق ذلك المنع');
      expect(got, contains(kStatementColumnBalance));
    });

    test('والفارغُ والمجهولُ كلُّه يعنيان «خُذِ الافتراض» لا «لا أعمدة»', () {
      expect(parseStatementColumnPreference(null), isNull);
      expect(parseStatementColumnPreference('   '), isNull);
      expect(parseStatementColumnPreference('س,ص,ع'), isNull,
          reason: 'مجموعةٌ فارغةٌ كانت ستُنتج جدولاً بلا عمودٍ واحد');
    });

    test('والمسافاتُ حول الرموز تُقلَّم', () {
      expect(
        parseStatementColumnPreference(
            ' $kStatementColumnDate , $kStatementColumnStatus '),
        {kStatementColumnDate, kStatementColumnStatus},
      );
    });
  });

  group('الكتابةُ والقراءةُ تُغلقان الدائرة', () {
    test('ما يُكتَب يُقرأ كما هو', () {
      const picked = {
        kStatementColumnDate,
        kStatementColumnDesc,
        kStatementColumnBalance,
      };
      expect(
        parseStatementColumnPreference(
            encodeStatementColumnPreference(picked)),
        picked,
      );
    });

    test('🔴 والترتيبُ ترتيبُ الكتالوج لا ترتيبُ الاختيار', () {
      // التفضيلُ يحفظ **أيَّها** لا أيُّها أوّل — وإلّا فرض تفضيلٌ قديمٌ
      // ترتيباً على عمودٍ أُضيف بعده.
      expect(
        encodeStatementColumnPreference(
            {kStatementColumnBalance, kStatementColumnDate}),
        '$kStatementColumnDate,$kStatementColumnBalance',
      );
    });
  });

  group('المفتاحُ لكلّ مستخدم', () {
    test('مستخدمان مفتاحان', () {
      expect(statementColumnPrefKey(7), isNot(statementColumnPrefKey(8)));
    });

    test('والمعرِّفُ داخلَه فعلاً', () {
      expect(statementColumnPrefKey(42), contains('42'));
    });
  });
}
