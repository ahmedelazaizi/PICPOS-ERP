// ═══════════════════════════════════════════════════════════════════════════
// حمولةُ المستند الضريبيّ تُبنى في موضعٍ واحد — لا بيدِ كلِّ منادٍ.
// ═══════════════════════════════════════════════════════════════════════════
//
// ═══ فئةُ العطب ═══
//
// `buildInvoicePayload` يبني الحمولةَ الصحيحةَ من الفاتورة: بنودُها وتاريخُها
// ومشتريها ونسخةُ مستندها. و`EInvoiceAutoSubmitter._buildUnifiedInvoice`
// يحوّلها صحيحاً.
//
// لكنّ شاشةَ الفاتورة الإلكترونيّة كانت **تجلب الحمولةَ ثمّ ترميها**: تبني
// `UnifiedInvoice(items: [], issueDate: DateTime.now())` بيدها في موضعَين
// (‏«إرسال المعلَّقة» و«إرسالُ واحد»). فما يصل مصلحةَ الضرائب مستندٌ **بلا
// بنودٍ وبتاريخ اليوم** لفاتورةٍ حرّرت أمس — إقرارٌ خاطئٌ لا إخفاقُ إرسال.
//
// فالتحويلُ صار مصنعاً واحداً على النموذج نفسِه، ولا يبنيه أحدٌ بيده.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/e_invoicing/e_invoice_service_wrapper.dart';

void main() {
  Map<String, dynamic> payload() => {
        'platform': 'eta',
        'documentVersion': '1.0',
        'internalId': 'INV-55',
        'issueDate': DateTime(2026, 8, 30, 11, 20).toIso8601String(),
        'seller': {'registrationNumber': '100-200-300', 'branchId': '0'},
        'buyer': {'name': 'عميل', 'taxNumber': '999'},
        'items': <Map<String, dynamic>>[
          {
            'description': 'صنف أ',
            'itemCode': 'EG-1',
            'itemType': 'EGS',
            'unitType': 'EA',
            'quantity': 2.0,
            'unitPrice': 100.0,
            'discount': 10.0,
            'taxType': 'T1',
            'taxSubtype': 'V009',
            'taxRate': 14.0,
          },
          {
            'description': 'صنف ب',
            'itemCode': 'EG-2',
            'quantity': 1.0,
            'unitPrice': 50.0,
            'taxRate': 14.0,
          },
        ],
        'paymentMethod': 'cash',
      };

  test('🔴 البنودُ تُحمَل — لا تُرمى', () {
    final inv = UnifiedInvoice.fromPayload(payload());

    expect(inv.items, hasLength(2),
        reason: 'مستندٌ ضريبيٌّ بلا بنودٍ إقرارٌ خاطئ');
    expect(inv.items.first.description, 'صنف أ');
    expect(inv.items.first.quantity, 2.0);
    expect(inv.items.first.unitPrice, 100.0);
    expect(inv.items.first.discount, 10.0);
  });

  test('🔴 التاريخُ من الفاتورة لا من ساعة الإرسال', () {
    final inv = UnifiedInvoice.fromPayload(payload());

    expect(inv.issueDate, DateTime(2026, 8, 30, 11, 20),
        reason: 'فاتورةُ أمسٍ تُقدَّم بتاريخ أمس — لا بتاريخ اليوم');
  });

  test('المشتري ونسخةُ المستند وطريقةُ الدفع تُحمَل', () {
    final inv = UnifiedInvoice.fromPayload(payload());

    expect(inv.buyer?['name'], 'عميل');
    expect(inv.documentVersion, '1.0',
        reason: 'ETA تميّز 0.9 من 1.0 — وإغفالُها يُغيّر شكلَ المستند');
    expect(inv.paymentMethod, 'cash');
    expect(inv.internalId, 'INV-55');
    expect(inv.seller['registrationNumber'], '100-200-300');
  });

  test('نوعُ المستند يتبع الحمولة — إشعارُ ائتمانٍ لا فاتورة', () {
    final p = payload()..['documentType'] = 'credit_note';

    expect(UnifiedInvoice.fromPayload(p).invoiceType, 'credit_note');
  });

  // 🔴 الحمولةُ تُخزَّن نصّاً في `rawRequest`، فمسارُ إعادةِ محاولةٍ يقرؤها
  //    مفكوكةً من JSON — وعندها تصير القوائمُ `List<dynamic>` والخرائطُ
  //    `Map<String, dynamic>` بقيمٍ `dynamic`. وقالبٌ صارمٌ كان سيرمي
  //    استثناءً يبتلعه `catch` فيُعدّ «إخفاقَ إرسال» بلا سبب.
  test('🔴 تعمل على حمولةٍ مرَّت بـJSON — لا ترمي على List<dynamic>', () {
    final roundTripped =
        jsonDecode(jsonEncode(payload())) as Map<String, dynamic>;

    final inv = UnifiedInvoice.fromPayload(roundTripped);

    expect(inv.items, hasLength(2));
    expect(inv.items.first.quantity, 2.0);
    expect(inv.issueDate, DateTime(2026, 8, 30, 11, 20));
  });

  test('حمولةٌ بلا بنودٍ تُنتج مستنداً بلا بنود — ولا ترمي', () {
    final p = payload()..['items'] = <Map<String, dynamic>>[];

    expect(UnifiedInvoice.fromPayload(p).items, isEmpty);
  });
}
