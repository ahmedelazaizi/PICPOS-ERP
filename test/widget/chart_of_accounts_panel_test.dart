// دليلُ الحسابات — **لوحٌ جانبيٌّ يحلّ محلَّ الحوارات** (قرارُ المالك
// 2026-09-18).
//
// ═══ ما يقيسه هذا الملفّ ═══
//
// ‏• أنّ «حساب جديد» و«تعديل» يفتحان **اللوحَ** لا حواراً؛
// ‏• وأنّ حسابَ النظام يقول **لماذا** حقلُه معطَّل — لا حقلاً رماديّاً صامتاً؛
// ‏• وأنّ «طبيعة الحساب» تُعرَض ولا تُحرَّر (مشتقّةٌ من نوع الحساب)؛
// ‏• وأنّ «الحساب الأب» يُحرَّر عند الإنشاء ويُقرأ عند التعديل؛
// ‏• وأنّ اللوحَ **لا يفيض** بجوار الشجرة عند العروض الصغيرة.
//
// ⚠️ **و«ملاحظات ومرفقات» في التصميم لا تُبنى**: لا عمودَ `notes` على
// `accounts` إطلاقاً، والمرفقاتُ مؤجَّلة. وصفٌّ لا يحمل شيئاً أبداً ضجيجٌ.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/repositories/accounting_repository.dart';
import 'package:picpos_erp/presentation/accounting_picpos/chart_of_accounts_detail_panel.dart';
import 'package:picpos_erp/presentation/accounting_picpos/chart_of_accounts_picpos_screen.dart';

class _FakeAccountingRepo implements IAccountingRepository {
  _FakeAccountingRepo(this._accounts);
  final List<Account> _accounts;

  @override
  Stream<List<Account>> watchAllAccounts() => Stream.value(_accounts);

