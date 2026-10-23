// ═══════════════════════════════════════════════════════════════════════════
// نموذجُ إعداد الفاتورة الإلكترونيّة في PicPos — الموضعُ الذي كان غائباً.
// ═══════════════════════════════════════════════════════════════════════════
//
// ═══ فئةُ العطب ═══
//
// `EInvoiceConfigs` كان **لا يُكتَب من PicPos إطلاقاً**: الشاشةُ تعرض التسجيلَ
// والنشاطَ قراءةً فقط. فالميزةُ لا تُفعَّل من داخل المنتج أصلاً — ولا رايةَ
// `einvoice_enabled` تُكتب، فكلُّ جهازٍ يبقى «غيرَ مُفعَّل» ويطبع الرمزَ غيرَ
// الضريبيّ مهما كانت المنشأةُ مسجَّلة.
//
// ═══ والتسييجُ بـ`settings_tax` لا `einvoice_submit` ═══
//
// الإعدادُ يحمل `clientSecret` — اعتمادَ البوّابة. وحملُ السرِّ أخطرُ من
// الإرسال، فلا يُعاد استعمالُ صلاحيّة الإرسال له. و`settings_tax` هي البوّابةُ
// القائمةُ الصحيحةُ دلالةً (تسجيلٌ ضريبيٌّ واعتمادُ بوّابة) — ولا كودَ جديدَ
// يُقحَم في مصفوفةِ الصلاحيّات.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/database/database.dart' as db;
import 'package:picpos_erp/data/providers/auth_providers.dart';
import 'package:picpos_erp/data/providers/repository_providers.dart';
import 'package:picpos_erp/domain/repositories/e_invoice_repository.dart';
import 'package:picpos_erp/presentation/e_invoicing_picpos/screens/e_invoicing_picpos_screen.dart';

/// مستودعٌ مزيَّفٌ يسجّل ما كُتب — فالتوكيدُ على **الكتابة** لا على الشكل.
class _RecordingRepo implements IEInvoiceRepository {
  Map<String, Object?>? saved;

  @override
  Future<int> saveEInvoiceConfig({
    required String platform,
    required String clientId,
    required String clientSecret,
    required String registrationNumber,
    String? activityCode,
    String? branchId,
    String documentVersion = '0.9',
    String codingSystem = 'EGS',
    bool isProduction = false,
    bool isEnabled = false,
  }) async {
    saved = {
      'platform': platform,
      'clientId': clientId,
      'clientSecret': clientSecret,
      'registrationNumber': registrationNumber,
      'activityCode': activityCode,
      'branchId': branchId,
      'documentVersion': documentVersion,
      'codingSystem': codingSystem,
      'isProduction': isProduction,
      'isEnabled': isEnabled,
    };
    return 1;
  }

  @override
  Stream<List<db.EInvoiceSubmissionData>> watchSubmissions({
    String? status,
    String? platform,
  }) =>
      Stream.value(const []);

  @override
  Stream<List<Map<String, dynamic>>> watchSubmissionsWithInvoice() =>
      Stream.value(const []);

  @override
  Future<db.EInvoiceConfigData?> getActiveEInvoiceConfig(String platform) =>
      getEInvoiceConfig(platform);

  @override
  Future<db.EInvoiceConfigData?> getEInvoiceConfig(String platform) async {
    if (platform != 'eta') return null;
    return db.EInvoiceConfigData(
      id: 1,
      platform: 'eta',
      clientId: 'cid',
      clientSecret: 'secret',
      registrationNumber: '344228891',
      activityCode: '4711',
      branchId: '0',
      documentVersion: '1.0',
      codingSystem: 'EGS',
      isProduction: true,
      isEnabled: true,
      createdAt: DateTime(2026, 1, 1),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getStatusAuditTrail(int id) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_RecordingRepo> _pump(
  WidgetTester tester, {
  List<String> perms = const ['einvoice_submit', 'settings_tax'],
}) async {
  final repo = _RecordingRepo();
  tester.view.physicalSize = const Size(1920, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        eInvoiceRepositoryProvider.overrideWithValue(repo),
        currentUserPermissionsProvider.overrideWith((ref) async => perms),
      ],
      child: const MaterialApp(home: EInvoicingPicposScreen()),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump();
  return repo;
}

void main() {
  testWidgets('🔴 زرُّ إعداد المنصّة معروضٌ لمن يملك settings_tax',
      (tester) async {
    await _pump(tester);

    expect(find.byTooltip('إعداد المنصّة'), findsWidgets,
        reason: 'بلا هذا الزرّ لا تُفعَّل الفاتورةُ الإلكترونيّةُ من PicPos '
            'إطلاقاً — ولا تُكتب رايةُ التفعيل');
  });

  testWidgets('🔴 وهو محجوبٌ عمّن لا يملكها — السرُّ لا يُفتح بصلاحيّة إرسال',
      (tester) async {
    await _pump(tester, perms: const ['einvoice_submit', 'einvoice_view']);

    expect(find.byTooltip('إعداد المنصّة'), findsNothing,
        reason: 'صلاحيّةُ الإرسال لا تفتح بابَ اعتماد البوّابة');
  });

  testWidgets('🔴 الحفظُ يكتب ما أُدخل — لا شكلاً بلا أثر', (tester) async {
    final repo = await _pump(tester);

    await tester.tap(find.byTooltip('إعداد المنصّة').first);
    await tester.pumpAndSettle();

    // النموذجُ يفتح بقيم الإعداد القائم — لا فارغاً.
    expect(find.text('344228891'), findsOneWidget,
        reason: 'نموذجٌ يفتح فارغاً يمحو الإعدادَ القائمَ عند أوّل حفظ');

    await tester.enterText(
        find.widgetWithText(TextFormField, 'الرقم الضريبي'), '555666777');
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'حفظ'));
    await tester.pumpAndSettle();

    expect(repo.saved, isNotNull, reason: 'الزرُّ لم يكتب شيئاً');
    expect(repo.saved!['registrationNumber'], '555666777');
    expect(repo.saved!['platform'], 'eta');
    // السرُّ القائمُ لا يُمحى بحفظٍ لم يُغيّره.
    expect(repo.saved!['clientSecret'], 'secret');
  });
}
