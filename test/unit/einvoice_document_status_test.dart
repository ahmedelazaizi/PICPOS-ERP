// ═══════════════════════════════════════════════════════════════════════════
// ترجمةُ حكم البوّابة إلى حالةٍ نخزّنها — والمجهولُ ليس حكماً.
// ═══════════════════════════════════════════════════════════════════════════
//
// البوّابةُ تردّ نصّاً حرّاً (`Valid` · `Invalid` · `Rejected` · `Submitted`…)
// بحروفٍ تختلف. والمخزَّنُ عندنا اصطلاحٌ ثابت.
//
// ⚠️ **وأخطرُ الحالات المجهولة**: حالةٌ لا نعرفها — صيغةٌ جديدةٌ من البوّابة،
// أو ردٌّ مشوّه — يجب أن تُترك **بلا تغيير** فيُعاد استطلاعُها. وترجمتُها إلى
// حكمٍ نهائيٍّ تُجمّد المستندَ عند حالةٍ خاطئة: إمّا رمزٌ ضريبيٌّ يُطبع على
// مستندٍ لم يُعتمد، وإمّا مستندٌ معتمَدٌ يُوسَم مرفوضاً فلا يُطبع رمزُه أبداً.

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/models/einvoice_document_status.dart';

void main() {
  test('الاعتمادُ بأيّ صيغة', () {
    expect(canonicalEInvoiceStatus('Valid'), 'valid');
    expect(canonicalEInvoiceStatus('valid'), 'valid');
    expect(canonicalEInvoiceStatus('VALID'), 'valid');
    expect(canonicalEInvoiceStatus('Accepted'), 'valid');
    expect(canonicalEInvoiceStatus('  Valid  '), 'valid');
  });

  test('الرفضُ يُميَّز عن عدم الصحّة', () {
    expect(canonicalEInvoiceStatus('Rejected'), 'rejected');
    expect(canonicalEInvoiceStatus('Invalid'), 'invalid');
  });

  test('والإلغاء', () {
    expect(canonicalEInvoiceStatus('Cancelled'), 'cancelled');
    expect(canonicalEInvoiceStatus('Canceled'), 'cancelled');
  });

  test('ما زال ينتظر ⇒ لا تغيير', () {
    expect(canonicalEInvoiceStatus('Submitted'), isNull);
    expect(canonicalEInvoiceStatus('Pending'), isNull);
    expect(canonicalEInvoiceStatus('InProgress'), isNull);
  });

  // 🔴 البندُ الذي كُتب الملفُّ من أجله.
  test('🔴 المجهولُ يُترك بلا تغيير — لا يُجمَّد على حكمٍ لم يصدر', () {
    for (final raw in ['', '   ', 'SomethingNew', '???', 'خطأ']) {
      expect(canonicalEInvoiceStatus(raw), isNull,
          reason: 'ترجمةُ «$raw» إلى حكمٍ نهائيٍّ تُجمّد المستندَ خطأً — '
              'إمّا رمزٌ ضريبيٌّ على غيرِ معتمَد، وإمّا معتمَدٌ لا يُطبع رمزُه');
    }
  });

  test('ولا يُترجَم إلى حالةٍ خارج الاصطلاح المخزَّن', () {
    const known = {'valid', 'invalid', 'rejected', 'cancelled'};
    for (final raw in ['Valid', 'Invalid', 'Rejected', 'Cancelled']) {
      expect(known, contains(canonicalEInvoiceStatus(raw)));
    }
  });
}
