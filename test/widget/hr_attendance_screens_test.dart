// J4 (الجزء ٢) — شاشاتُ الحضور والإجازات والورديّات في PicPos:
//  * اللوحةُ اليوميّة والكشفُ الشهريّ والعطلات، والإجازاتُ بتبويباتها،
//    والورديّاتُ والإسناد — تُرسَم بلا فيضٍ ولا استثناءٍ عند 1366×768 في
//    RTL/LTR × فاتح/غامق؛
//  * «تحضير الكلّ» من الواجهة، والتصحيحُ اليدويُّ بسببٍ إلزاميّ؛
//  * استيرادُ CSV يعرض أسطرَ الخطأ ثمّ يكتب الأيّام؛
//  * الكشفُ الشهريّ يعرض مجاميعه؛
//  * اعتمادُ طلب إجازةٍ من الواجهة، وإسنادُ ورديّةٍ من الواجهة.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/i18n/tr.dart';
import 'package:ural_erp/core/theme/app_theme.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/domain/models/hr_attendance.dart';
import 'package:ural_erp/domain/models/hr_employee_file.dart';
import 'package:ural_erp/domain/models/hr_leave.dart';
import 'package:ural_erp/presentation/hr_picpos/screens/hr_attendance_picpos_screen.dart';
import 'package:ural_erp/presentation/hr_picpos/screens/hr_leave_picpos_screen.dart';
import 'package:ural_erp/presentation/hr_picpos/screens/hr_shifts_picpos_screen.dart';
import 'package:ural_erp/presentation/hr_picpos/widgets/attendance_import_dialog.dart';