  @override
  Future<List<Account>> getAllAccounts() async => _accounts;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Account _acc({
  required int id,
  required String code,
  required String name,
  required String type,
  int? parentId,
  bool isSystem = false,
  String nature = 'detail',
}) =>
    Account(
      id: id,
      code: code,
      name: name,
      accountType: type,
      accountNature: nature,
      normalBalance: type == 'revenue' ? 'credit' : 'debit',
      level: parentId == null ? 1 : 2,
      parentId: parentId,
      balance: 0,
      isSystem: isSystem,
      isActive: true,
      isHiddenFromEntries: false,
      rowVersion: 1,
    );

void main() {
  final accounts = [
    _acc(id: 1, code: '1000', name: 'الأصول', type: 'asset', nature: 'view'),
    _acc(id: 2, code: '1100', name: 'النقدية', type: 'asset', parentId: 1),
    // ⚠️ جذرٌ لا ابنٌ: أبناءُ الشجرة مطويّون افتراضيّاً (`_expandedAccounts`
    //    فارغة)، فصفُّ الابن غيرُ مرسومٍ أصلاً ولا يُنقَر.
    _acc(
        id: 3,
        code: '1101',
        name: 'الصندوق الرئيسي',
        type: 'asset',
        isSystem: true),
    _acc(id: 4, code: '4100', name: 'المبيعات', type: 'revenue'),
  ];

  Future<List<String>> pump(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 950);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final errors = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (d) => errors.add(d.exceptionAsString());
    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accountingRepositoryProvider
                .overrideWithValue(_FakeAccountingRepo(accounts)),
          ],
          child: const MaterialApp(home: ChartOfAccountsPicPosScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
    } finally {
      FlutterError.onError = previous;
    }
    return errors;
  }

  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  /// يفتح لوحَ الإنشاء من زرّ الترويسة.
  Future<void> openNew(WidgetTester tester) async {
    await tester.tap(find.text('إضافة حساب رئيسي'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
  }

  group('🔴 اللوحُ يحلّ محلَّ الحوارات', () {
    // ⚠️ المرحلة G (البند ١٩): اللوحُ صار **ظاهراً دائماً** بجوار الشجرة،
    //    وقبل الاختيار يرسم حالةً فارغةً مرشدة — لا نموذجاً ولا تفاصيل.
    testWidgets('قبل اختيارِ شيء: حالةٌ فارغةٌ لا نموذج', (tester) async {
      await pump(tester, 1500);
      expect(find.text('تفاصيل الحساب'), findsNothing);
      expect(find.text('حساب جديد'), findsNothing);
      expect(find.byKey(const Key('coa_empty_panel')), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('🔴 و«إضافة حساب رئيسي» يفتح اللوحَ لا حواراً', (tester) async {
      await pump(tester, 1500);
      await openNew(tester);

      expect(find.text('حساب جديد'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing,
          reason: 'حوارٌ يحجب الشجرةَ التي يُحرَّر منها — وهو ما أسقطه القرار');
      // وحقولُ التصميم حاضرة.
      for (final label in [
        'رمز الحساب',
        'اسم الحساب',
        'الحساب الأب',
        'طبيعة الحساب',
        'مستوى الحساب',
        'حالة الحساب',
      ]) {
        expect(find.text(label), findsOneWidget, reason: 'الحقل «$label» غائب');
      }
      expect(find.text('حفظ الحساب'), findsOneWidget);
      expect(find.text('رجوع'), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('و«رجوع» يُغلق اللوحَ', (tester) async {
      await pump(tester, 1500);
      await openNew(tester);
      expect(find.text('حساب جديد'), findsOneWidget);

      await tester.tap(find.text('رجوع'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text('حساب جديد'), findsNothing);
      await teardown(tester);
    });

    testWidgets('🔴 و«ملاحظات ومرفقات» لا تُبنى — لا عمودَ خلفها',
        (tester) async {
      await pump(tester, 1500);
      await openNew(tester);
      expect(find.textContaining('ملاحظات'), findsNothing,
          reason: 'صفٌّ لا يحمل شيئاً أبداً — نفسُ قرار اليومية العامة');
      await teardown(tester);
    });
  });

  group('🔴 وحسابُ النظام يقول لماذا', () {
    testWidgets('السببُ ظاهرٌ وحقلُ الرمز معطَّل', (tester) async {
      await pump(tester, 1500);
      // اختيارُ «الصندوق الرئيسي» — حسابُ نظام. الشجرةُ تُفتَح بالنقر على
      // مجموعة النوع ثمّ على الصفّ.
      await tester.tap(find.text('الصندوق الرئيسي').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      // المرحلة G: الاختيارُ يعرض، و«تعديل» يفتح النموذجَ في اللوح نفسِه.
      await tester.tap(find.byKey(const Key('coa_overview_edit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.textContaining('حسابُ نظام'), findsOneWidget,
          reason: '🔴 الحوارُ القديمُ كان يُعطّل الحقلَ **بلا كلمة**، فيرى '
              'المستخدمُ حقلاً رماديّاً ويظنّ البرنامجَ معطوباً');

      // ⚠️ مقصورٌ على اللوح: حقلُ بحثِ الترويسة `TextField` أيضاً، و
      //    `byType(...).first` كان يقيسه هو لا حقلَ الرمز.
      final codeField = tester.widget<TextField>(
        find
            .descendant(
              of: find.byType(AccountDetailPanel),
              matching: find.byType(TextField),
            )
            .first,
      );
      expect(codeField.enabled, isFalse,
          reason: 'رمزُ حسابِ النظام يُحرَّر — والمحرّكُ يقرؤه بالرمز');
      await teardown(tester);
    });
  });

  group('🔴 وحقلان يُعرضان ولا يُحرَّران — وسببُهما مكتوب', () {
    testWidgets('«طبيعة الحساب» مشتقّةٌ من النوع', (tester) async {
      await pump(tester, 1500);
      await openNew(tester);

      expect(find.textContaining('تُشتقُّ من نوع الحساب'), findsOneWidget,
          reason: 'حقلٌ لا يُحرَّر بلا سببٍ مكتوبٍ يبدو عُطلاً');
      // والافتراضُ أصلٌ ⇒ مدين.
      expect(find.text('مدين'), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('🔴 و«الحساب الأب» يُحرَّر إنشاءً ويُقرأ تعديلاً',
        (tester) async {
      await pump(tester, 1500);
      await openNew(tester);
      // إنشاءً: قائمةٌ منسدلة.
      expect(find.text('— حسابٌ رئيسيّ —'), findsWidgets);

      await tester.tap(find.text('رجوع'));
      await tester.pump();
      await tester.tap(find.text('المبيعات').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tap(find.byKey(const Key('coa_overview_edit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.text('تفاصيل الحساب'), findsOneWidget);
      expect(find.textContaining('النسبُ يُختار عند الإنشاء'), findsOneWidget,
          reason: 'إعادةُ النسب تُعيد حسابَ المستوى لكلّ الذرّيّة — '
              'وحقلٌ يَعِد بها ولا يفعلها أسوأُ من غيابه');
      await teardown(tester);
    });
  });

  group('ومراسي تركيب', () {
    for (final width in [1100.0, 1500.0, 1920.0]) {
      testWidgets('اللوحُ بجوار الشجرة بلا فيضٍ عند ${width.toInt()}',
          (tester) async {
        final errors = await pump(tester, width);
        await openNew(tester);
        expect(errors, isEmpty, reason: 'عطبُ تخطيطٍ عند $width: $errors');
        expect(tester.takeException(), isNull);
        // والشجرةُ لم تُبتَر: مجموعةُ نوعٍ ما زالت تُقرأ.
        expect(find.textContaining('الأصول'), findsWidgets);
        await teardown(tester);
      });
    }
  });
}
