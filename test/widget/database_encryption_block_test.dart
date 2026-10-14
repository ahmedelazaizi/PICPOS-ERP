// كتلة «تشفير قاعدة البيانات»: مخفيّةٌ لغير المدير وعلى الويب ومع PostgreSQL؛
// ترقيةٌ يدويّة بفحصٍ مسبق وتأكيدٍ مزدوج وطلبٍ مؤجَّل؛ حوارُ رمز الاسترداد لا
// يُغلق قبل التأكيد؛ تصديرٌ محمول (12 حرفًا)؛ رجوعٌ ما دامت النسخةُ متاحة.
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/i18n/tr.dart';
import 'package:ural_erp/core/theme/app_theme.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/presentation/settings_picpos/widgets/database_encryption_block.dart';
import 'package:ural_erp/services/db_encryption_actions.dart';
import 'package:ural_erp/services/db_key_boot.dart';

class _Fake implements DbEncryptionActions {
  DbEncryptionStatus st =
      const DbEncryptionStatus(state: DbEncryptionState.legacy);
  MigrationSpaceCheck space = const MigrationSpaceCheck(
      dbBytes: 100, requiredBytes: 300, freeBytes: 10000);
  String? code;
  String? exportDir = r'C:\out';
  bool rollbackOk = true;

  final requests = <bool>[];
  final audits = <String>[];
  int cancels = 0;
  int acks = 0;
  int rollbacks = 0;
  final exports = <(String, String)>[];

  @override
  Future<DbEncryptionStatus> status() async => DbEncryptionStatus(
        state: st.state,
        recoveryCodePending: code != null,
        preMigrationUntil: st.preMigrationUntil,
        lastOutcome: st.lastOutcome,
      );

  @override
  Future<MigrationSpaceCheck> preflight() async => space;

  @override
  Future<void> requestMigration({required bool spaceConfirmed}) async {
    requests.add(spaceConfirmed);
    st = const DbEncryptionStatus(state: DbEncryptionState.requested);
  }

  @override
  Future<void> cancelRequest() async {
    cancels++;
    st = const DbEncryptionStatus(state: DbEncryptionState.legacy);
  }

  @override
  Future<String?> pendingRecoveryCode() async => code;

  @override
  Future<void> acknowledgeRecoveryCode() async {
    acks++;
    code = null;
  }

  @override
  Future<String?> pickExportDirectory() async => exportDir;

  @override
  Future<String> exportPortable(
      {required String password, required String directory}) async {
    exports.add((password, directory));
    return '$directory\\x.db';
  }

  @override
  Future<bool> scheduleRollback() async {
    rollbacks++;
    return rollbackOk;
  }

  @override
  Future<void> audit(String action, String description) async =>
      audits.add(action);
}

DbEncryptionStatus _st(DbEncryptionState s, {DateTime? until}) =>
    DbEncryptionStatus(state: s, preMigrationUntil: until);