void main() {
  late AppDatabase db;
  late int lateId;
  late int freeA;
  late int freeB;
  late int shiftId;
  late int requestId;
  final today = hrDay(DateTime.now());
  DateTime at(int h, int m) => DateTime(today.year, today.month, today.day, h, m);

  Future<void> seed(WidgetTester tester) async {
    db = AppDatabase.forTesting();
    await tester.runAsync(() async {
      await db.getBranches();
      await db.ensureDefaultLeaveTypes();
      final dept = await db.saveHrDepartment(name: 'المبيعات');
      final manager = await db.saveEmployeeProfile(EmployeeProfile(
          name: 'مدير', departmentId: dept, hireDate: DateTime(2020)));
      lateId = await db.saveEmployeeProfile(EmployeeProfile(
          name: 'المتأخر',
          code: 'EMP-L',
          departmentId: dept,
          managerId: manager,
          hireDate: DateTime(2020)));
      freeA = await db.saveEmployeeProfile(EmployeeProfile(
          name: 'بلا بصمة أ', code: 'EMP-A', hireDate: DateTime(2020)));
      freeB = await db.saveEmployeeProfile(EmployeeProfile(
          name: 'بلا بصمة ب', code: 'EMP-B', hireDate: DateTime(2020)));
      shiftId = await db.saveWorkShift(const WorkShift(
          name: 'صباحي',
          nameEn: 'Morning',
          startMinute: 9 * 60,
          endMinute: 17 * 60,
          breakMinutes: 60,
          graceLateMinutes: 10,
          overtimeAfterMinutes: 30));
      await db.saveWorkShift(const WorkShift(
          name: 'ليلي', startMinute: 22 * 60, endMinute: 6 * 60));
      for (final e in [lateId, freeA]) {
        await db.assignShift(
            employeeId: e, shiftId: shiftId, from: DateTime(2020));
      }
      await db.saveAttendanceEntry(
          employeeId: lateId,
          day: today,
          checkIn: at(9, 30),
          checkOut: at(18, 0),
          reason: 'بصمة');
      await db.savePublicHoliday(
          PublicHoliday(date: DateTime(today.year, 12, 25), name: 'عيد'));
      final annual = (await db.listLeaveTypes())
          .firstWhere((t) => t.code == LeaveTypeCode.annual);
      requestId = await db.saveLeaveRequest(
          LeaveRequest(
              employeeId: freeB,
              leaveTypeId: annual.id!,
              startDate: DateTime(today.year, 1, 5),
              endDate: DateTime(today.year, 1, 6),
              reason: 'سفر'),
          submit: true);
    });
    addTearDown(() => tester.runAsync(db.close));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)));
    await tester.pumpAndSettle();
  }

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    Locale locale = const Locale('ar'),
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    if (locale.languageCode == 'en') {
      I18nCatalog.setCatalog(Map<String, String>.from(jsonDecode(
          File('assets/i18n/en.json').readAsStringSync()) as Map));
      I18nCatalog.setLocale(const Locale('en'));
      addTearDown(() => I18nCatalog.setLocale(const Locale('ar', 'EG')));
    }
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        hasPermissionProvider.overrideWith((ref, code) async => true),
        branchScopeProvider
            .overrideWith((ref) async => const BranchScope.fullAccess()),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.lightTheme,
        locale: locale,
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: home,
      ),
    ));
    await settle(tester);
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.tap(f);
    await settle(tester);
  }

  int rows(String prefix) => find
      .byWidgetPredicate((w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith(prefix))
      .evaluate()
      .length;

  for (final locale in const [Locale('ar'), Locale('en')]) {
    for (final dark in [false, true]) {
      final label = '${locale.languageCode}/${dark ? 'dark' : 'light'}';
      // Built inside each test: the theme loads fonts, which needs the binding.
      ThemeData theme() => dark ? AppTheme.darkTheme : AppTheme.lightTheme;

      testWidgets('الحضور: اللوحة والكشف والعطلات بلا فيض — $label',
          (tester) async {
        await seed(tester);
        await pump(tester, const HrAttendancePicPosScreen(),
            locale: locale, theme: theme());
        final dir = Directionality.of(
            tester.element(find.byKey(const Key('att_tab_board'))));
        expect(dir,
            locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr);
        expect(rows('att_row_'), 4);
        expect(find.text(tr('متأخر')), findsWidgets);
        expect(find.text('0:30'), findsWidgets, reason: 'late 30 minutes');
        await tap(tester, find.byKey(const Key('att_tab_month')));
        expect(find.byKey(const Key('att_total_worked')), findsOneWidget);
        expect(find.byKey(Key('att_cal_${today.day}')), findsOneWidget);
        await tap(tester, find.byKey(const Key('att_tab_holidays')));
        expect(find.text(tr('عطلة جديدة')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('الإجازات: الطلبات والأرصدة والأنواع بلا فيض — $label',
          (tester) async {
        await seed(tester);
        await pump(tester, const HrLeavePicPosScreen(),
            locale: locale, theme: theme());
        expect(find.byKey(Key('leave_row_$requestId')), findsOneWidget);
        expect(find.byKey(Key('leave_approve_$requestId')), findsOneWidget);
        await tap(tester, find.byKey(const Key('leave_tab_balances')));
        expect(rows('leave_bal_row_'), 3,
            reason: 'annual, sick and emergency carry an entitlement');
        await tap(tester, find.byKey(const Key('leave_tab_types')));
        expect(rows('leave_type_row_'), 4);
        expect(find.text(tr('إجازة سنوية')), findsWidgets);
        expect(tester.takeException(), isNull);
      });

      testWidgets('الورديات والإسناد بلا فيض — $label', (tester) async {
        await seed(tester);
        await pump(tester, const HrShiftsPicPosScreen(),
            locale: locale, theme: theme());
        expect(rows('shift_row_'), 2);
        expect(find.text('22:00 – 06:00 (+1)'), findsOneWidget,
            reason: 'the night shift crosses midnight');
        await tap(tester, find.byKey(const Key('shifts_tab_assign')));
        expect(rows('assign_row_'), 4);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('«تحضير الكلّ» يسجّل من بلا بصمة، والتصحيحُ يحتاج سبباً',
      (tester) async {
    await seed(tester);
    await pump(tester, const HrAttendancePicPosScreen());
    await tap(tester, find.byKey(const Key('att_mark_all')));
    await tap(tester, find.text('تحضير'));
    await tester.pump(const Duration(seconds: 3));
    await settle(tester);
    for (final e in [freeA, freeB]) {
      final r = await tester.runAsync(() => db.attendanceRecordFor(e, today));
      expect(r, isNotNull, reason: 'employee $e marked present');
      expect(r!.source, AttendanceSource.bulk);
    }
    final a = (await tester.runAsync(() => db.attendanceRecordFor(freeA, today)))!;
    expect(a.checkIn, at(9, 0), reason: 'the shift start');

    await tap(tester, find.byKey(Key('att_edit_$lateId')));
    await tester.enterText(find.byKey(const Key('att_entry_in')), '09:05');
    await tap(tester, find.text('حفظ'));
    expect(find.text('سبب التعديل مطلوب.'), findsOneWidget,
        reason: 'no reason ⇒ refused, the dialog stays');
    await tester.enterText(
        find.byKey(const Key('att_entry_reason')), 'نسي البصمة');
    await tap(tester, find.text('حفظ'));
    final r = (await tester.runAsync(() => db.attendanceRecordFor(lateId, today)))!;
    expect(r.checkIn, at(9, 5));
    expect(r.editReason, 'نسي البصمة');
    expect(tester.takeException(), isNull);
  });

  testWidgets('استيرادُ CSV: أسطرُ الخطأ في المعاينة ثمّ الكتابة', (tester) async {
    await seed(tester);
    final d = '${today.year}-${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    final csv = 'code,time,dir\n'
        'EMP-A,$d 08:58,in\n'
        'EMP-A,$d 17:02,out\n'
        'NOPE,$d 09:00,in\n'
        'EMP-B,bad,in\n';
    await pump(
      tester,
      Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              key: const Key('open_import'),
              onPressed: () => showAttendanceImportDialog(ctx, initialText: csv),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tap(tester, find.byKey(const Key('open_import')));
    await tester.tap(find.byKey(const Key('att_import_direction')));
    await tester.pumpAndSettle();
    await tap(tester, find.text('عمود 3: dir').last);
    await tap(tester, find.text('معاينة'));
    expect(find.byKey(const Key('att_import_error_4')), findsOneWidget);
    expect(find.byKey(const Key('att_import_error_5')), findsOneWidget);
    expect(find.textContaining('كود الموظف غير موجود'), findsOneWidget);
    await tap(tester, find.text('استيراد'));
    await tester.pump(const Duration(seconds: 3));
    await settle(tester);
    final r = (await tester.runAsync(() => db.attendanceRecordFor(freeA, today)))!;
    expect([r.checkIn, r.checkOut], [at(8, 58), at(17, 2)]);
    expect(r.source, AttendanceSource.device);
    expect(tester.takeException(), isNull);
  });

  testWidgets('اعتمادُ طلب إجازةٍ من الواجهة', (tester) async {
    await seed(tester);
    await pump(tester, const HrLeavePicPosScreen());
    await tap(tester, find.byKey(Key('leave_approve_$requestId')));
    await tester.enterText(
        find.byKey(const Key('leave_decision_note')), 'موافق');
    await tap(tester, find.text('تأكيد'));
    await tester.pump(const Duration(seconds: 3));
    await settle(tester);
    final r = (await tester.runAsync(() => db.getLeaveRequest(requestId)))!;
    expect(r.status, LeaveRequestStatus.approved);
    expect(r.decisionNote, 'موافق');
    expect(find.byKey(Key('leave_approve_$requestId')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('إسنادُ ورديّةٍ من الواجهة', (tester) async {
    await seed(tester);
    await pump(tester, const HrShiftsPicPosScreen());
    await tap(tester, find.byKey(const Key('shifts_tab_assign')));
    await tap(tester, find.byKey(Key('assign_btn_$freeB')));
    await tester.tap(find.byKey(const Key('assign_shift')));
    await tester.pumpAndSettle();
    await tap(tester, find.textContaining('ليلي').last);
    await tap(tester, find.text('إسناد').last);
    final current =
        (await tester.runAsync(() => db.currentShiftIds(day: today)))!;
    expect(current[freeB], isNot(shiftId));
    expect(current[freeB], isNotNull);
    expect(tester.takeException(), isNull);
  });
}
