// اللوحُ مُركَّبٌ حيث يُعرَض مستندٌ محفوظ — **والباقي موسومٌ بسببه**.
//
// ═══ 🔴 لماذا حارسٌ بنيويٌّ لهذا ═══
//
// §٨٫٤ قرار ٢ يسمّي **تسعةَ** مستنداتٍ تقبل مرفقاً. والقياسُ عند التنفيذ
// (2026-09-20) وجد أنّ أربعةً منها بلا **شاشةِ عرضٍ لمستندٍ محفوظ**:
// سندُ القبض وسندُ الصرف وسندُ القيد ومردودُ المشتريات — كلُّها
// استماراتُ إنشاءٍ تُغلَق بالحفظ. واللوحُ يشترط رقمَ المستند وهُويّتَه،
// فلا يقول فيها غيرَ «احفظ أوّلاً».
//
// ⚠️ **وخطرُ ذلك أن يُنسى**: «سنركّبها يومَ توجد شاشةُ عرض» جملةٌ لا
// تُنفِّذ نفسَها — وهذا المستودعُ يحمل سوابقَ مقيسةً لبنيةٍ شُحنت بلا
// مُنادٍ (رايةُ `table_bill_guest_order_enabled` · `InvoiceCurrencySelector`
// · `Payments` و`PaymentAllocations`). فالحارسُ يشترط **وسماً مكتوباً
// يذكر السبب** في كلِّ واحدٍ من الأربعة: أوّلُ من يحذف الوسمَ بلا تركيبٍ
// يُسقط البناء.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String p) => File(p).readAsStringSync();

/// نصٌّ بلا أسطر التعليق — فذكرُ اسم اللوح في شرحٍ ليس تركيباً.
String _code(String raw) => [
      for (final line in raw.split('\n'))
        if (!line.trimLeft().startsWith('//')) line,
    ].join('\n');

/// الستُّ التي تُركَّب فيها فعلاً: المِلفُّ ونوعُ المستند.
const _mounted = <String, String>{
  'lib/presentation/purchases_picpos/screens/purchases_picpos_details.dart':
      'purchase_invoice',
  'lib/presentation/sales_invoices_picpos/screens/sales_invoice_dialogs.dart':
      'sales_invoice',
  'lib/presentation/accounting_picpos/journal_entries_picpos_screen.dart':
      'journal_entry',
  'lib/presentation/import_purchases_picpos/screens/import_purchases_picpos_screen.dart':
      'import_purchase',
  'lib/presentation/fixed_assets_picpos/screens/asset_card_picpos.dart':
      'fixed_asset',
  'lib/presentation/fixed_assets_picpos/screens/asset_disposal_request_picpos.dart':
      'asset_disposal',
};

/// والأربعُ الموسومةُ بسببها.
const _marked = <String, String>{
  'lib/presentation/treasury_picpos/screens/voucher_form_picpos.dart':
      'سندا القبض والصرف',
  'lib/presentation/accounting_picpos/journal_voucher_picpos_screen.dart':
      'سند القيد',
  'lib/presentation/purchase_returns_picpos/screens/purchase_returns_picpos_screen.dart':
      'مردود المشتريات',
  'lib/presentation/accounting_picpos/chart_of_accounts_detail_panel.dart':
      'دليل الحسابات (خارجَ التسعة)',
};