void main() {
  late _Fake fake;

  setUp(() => fake = _Fake());

  Future<void> pump(
    WidgetTester tester, {
    bool admin = true,
    bool supported = true,
    List<dynamic> extra = const [],
    Size size = const Size(1366, 768),
    Locale locale = const Locale('ar'),
  }) async {
    if (locale.languageCode == 'en') {
      I18nCatalog.setCatalog(Map<String, String>.from(
          jsonDecode(File('assets/i18n/en.json').readAsStringSync()) as Map));
    }
    I18nCatalog.setLocale(locale);
    addTearDown(() => I18nCatalog.setLocale(const Locale('ar', 'EG')));
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserPermissionsProvider.overrideWith(
            (ref) async => admin ? ['system_admin'] : ['pos_access']),
        dbEncryptionActionsProvider.overrideWithValue(fake),
        if (extra.isEmpty) dbEncryptionSupportedProvider.overrideWithValue(supported),
        ...extra.cast(),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        locale: locale,
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: DatabaseEncryptionBlock(onPrintCode: (_) async {}),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Finder rowButton(String key) => find.descendant(
      of: find.byKey(Key(key)), matching: find.byType(OutlinedButton));
  Finder block() => find.byKey(const Key('ld_db_encryption'));

  group('الظهور', () {
    testWidgets('يظهر للمدير', (tester) async {
      await pump(tester);
      expect(block(), findsOneWidget);
      expect(find.byKey(const Key('dbenc_status')), findsOneWidget);
    });

    testWidgets('مخفيّ لغير المدير', (tester) async {
      await pump(tester, admin: false);
      expect(block(), findsNothing);
    });

    testWidgets('مخفيّ على الويب (غير مدعوم)', (tester) async {
      await pump(tester, supported: false);
      expect(block(), findsNothing);
    });

    testWidgets('مخفيّ مع PostgreSQL المتصل، ظاهر مع SQLite', (tester) async {
      final pg = AppDatabase.withExecutor(NativeDatabase.memory(),
          isPostgres: true);
      await pump(tester, extra: [databaseProvider.overrideWithValue(pg)]);
      expect(block(), findsNothing);

      final sqlite = AppDatabase.forTesting();
      await pump(tester, extra: [databaseProvider.overrideWithValue(sqlite)]);
      expect(block(), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('الحالة والأزرار', () {
    testWidgets('مشتق من الجهاز ⇒ زر الترقية فقط (بلا تصدير ولا رجوع)',
        (tester) async {
      fake.st = _st(DbEncryptionState.legacy);
      await pump(tester);
      expect(find.byKey(const Key('dbenc_upgrade_row')), findsOneWidget);
      expect(find.byKey(const Key('dbenc_export_row')), findsNothing);
      expect(find.byKey(const Key('dbenc_rollback_row')), findsNothing);
      expect(find.text('مشتق من الجهاز'), findsOneWidget);
    });

    testWidgets('مرحَّل ⇒ تصدير محمول، والرجوع ما دامت النسخة متاحة',
        (tester) async {
      fake.st = _st(DbEncryptionState.migrated,
          until: DateTime.now().add(const Duration(days: 20)));
      await pump(tester);
      expect(find.byKey(const Key('dbenc_upgrade_row')), findsNothing);
      expect(find.byKey(const Key('dbenc_export_row')), findsOneWidget);
      expect(find.byKey(const Key('dbenc_rollback_row')), findsOneWidget);
      expect(find.text('مفتاح عشوائي'), findsOneWidget);
    });

    testWidgets('مرحَّل بعد انقضاء 30 يومًا ⇒ لا رجوع', (tester) async {
      fake.st = _st(DbEncryptionState.migrated);
      await pump(tester);
      expect(find.byKey(const Key('dbenc_rollback_row')), findsNothing);
    });

    testWidgets('بانتظار تأكيد وبانتظار إعادة التشغيل', (tester) async {
      fake.st = _st(DbEncryptionState.pendingConfirm);
      await pump(tester);
      expect(find.text('بانتظار تأكيد'), findsOneWidget);
      fake.st = _st(DbEncryptionState.requested);
      await tester.pumpWidget(const SizedBox.shrink());
      await pump(tester);
      expect(find.text('بانتظار إعادة التشغيل'), findsOneWidget);
      expect(find.byKey(const Key('dbenc_cancel_row')), findsOneWidget);
      expect(find.byKey(const Key('dbenc_upgrade_row')), findsNothing);
    });

    testWidgets('غير متاح', (tester) async {
      fake.st = _st(DbEncryptionState.unavailable);
      await pump(tester);
      expect(find.text('غير متاح'), findsOneWidget);
    });

    testWidgets('نتيجةُ آخر طلبٍ متخطَّى تظهر', (tester) async {
      fake.st = const DbEncryptionStatus(
        state: DbEncryptionState.legacy,
        lastOutcome: DbKeyBootOutcome(
            DbKeyBootOutcomeKind.skipped, 'insufficient free space'),
      );
      await pump(tester);
      expect(find.byKey(const Key('dbenc_outcome')), findsOneWidget);
      expect(find.textContaining('insufficient free space'), findsOneWidget);
    });
  });

  group('الترقية اليدوية', () {
    Future<void> open(WidgetTester tester) async {
      await tester.ensureVisible(rowButton('dbenc_upgrade_row'));
      await tester.tap(rowButton('dbenc_upgrade_row'));
      await tester.pumpAndSettle();
    }

    Finder submit() => find.widgetWithText(ElevatedButton, 'سجّل الطلب');

    testWidgets('لا طلب قبل كتابة الكلمة، ثم يُسجَّل طلبٌ مؤجَّل لا ترحيلٌ فوريّ',
        (tester) async {
      await pump(tester);
      await open(tester);
      expect(find.byKey(const Key('dbenc_space_result')), findsOneWidget);
      expect(tester.widget<ElevatedButton>(submit()).onPressed, isNull);

      await tester.enterText(
          find.byKey(const Key('dbenc_upgrade_confirm_field')), 'خطأ');
      await tester.pump();
      expect(tester.widget<ElevatedButton>(submit()).onPressed, isNull);

      await tester.enterText(
          find.byKey(const Key('dbenc_upgrade_confirm_field')), 'ترقية');
      await tester.pump();
      expect(tester.widget<ElevatedButton>(submit()).onPressed, isNotNull);
      expect(fake.requests, isEmpty, reason: 'الكتابة وحدها لا تسجّل');

      await tester.tap(submit());
      await tester.pumpAndSettle();
      expect(fake.requests, [false]);
      expect(fake.audits, ['db_encryption_upgrade_requested']);
      expect(find.text('بانتظار إعادة التشغيل'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('إلغاء الحوار لا يسجّل شيئًا', (tester) async {
      await pump(tester);
      await open(tester);
      await tester.tap(find.text('إلغاء').last);
      await tester.pumpAndSettle();
      expect(fake.requests, isEmpty);
      expect(fake.audits, isEmpty);
    });

    testWidgets('مساحةٌ غير كافية ⇒ لا تسجيل ولو كُتبت الكلمة', (tester) async {
      fake.space = const MigrationSpaceCheck(
          dbBytes: 1000, requiredBytes: 3000, freeBytes: 2999);
      await pump(tester);
      await open(tester);
      await tester.enterText(
          find.byKey(const Key('dbenc_upgrade_confirm_field')), 'ترقية');
      await tester.pump();
      expect(tester.widget<ElevatedButton>(submit()).onPressed, isNull);
    });

    testWidgets('مساحةٌ غير معروفة ⇒ تأكيدٌ صريح من المدير ويُسجَّل', (tester) async {
      fake.space = const MigrationSpaceCheck(dbBytes: 1000, requiredBytes: 3000);
      await pump(tester);
      await open(tester);
      expect(find.byKey(const Key('dbenc_space_unknown')), findsOneWidget);
      await tester.enterText(
          find.byKey(const Key('dbenc_upgrade_confirm_field')), 'ترقية');
      await tester.pump();
      expect(tester.widget<ElevatedButton>(submit()).onPressed, isNull,
          reason: 'الكلمة وحدها لا تكفي مع مساحةٍ مجهولة');
      await tester.tap(find.byKey(const Key('dbenc_space_confirm')));
      await tester.pump();
      await tester.tap(submit());
      await tester.pumpAndSettle();
      expect(fake.requests, [true]);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('إلغاء طلبٍ مسجَّل', (tester) async {
      fake.st = _st(DbEncryptionState.requested);
      await pump(tester);
      await tester.ensureVisible(rowButton('dbenc_cancel_row'));
      await tester.tap(rowButton('dbenc_cancel_row'));
      await tester.pumpAndSettle();
      expect(fake.cancels, 1);
      expect(find.byKey(const Key('dbenc_upgrade_row')), findsOneWidget);
    });
  });

  group('رمز الاسترداد', () {
    testWidgets('يظهر مرة واحدة ولا يُغلق قبل التأكيد، ثم يُحذف بعده',
        (tester) async {
      fake.code = 'ABCD-EFGH-IJKL-MNOP';
      fake.st = _st(DbEncryptionState.pendingConfirm);
      await pump(tester);
      expect(find.byKey(const Key('dbenc_code_dialog')), findsOneWidget);
      expect(find.text('ABCD-EFGH-IJKL-MNOP'), findsOneWidget);

      // لا يُغلق بالنقر خارجه ولا بـ Escape.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('dbenc_code_dialog')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('dbenc_code_dialog')), findsOneWidget);

      // زر «تم» معطَّل حتى يُؤكَّد المربع.
      final done = find.byKey(const Key('dbenc_code_done'));
      expect(tester.widget<FilledButton>(done).onPressed, isNull);
      expect(fake.acks, 0);

      await tester.tap(find.byKey(const Key('dbenc_code_copy')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('dbenc_code_print')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('dbenc_code_saved')));
      await tester.pump();
      expect(tester.widget<FilledButton>(done).onPressed, isNotNull);
      await tester.tap(done);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('dbenc_code_dialog')), findsNothing);
      expect(fake.acks, 1);
      expect(fake.code, isNull, reason: 'لا يبقى الرمز بعد التأكيد');
      expect(fake.audits, contains('db_recovery_code_acknowledged'));
      expect(find.byKey(const Key('dbenc_code_pending')), findsNothing);
    });

    testWidgets('لا حوار إن لم يكن ثمّة رمزٌ معلَّق', (tester) async {
      await pump(tester);
      expect(find.byKey(const Key('dbenc_code_dialog')), findsNothing);
    });

    testWidgets('لغير المدير لا يظهر الرمز', (tester) async {
      fake.code = 'SECRET-CODE';
      await pump(tester, admin: false);
      expect(find.text('SECRET-CODE'), findsNothing);
      expect(fake.acks, 0);
    });
  });

  group('التصدير المحمول والرجوع', () {
    testWidgets('كلمة المرور 12 حرفًا على الأقل وتطابقها', (tester) async {
      fake.st = _st(DbEncryptionState.migrated);
      await pump(tester);
      await tester.ensureVisible(find.byKey(const Key('dbenc_export_row')));
      await tester.tap(find.byKey(const Key('dbenc_export_row')));
      await tester.pumpAndSettle();
      final go = find.widgetWithText(ElevatedButton, 'اختيار المجلد وتصدير');
      expect(tester.widget<ElevatedButton>(go).onPressed, isNull);

      await tester.enterText(find.byKey(const Key('dbenc_export_pw')), 'short-pw1');
      await tester.enterText(find.byKey(const Key('dbenc_export_pw2')), 'short-pw1');
      await tester.pump();
      expect(tester.widget<ElevatedButton>(go).onPressed, isNull);

      await tester.enterText(find.byKey(const Key('dbenc_export_pw')), '0123456789ab');
      await tester.enterText(find.byKey(const Key('dbenc_export_pw2')), '0123456789ac');
      await tester.pump();
      expect(tester.widget<ElevatedButton>(go).onPressed, isNull);

      await tester.enterText(find.byKey(const Key('dbenc_export_pw2')), '0123456789ab');
      await tester.pump();
      expect(tester.widget<ElevatedButton>(go).onPressed, isNotNull);
      await tester.tap(go);
      await tester.pumpAndSettle();
      expect(fake.exports, [('0123456789ab', r'C:\out')]);
      expect(fake.audits, ['db_portable_export']);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('إلغاء اختيار المجلد لا يصدّر', (tester) async {
      fake.st = _st(DbEncryptionState.migrated);
      fake.exportDir = null;
      await pump(tester);
      await tester.ensureVisible(find.byKey(const Key('dbenc_export_row')));
      await tester.tap(find.byKey(const Key('dbenc_export_row')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('dbenc_export_pw')), '0123456789ab');
      await tester.enterText(find.byKey(const Key('dbenc_export_pw2')), '0123456789ab');
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'اختيار المجلد وتصدير'));
      await tester.pumpAndSettle();
      expect(fake.exports, isEmpty);
    });

    testWidgets('الرجوع يطلب تأكيدًا ثم يجدول', (tester) async {
      fake.st = _st(DbEncryptionState.migrated,
          until: DateTime.now().add(const Duration(days: 5)));
      await pump(tester);
      await tester.ensureVisible(rowButton('dbenc_rollback_row'));
      await tester.tap(rowButton('dbenc_rollback_row'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('إلغاء').last);
      await tester.pumpAndSettle();
      expect(fake.rollbacks, 0);

      await tester.tap(rowButton('dbenc_rollback_row'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('جدولة الرجوع').last);
      await tester.pumpAndSettle();
      expect(fake.rollbacks, 1);
      expect(fake.audits, ['db_encryption_rollback_scheduled']);
      await tester.pump(const Duration(seconds: 6));
    });
  });

  group('الأحجام واللغات', () {
    for (final size in const [Size(1366, 768), Size(1024, 768)]) {
      for (final locale in const [Locale('ar'), Locale('en')]) {
        for (final state in DbEncryptionState.values) {
          testWidgets(
              '${state.name} ${locale.languageCode} ${size.width.toInt()}×${size.height.toInt()}',
              (tester) async {
            fake.st = _st(state,
                until: DateTime.now().add(const Duration(days: 9)));
            fake.code = state == DbEncryptionState.pendingConfirm
                ? 'ABCD-EFGH-IJKL-MNOP-QRST-UVWX'
                : null;
            await pump(tester, size: size, locale: locale);
            expect(tester.takeException(), isNull);
            if (fake.code != null) {
              expect(find.byKey(const Key('dbenc_code_dialog')), findsOneWidget);
              expect(tester.takeException(), isNull);
            }
          });
        }
      }
    }
  });
}
