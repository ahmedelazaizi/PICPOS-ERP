// سياسةُ المرفقات — الحسابُ الخالصُ الذي يقرؤه الثلاثة (§٨).
//
// ═══ 🔴 لماذا اختبارُ وحدةٍ لا اختبارُ ودجت ═══
//
// لأنّ هذا النصَّ بعينه يُنفَّذ في **ثلاثة مواضع**: الودجتُ قبل الاختيار،
// والمستودعُ قبل الكتابة، والخادمُ قبل القبول. فاختبارُه في الودجت وحدَه
// يترك الخادمَ بلا برهان، وعميلٌ مُعدَّلٌ يتجاوز الودجتَ أصلاً.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/attachment_policy.dart';

String _ok({
  String entityType = 'purchase_invoice',
  String fileName = 'bill.pdf',
  String mimeType = 'application/pdf',
  int byteSize = 1024,
  int existingCount = 0,
}) =>
    validateAttachment(
      entityType: entityType,
      fileName: fileName,
      mimeType: mimeType,
      byteSize: byteSize,
      existingCount: existingCount,
    ) ??
    '';

void main() {
  group('السقوف — قرارُ المالك §٨٫٤', () {
    test('خمسةُ ميغا لا خمسةٌ وعشرون', () {
      expect(kAttachmentMaxBytes, 5 * 1024 * 1024);
    });

    test('وعشرةُ ملفّاتٍ للمستند', () {
      expect(kAttachmentMaxPerDocument, 10);
    });

    test('🔴 وملفٌّ عند السقف بالضبط يُقبَل — والذي يليه بايتاً يُرفَض', () {
      expect(_ok(byteSize: kAttachmentMaxBytes), '');
      expect(_ok(byteSize: kAttachmentMaxBytes + 1), isNotEmpty);
    });

    test('🔴 والعاشرُ يُقبَل والحاديَ عشرَ يُرفَض', () {
      // ⚠️ الحدُّ على **عدد القائمِ** لا على عدد ما بعد الإضافة: تسعةٌ
      //    قائمةً تقبل عاشراً، وعشرةٌ قائمةً ترفض.
      expect(_ok(existingCount: 9), '');
      expect(_ok(existingCount: 10), isNotEmpty);
    });

    test('وملفٌّ فارغٌ يُرفَض — صفرُ بايتٍ ليس ورقة', () {
      expect(_ok(byteSize: 0), isNotEmpty);
      expect(_ok(byteSize: -1), isNotEmpty);
    });
  });

  group('الأنواع — صورةٌ وPDF فقط', () {
    test('المسموحُ يمرّ', () {
      for (final m in kAttachmentAllowedMimeTypes) {
        expect(_ok(mimeType: m), '', reason: '«$m» مسموحٌ ورُفض');
      }
    });

    test('🔴 والتنفيذيُّ يُرفَض — سطحُ هجومٍ لا ميزة', () {
      for (final m in const [
        'application/x-msdownload',
        'application/octet-stream',
        'text/html',
        'application/zip',
        '',
      ]) {
        expect(_ok(mimeType: m), isNotEmpty, reason: '«$m» مرّ وهو ممنوع');
      }
    });

    test('ولا امتدادَ تنفيذيٍّ في خريطة الاشتقاق', () {
      for (final ext in kAttachmentMimeByExtension.keys) {
        expect(
          const {'exe', 'bat', 'cmd', 'ps1', 'sh', 'dll', 'js', 'msi'}
              .contains(ext),
          isFalse,
          reason: 'امتدادٌ تنفيذيٌّ «$ext» في الخريطة',
        );
      }
      expect(kAttachmentAllowedExtensions, isNotEmpty);
    });

    test('واشتقاقُ النوع من الاسم — والحالةُ لا تهمّ', () {
      expect(attachmentMimeForFileName('a.PDF'), 'application/pdf');
      expect(attachmentMimeForFileName('a.JpG'), 'image/jpeg');
      expect(attachmentMimeForFileName('noext'), isNull);
      expect(attachmentMimeForFileName('trailing.'), isNull);
      expect(attachmentMimeForFileName('a.exe'), isNull);
    });

    test('وتمييزُ الصورة عن الـPDF', () {
      expect(isAttachmentImage('image/png'), isTrue);
      expect(isAttachmentImage('application/pdf'), isFalse);
      expect(isAttachmentPdf('application/pdf'), isTrue);
      expect(isAttachmentPdf('image/png'), isFalse);
    });
  });

  group('المستنداتُ التسعة — §٨٫٤ قرار ٢', () {
    test('تسعةٌ لا أقلّ', () {
      expect(kAttachmentEntities.length, 9);
    });

    test('والمذكورةُ في الخطّة كلُّها موجودة', () {
      for (final t in const [
        'purchase_invoice',
        'import_purchase',
        'purchase_return',
        'sales_invoice',
        'journal_entry',
        'receipt_voucher',
        'payment_voucher',
        'fixed_asset',
        'asset_disposal',
      ]) {
        expect(attachmentEntityFor(t), isNotNull, reason: '«$t» مفقود');
      }
    });

    test('🔴 ولكلٍّ صلاحيةُ كتابةٍ غيرُ صلاحية القراءة — لا صلاحيةَ عامّة',
        () {
      for (final e in kAttachmentEntities) {
        expect(e.viewPermission, isNotEmpty);
        expect(e.attachPermission, isNotEmpty);
        expect(e.tableName, isNotEmpty);
        expect(e.labelAr, isNotEmpty);
        // ولا صلاحيةَ اسمُها «attachments_*» — فتلك تعني بوّابةً واحدةً
        // تفتح أوراقَ اليوميّة لأمين المخزن.
        expect(e.attachPermission.startsWith('attachments'), isFalse);
      }
    });

    test('واسمُ الجدول اسمٌ حقيقيٌّ — صيغةُ snake_case بالجمع', () {
      for (final e in kAttachmentEntities) {
        expect(RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(e.tableName), isTrue,
            reason: '«${e.tableName}» ليس اسمَ جدولٍ صالحاً');
      }
    });

    test('ونوعٌ غيرُ مدعومٍ يُرفَض بلا استثناء', () {
      expect(attachmentEntityFor('stock_movement'), isNull);
      expect(attachmentEntityFor(null), isNull);
      expect(_ok(entityType: 'stock_movement'), isNotEmpty);
    });
  });

  group('رموزُ التصنيف ثابتةٌ لا تُشتقُّ من الاسم', () {
    test('لكلّ عضوٍ رمزٌ ووسمٌ عربيّ', () {
      final codes = <String>{};
      for (final t in AttachmentDocType.values) {
        expect(t.code, isNotEmpty);
        expect(t.labelAr, isNotEmpty);
        expect(codes.add(t.code), isTrue, reason: 'رمزٌ مكرَّر: ${t.code}');
      }
    });

    test('والقراءةُ عكسُ الكتابة — ورمزٌ مجهولٌ يصير «أخرى»', () {
      for (final t in AttachmentDocType.values) {
        expect(AttachmentDocType.fromCode(t.code), t);
      }
      expect(AttachmentDocType.fromCode('nope'), AttachmentDocType.other);
      expect(AttachmentDocType.fromCode(null), AttachmentDocType.other);
    });

    test('🔴 والبيانُ الجمركيُّ وبوليصةُ الشحن موجودان — أوّلُ ما طُلب', () {
      // §٨٫٤ قرار ٢: «والخارجيّةُ أولاها: البيانُ الجمركيُّ وبوليصةُ
      // الشحن ورقٌ بطبيعته».
      expect(AttachmentDocType.fromCode('customs_declaration'),
          AttachmentDocType.customsDeclaration);
      expect(AttachmentDocType.fromCode('bill_of_lading'),
          AttachmentDocType.billOfLading);
    });
  });

  group('تحقّقُ البصمة — كشفُ ما وصل ناقصاً', () {
    const sha =
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

    test('المطابقُ يمرّ، والحالةُ لا تهمّ', () {
      expect(
          validateAttachmentBytes(
            expectedSize: 10,
            expectedSha: sha,
            actualSize: 10,
            actualSha: sha.toUpperCase(),
          ),
          isNull);
    });

    test('🔴 وحجمٌ مختلفٌ يُرفَض ولو طابقت البصمة', () {
      expect(
          validateAttachmentBytes(
            expectedSize: 10,
            expectedSha: sha,
            actualSize: 9,
            actualSha: sha,
          ),
          isNotNull);
    });

    test('🔴 وبصمةٌ مختلفةٌ تُرفَض ولو طابق الحجم', () {
      expect(
          validateAttachmentBytes(
            expectedSize: 10,
            expectedSha: sha,
            actualSize: 10,
            actualSha: sha.replaceRange(0, 1, 'f'),
          ),
          isNotNull);
    });
  });

  group('عرضُ الحجم', () {
    test('ثلاثُ مراتبَ ووحدةٌ عربيّة', () {
      expect(formatAttachmentSize(512), contains('بايت'));
      expect(formatAttachmentSize(2048), contains('ك.ب'));
      expect(formatAttachmentSize(5 * 1024 * 1024), contains('م.ب'));
      expect(formatAttachmentSize(-1), '—');
    });

    test('ورسالةُ السقف تحمل الرقمَ لا عبارةً مبهمة', () {
      final msg = _ok(byteSize: kAttachmentMaxBytes + 1);
      expect(msg, contains('5.0'));
    });
  });
}