void main() {
  group('حراسةُ الحارس', () {
    test('الملفّاتُ العشرةُ موجودةٌ وغيرُ فارغة', () {
      for (final p in [..._mounted.keys, ..._marked.keys]) {
        final f = File(p);
        expect(f.existsSync(), isTrue, reason: 'الملفُّ «$p» غيرُ موجود');
        expect(f.readAsStringSync().length, greaterThan(500));
      }
    });

    test('ونزعُ التعليقات يبقي الكود — على البلاغ نفسِه', () {
      const sample = '  // PicPosAttachmentsPanel مذكورٌ شرحاً\n'
          '  PicPosAttachmentsPanel(';
      expect('PicPosAttachmentsPanel('.allMatches(_code(sample)).length, 1,
          reason: 'ذكرٌ في تعليقٍ يُعَدُّ تركيباً ⇒ الحارسُ يكذب في الاتّجاه '
              'الخطر.');
    });

    test('واللوحُ نفسُه موجودٌ ويشترط النوعَ والرقم', () {
      final panel = _read(
          'lib/presentation/picpos_shell/picpos_attachments_panel.dart');
      expect(panel, contains('class PicPosAttachmentsPanel'));
      expect(panel, contains('required this.entityType'));
      expect(panel, contains('required this.entityId'));
    });
  });

  test('🔴 الستُّ مُركَّبةٌ فعلاً — بالنوع الصحيح', () {
    final missing = <String>[];
    _mounted.forEach((path, type) {
      final code = _code(_read(path));
      if (!code.contains('PicPosAttachmentsPanel(')) {
        missing.add('$path — لا لوحَ أصلاً');
      } else if (!code.contains("entityType: '$type'")) {
        missing.add('$path — اللوحُ هناك بنوعٍ غير «$type»');
      }
    });
    expect(missing, isEmpty,
        reason: 'شاشةٌ تعرض مستنداً محفوظاً بلا لوحِ مرفقاتٍ:\n'
            '  ${missing.join('\n  ')}');
  });

  test('🔴 والأربعُ موسومةٌ بسببها — لا صمت', () {
    final silent = <String>[];
    _marked.forEach((path, label) {
      final raw = _read(path);
      // الوسمُ يُقرأ من **التعليقات** لا من الكود: هو شرحٌ بطبيعته.
      final says = raw.contains('v176') && raw.contains('المرفقات');
      if (!says) silent.add('$path ($label)');
    });
    expect(silent, isEmpty,
        reason: 'موضعٌ لم يُركَّب فيه اللوحُ ولا يقول لماذا — والقارئُ بعد '
            'شهرٍ يظنُّه سهواً فيركّبه على استمارةِ إنشاءٍ لا مستندَ فيها:\n'
            '  ${silent.join('\n  ')}');
  });

  test('ولا موضعَ يقول «لا بنيةَ مرفقاتٍ» بعد أن بُنيت', () {
    final stale = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final s = f.readAsStringSync();
      if (s.contains('لا بنيةَ مرفقاتٍ') ||
          s.contains('المرفقاتُ مؤجَّلةٌ إلى خطّتها')) {
        stale.add(f.path);
      }
    }
    expect(stale, isEmpty,
        reason: 'تعليقٌ يقول إنّ المرفقاتِ غيرُ مبنيّةٍ وقد بُنيت في v176 — '
            'وهو يوجّه القارئَ إلى بناءٍ ثانٍ:\n  ${stale.join('\n  ')}');
  });

  test('🔴 وكلُّ اختبارٍ يرسم شاشةً حاملةً يُجاوز المستودع', () {
    // الودجتاتُ التي **يُرسَم لوحُها في أوّل إطار** بلا تفاعل.
    //
    // ⚠️ والمبنيّاتُ على حوارٍ (المشتريات · المبيعات · اليومية · حوارُ
    //    أوراق الاستيراد) خارجَ هذا الشرط: لوحُها لا يُبنى إلّا بعد فتح
    //    الحوار. فمن يفتحه في اختبارٍ **يحتاج التجاوزَ أيضاً** — وقد وقع
    //    فعلاً في `import_purchases_screen_composition_test`.
    const alwaysRendered = <String>[
      'AssetCardPicpos(',
      'AssetDisposalRequestForm(',
      'FixedAssetsPicposScreen(',
    ];
    final offenders = <String>[];
    for (final f in Directory('test/widget').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final code = _code(f.readAsStringSync());
      if (!alwaysRendered.any(code.contains)) continue;
      if (!code.contains('attachmentsRepositoryProvider')) {
        offenders.add(f.path.replaceAll(r'\', '/'));
      }
    }
    expect(offenders, isEmpty,
        reason: 'اختبارٌ يرسم شاشةً تحمل لوحَ مرفقاتٍ بلا تجاوزِ المستودع '
            '⇒ `databaseProvider` يفتح قاعدةً حقيقيّةً ولا يستقرّ '
            '`pumpAndSettle` — والبلاغُ يقول «timed out» ولا يذكر '
            'المرفقاتِ بكلمة.\n'
            'والعلاجُ سطرٌ: '
            '`attachmentsRepositoryProvider.overrideWithValue('
            'fakeAttachmentsRepo())`\n'
            '  ${offenders.join('\n  ')}');
  });

  test('والأنواعُ المُركَّبةُ كلُّها معرَّفةٌ في السياسة', () {
    final policy = _read('lib/domain/models/attachment_policy.dart');
    for (final type in _mounted.values) {
      expect(policy, contains("type: '$type'"),
          reason: 'الشاشةُ تمرّر «$type» ولا وجودَ له في '
              '`kAttachmentEntities` ⇒ اللوحُ يعرض «نوعٌ غيرُ مدعوم».');
    }
  });
}
