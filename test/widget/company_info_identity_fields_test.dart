// «معلومات الشركة» — الاسمُ الإنجليزيُّ والسجلُّ التجاريّ يُعرَضان ويُحفَظان.
//
// معالجُ الإعداد يكتب `company_name_en` و`company_cr_number`، وكانت الشاشةُ
// التي تحرّر بقيّةَ هويّة الشركة لا تعرفهما — فلا سبيلَ لتصحيح خطأٍ في اسمٍ
// أو رقمٍ بعد الإعداد. يُقاس هنا على لوحة PicPos (الأصلُ) والحوارِ الكلاسيكيّ.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/theme/app_theme.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/repositories/settings_repository.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_body_handle.dart';
import 'package:picpos_erp/presentation/widgets/settings/company_info_widget.dart';

class _MemorySettingsRepository implements ISettingsRepository {
  final values = <String, String>{};

  @override
  Future<List<String>> getAvailableBackups() async => [];

  @override
  Future<String?> createBackup() async => null;

  @override
  Future<bool> deleteBackup(String path) async => false;

  @override
  Future<bool> exportBackup(String destinationFolder) async => false;

  @override
  Future<Map<String, dynamic>> getBackupStats() async => {};

  @override
  Future<Map<String, String>> getAllSettings() async => values;

  @override
  Future<String?> getSetting(String key) async => values[key];

  @override
  Future<Map<String, dynamic>> getReceiptSettings() async => {};

  @override
  Future<bool> restoreBackup(String path) async => false;

  @override
  Future<void> saveCompanyInfo({
    required String name,
    String? phone,
    String? address,
    String? taxId,
  }) async {}

  @override
  Future<void> saveReceiptSettings({
    String? companyName,
    String? companyAddress,
    String? companyPhone,
    String? companyPhone2,
    String? companyEmail,
    String? taxNumber,
    String? headerText,
    String? footerText,
    String? termsText,
    dynamic logoImage,
    bool? showLogo,
    bool? showQrCode,
    bool? showBarcode,
    bool? showTaxDetails,
    bool? showItemCode,
    bool? showSalesperson,
    bool? showCustomerInfo,
    int? headerFontSize,
    int? bodyFontSize,
    int? footerFontSize,
    int? paperWidth,
    String? currencySymbol,
  }) async {}

  @override
  Future<void> saveSetting(String key, String value) async {
    values[key] = value;
  }

  @override
  Stream<dynamic> watchReceiptSettings() => const Stream.empty();

  @override
  Stream<String?> watchSettingValue(String key) => Stream.value(values[key]);
}

Future<void> _pump(
  WidgetTester tester,
  _MemorySettingsRepository repo,
  Widget child,
) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [settingsRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  ));
  await tester.pumpAndSettle();
}

/// الحفظُ يُظهر toastًا بمؤقّتٍ — يُترك ينقضي وتُفكّ الشجرةُ قبل نهاية الاختبار.
Future<void> _drainToast(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 10));
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 10));
}

void main() {
  const nameEnKey = Key('company_name_en_field');
  const crKey = Key('company_cr_number_field');

  testWidgets('لوحة PicPos: الحقلان يُعرضان بالقيم المحفوظة ويُحفَظ تعديلُهما',
      (tester) async {
    final repo = _MemorySettingsRepository()
      ..values['company_name'] = 'شركة النور'
      ..values['company_name_en'] = 'Old Name'
      ..values['company_cr_number'] = '111';
    final handle = PicPosBodyHandle();
    addTearDown(handle.dispose);

    await _pump(tester, repo,
        CompanyInfoWidget(picposChrome: true, saveHandle: handle));

    expect(find.byKey(nameEnKey), findsOneWidget);
    expect(find.byKey(crKey), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Old Name'), findsOneWidget,
        reason: 'القيمةُ المحفوظةُ تُعرَض');

    await tester.enterText(find.byKey(nameEnKey), '  Al-Nour Trading Co ');
    await tester.enterText(find.byKey(crKey), '1020304050');
    handle.invoke();
    await tester.pumpAndSettle();

    expect(repo.values['company_name_en'], 'Al-Nour Trading Co',
        reason: 'يُحفَظ مقصوصاً');
    expect(repo.values['company_cr_number'], '1020304050');
    expect(repo.values['company_name'], 'شركة النور',
        reason: 'الاسمُ العربيُّ لم يُمسّ');
    await _drainToast(tester);
  });

  testWidgets('الحوار الكلاسيكيّ: الحقلان يُحفَظان، ومسحُهما يمسح القيمة',
      (tester) async {
    final repo = _MemorySettingsRepository()
      ..values['company_name_en'] = 'Old Name'
      ..values['company_cr_number'] = '111';

    await _pump(tester, repo, const CompanyInfoWidget());

    await tester.enterText(find.byKey(nameEnKey), 'New Name Ltd');
    await tester.enterText(find.byKey(crKey), '');
    await tester.tap(find.byType(ElevatedButton).last);
    await tester.pumpAndSettle();

    expect(repo.values['company_name_en'], 'New Name Ltd');
    expect(repo.values['company_cr_number'], '',
        reason: 'حقلٌ فارغٌ ⇒ لا يُطبع على المستند');
    await _drainToast(tester);
  });
}
