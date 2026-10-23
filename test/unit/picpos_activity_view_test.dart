// نموذجُ عرضِ «سجل العمليات» — صياغةُ نصٍّ خالصة.
//
// ما يُقاس هنا هو ما يكذب صامتاً لو انحرف: المبلغُ الذي كاد يُسقَط لأن
// التصميمَ لا يرسم له عموداً، والحقولُ التي **تغيب بحقّ** (فرعٌ قبل v138،
// دورٌ غيرُ مسنَد) فلا يُكتب مكانها نصٌّ يوهم بمعلومة.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/constants/app_constants.dart';
import 'package:picpos_erp/domain/models/picpos_activity_view.dart';

PicPosActivityRow _row({
  int id = 1,
  String actionLabel = 'بيع',
  String entityLabel = 'فاتورة',
  String detail = 'فاتورة نقدية',
  String userName = 'أحمد',
  DateTime? time,
  String? branchName,
  String? roleName,
  int? entityId,
  double? amount,
}) =>
    PicPosActivityRow(
      id: id,
      actionLabel: actionLabel,
      entityLabel: entityLabel,
      detail: detail,
      userName: userName,
      time: time ?? DateTime(2026, 8, 21, 14, 5),
      branchName: branchName,
      roleName: roleName,
      entityId: entityId,
      amount: amount,
    );

void main() {
  group('التوقيت', () {
    test('الساعةُ بخانتَين دائماً', () {
      expect(_row(time: DateTime(2026, 8, 21, 9, 5)).timeLabel, '09:05');
      expect(_row(time: DateTime(2026, 8, 21, 14, 5)).timeLabel, '14:05');
      expect(_row(time: DateTime(2026, 8, 21, 0, 0)).timeLabel, '00:00');
    });

    test('التاريخُ يوم/شهر بلا حشو', () {
      expect(_row(time: DateTime(2026, 8, 21)).dateLabel, '21/8');
      expect(_row(time: DateTime(2026, 12, 3)).dateLabel, '3/12');
    });
  });

  group('مرجعُ المستند', () {
    test('يُسبَق بـ# حين يوجد معرّف', () {
      expect(_row(entityId: 842).refLabel, '#842');
    });

    // بلا هذا الحارس كان `#null` سيُطبع في عمودٍ ملوّنٍ بلون العلامة.
    test('فارغٌ حين لا معرّفَ — لا «#null»', () {
      expect(_row().refLabel, '');
    });
  });

  group('الفرعُ والدور — يغيبان بحقّ', () {
    test('غيابُ الفرع يعطي سطراً فارغاً لا «غير معروف»', () {
      expect(_row().branchLabel, '');
      expect(_row(branchName: 'فرع العقبة').branchLabel, 'فرع العقبة');
    });

    test('غيابُ الدور يعطي سطراً فارغاً لا «غير معروف»', () {
      expect(_row().roleLabel, '');
      expect(_row(roleName: 'كاشير').roleLabel, 'كاشير');
    });
  });

  group('خليّةُ التفاصيل', () {
    test('بلا مبلغٍ تعرض الوصفَ وحدَه', () {
      expect(_row(detail: 'فاتورة نقدية').detailLabel, 'فاتورة نقدية');
    });

    // ⚠️ الحارسُ الأهمّ: التصميمُ لا يرسم عمودَ مبلغ، والشاشةُ قبل إعادة
    // التصميم كانت تعرضه. إسقاطُه كان سيُخفي رقماً ماليّاً مسجَّلاً.
    test('المبلغُ يُضمّ إلى الوصف ولا يُسقَط', () {
      final label = _row(detail: 'فاتورة نقدية', amount: 250).detailLabel;
      expect(label, contains('فاتورة نقدية'));
      expect(
        label,
        contains((250.0).toStringAsFixed(AppConstants.decimalPlaces)),
      );
      expect(label, contains(AppConstants.currencySymbolEn));
    });

    test('مبلغٌ بلا وصفٍ يظهر وحدَه بلا فاصلٍ معلَّق', () {
      final label = _row(detail: '', amount: 250).detailLabel;
      expect(label.startsWith('·'), isFalse);
      expect(
        label,
        '${(250.0).toStringAsFixed(AppConstants.decimalPlaces)} '
        '${AppConstants.currencySymbolEn}',
      );
    });

    test('مبلغُ صفرٍ يُعرَض ولا يُعامَل كغياب', () {
      expect(_row(amount: 0).detailLabel, contains('0.'));
    });

    test('المبلغُ يستعمل decimalPlaces لا رقماً مكتوباً باليد', () {
      final label = _row(detail: '', amount: 12.5).detailLabel;
      expect(label.split(' ').first.split('.').last.length,
          AppConstants.decimalPlaces);
    });
  });
}
