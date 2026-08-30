// إذنُ موافقةِ المسؤول لا يُصرَف في بابٍ غيرِ بابه.
//
// ═══ فئةُ العطب — بلاغُ المراجعة الأمنيّة 2026-08-30 ═══
//
// `requestManagerApproval` تمنح إذناً عمرُه ٦٠ ثانيةً تحت **كود الصلاحية**،
// و`_ensure` تستهلك **أوّلَ** إذنٍ تجده لذلك الكود. ولخصمِ السلّة ثلاثةُ
// أبوابٍ تتقاسم `pos_discount`:
//
//   • خليّةُ «الخصم ٪» في الجدول — ببوّابتَين: لمسةٌ ثمّ إدخال.
//   • حوارُ تعديل السطر (F6) — بوّابةٌ واحدة.
//   • خصمُ الفاتورة — بوّابةٌ واحدة.
//
// فالسيناريو المُستغَلّ: كاشيرٌ بلا `pos_discount` يلمس خليّةَ الخصم، فيأتي
// المديرُ ويصادق على «خصمٍ بسيطٍ على صنفٍ واحد» ⇒ يُمنَح الإذن. ثمّ يُلغي
// الكاشيرُ لوحةَ الأرقام فلا تُنادى بوّابةُ الإدخال ⇒ **الإذنُ يبقى حيّاً**.
// وخلال ٦٠ ثانيةً يفتح خصمَ الفاتورة فيستهلكه ⇒ خصمٌ على الفاتورة كلِّها
// بلا كلمة مرور، والمديرُ لا يعلم أنّ ما صادق عليه أُلغي.
//
// ═══ العلاج المقيس هنا ═══
//
// الإذنُ يُوسَم بالباب. فبوّابتا البابِ الواحد تتشاركانه — وهو الغرضُ
// الأصليُّ من الذاكرة — ولا يعبر إلى بابٍ آخر.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/services/manager_approval_cache.dart';

const _perm = 'pos_discount';

void main() {
  setUp(() => ManagerApprovalCache.instance.clear());
  tearDown(() => ManagerApprovalCache.instance.clear());

  group('نطاقُ إذن المسؤول', () {
    test('المرساة: الإذنُ بلا بابٍ ما زال يعمل كما كان', () {
      // ⚠️ بلا هذه المرساةِ يمرُّ الاختبارُ لو تعطّلت الذاكرةُ كلُّها.
      ManagerApprovalCache.instance.grant(_perm);
      expect(ManagerApprovalCache.instance.consume(_perm), isTrue,
          reason: 'الاستدعاءُ القديمُ بلا باب يجب أن يبقى عاملاً — '
              'سبعةَ عشرَ موضعاً في المستودع لا تمرّر باباً');
      expect(ManagerApprovalCache.instance.consume(_perm), isFalse,
          reason: 'وحيدُ الاستعمال: لا يُصرَف مرّتين');
    });

    test('إذنُ خليّةِ الجدول لا يفتح خصمَ الفاتورة', () {
      // المديرُ صادق عند لمسِ خليّةِ الخصم.
      ManagerApprovalCache.instance.grant(_perm, scope: 'cell_line_discount');

      // الكاشيرُ ألغى لوحةَ الأرقام، ثمّ فتح خصمَ الفاتورة.
      expect(
        ManagerApprovalCache.instance.consume(_perm, scope: 'invoice_discount'),
        isFalse,
        reason: 'إذنُ خصمِ سطرٍ صار خصماً على الفاتورة كلِّها — '
            'وهو بعينُه ما بلّغت عنه المراجعةُ الأمنيّة',
      );
    });

    test('ولا يفتح حوارَ تعديل السطر', () {
      ManagerApprovalCache.instance.grant(_perm, scope: 'cell_line_discount');
      expect(
        ManagerApprovalCache.instance.consume(_perm, scope: 'line_edit_discount'),
        isFalse,
      );
    });

    test('لكنّ بوّابتَي البابِ الواحد تتشاركان إذناً واحداً', () {
      // هذا هو الغرضُ الأصليُّ من الذاكرة: لمسةٌ ثمّ إدخالٌ = فعلٌ واحد،
      // فلا يُسأل المسؤولُ كلمةَ السرِّ مرّتين.
      ManagerApprovalCache.instance.grant(_perm, scope: 'cell_line_discount');
      expect(
        ManagerApprovalCache.instance.consume(_perm, scope: 'cell_line_discount'),
        isTrue,
        reason: 'إن سقط هذا فقد أعدنا عطبَ «كلمةُ مرورٍ مرّتين لفعلٍ واحد»',
      );
    });

    test('وإذنٌ بلا بابٍ لا يُصرَف في بابٍ مسمّى ولا العكس', () {
      ManagerApprovalCache.instance.grant(_perm);
      expect(
        ManagerApprovalCache.instance.consume(_perm, scope: 'invoice_discount'),
        isFalse,
        reason: 'الفصلُ في الاتّجاهين — وإلّا صار تمريرُ بابٍ في أحد '
            'الطرفين وحدَه ثغرةً بدل أن يكون تشديداً',
      );

      ManagerApprovalCache.instance.clear();
      ManagerApprovalCache.instance.grant(_perm, scope: 'invoice_discount');
      expect(ManagerApprovalCache.instance.consume(_perm), isFalse);
    });

    test('وبابُ السعر لا يخلط بباب الخصم', () {
      ManagerApprovalCache.instance
          .grant('pos_price_edit', scope: 'cell_line_price');
      expect(
        ManagerApprovalCache.instance.consume(_perm, scope: 'cell_line_price'),
        isFalse,
        reason: 'الكودُ جزءٌ من المفتاح كما كان — البابُ إضافةٌ لا بديل',
      );
    });
  });
}
