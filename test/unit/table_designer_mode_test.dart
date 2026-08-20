// المهمّة ٦-ب — قواعدُ وضع التصميم الخالصة.
//
// دالّتان خالصتان بلا ودجت ولا Provider، فتُقاسان بلا فتح شاشة:
// - `showDesignerModeToggle`: هل يظهر زرُّ «تصميم» في الترويسة؟ لا معنى
//   لترتيب مخطَّطٍ في وضع الشبكة.
// - `designerModeAfterViewToggle`: مغادرةُ الخريطة تُطفئ وضعَ التصميم دائماً
//   — وإلّا عاد المستخدمُ إلى الخريطة فوجد نفسَه في وضعِ تحريرٍ لا يذكر أنه
//   فتحه (البند ٥ في `task-6b-brief.md`).
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/table_designer_mode.dart';

void main() {
  group('showDesignerModeToggle', () {
    test('يظهر في وضع الخريطة', () {
      expect(showDesignerModeToggle(isVisualView: true), isTrue);
    });

    test('يغيب في وضع الشبكة', () {
      expect(showDesignerModeToggle(isVisualView: false), isFalse);
    });
  });

  group('designerModeAfterViewToggle', () {
    test('مغادرةُ الخريطة (كانت مرئيّة) تُطفئ وضعَ التصميم', () {
      expect(
        designerModeAfterViewToggle(
          wasVisualView: true,
          wasDesignerMode: true,
        ),
        isFalse,
      );
    });

    test('مغادرةُ الخريطة وهي أصلاً غيرُ مفعّلةٍ تبقى مُطفأة', () {
      expect(
        designerModeAfterViewToggle(
          wasVisualView: true,
          wasDesignerMode: false,
        ),
        isFalse,
      );
    });

    test('الدخولُ إلى الخريطة (من الشبكة) لا يُشعل وضعَ التصميم من تلقاء نفسه',
        () {
      expect(
        designerModeAfterViewToggle(
          wasVisualView: false,
          wasDesignerMode: false,
        ),
        isFalse,
      );
    });
  });
}
