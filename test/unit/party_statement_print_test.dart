// ═══════════════════════════════════════════════════════════════════════════
// طباعة كشف حساب المورد/العميل — ترويسة الشركة وتذييلها، وسلامة الأعمدة
// والإجماليات.
// ═══════════════════════════════════════════════════════════════════════════
//
// المُبلَّغ عنه: عند طباعة كشف حساب المورد لا تظهر بيانات الشركة المسجّلة في
// النظام (الاسم/الهاتف/العنوان) — لا في رأس الصفحة ولا في تذييلها.
//
// ما تبيّن بالفحص أن الأمر أوسع:
//   1) `printStatement` في الشاشة **لا يمرّر `companyName` إطلاقاً**، فالمولّد
//      يقع على `Brand.documentCompanyFallback` — اسم عام لا علاقة له بشركة
//      العميل. والهاتف والعنوان غير ممرَّرين ولا مدعومين أصلاً.
//   2) **لا يوجد تذييل** في الصفحة ولا ترقيم صفحات.
//   3) **لا يوجد صف إجماليات** في PDF رغم أن تصدير Excel من نفس الشاشة يحسب
//      `totalDebit`/`totalCredit`/`finalBalance` ويعرضها. فكشف من صفحتين
//      يُطبع بلا أي مجموع.
//   4) رقم المستند مدموج داخل نص البيان بدل عمود مستقل، فيُطيل العمود ويزاحم
//      أعمدة الأرقام.
//
// هذه الاختبارات تغطي الطبقة القابلة للاختبار وحدةً: بناء بيانات الترويسة
// والتذييل، وحساب الإجماليات، وقياس الأعمدة. رسم الـPDF نفسه لا يُختبَر هنا.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/printing/printing_models.dart';

void main() {
  group('ترويسة وتذييل الشركة', () {
    test('تُبنى من إعدادات النظام لا من اسم افتراضي', () {
      const h = DocumentCompanyHeader(
        name: 'شركة الأمل التجارية',
        phone: '0791234567',
        address: 'عمّان - شارع المدينة المنوّرة',
        taxId: '12345678',
      );

      expect(h.name, 'شركة الأمل التجارية');
      expect(h.hasContactInfo, isTrue);
      // سطر التواصل يجمع الهاتف والعنوان بفاصل واضح.
      expect(h.contactLine, contains('0791234567'));
      expect(h.contactLine, contains('عمّان'));
    });

    test('الحقول الفارغة تُحذف بدل طباعة فواصل معلّقة', () {
      const h = DocumentCompanyHeader(name: 'متجر', phone: '', address: null);
      expect(h.hasContactInfo, isFalse);
      expect(h.contactLine, isEmpty,
          reason: 'لا يُطبع سطر تواصل فارغ ولا فاصل بلا قيمة');

      const onlyPhone = DocumentCompanyHeader(name: 'متجر', phone: '0790000000');
      expect(onlyPhone.contactLine, '0790000000',
          reason: 'بلا فاصل زائد حين يوجد حقل واحد');
    });

    test('الرقم الضريبي يظهر حين يكون مسجّلاً فقط', () {
      const withTax = DocumentCompanyHeader(name: 'ش', taxId: '99');
      const without = DocumentCompanyHeader(name: 'ش');
      expect(withTax.taxLine, contains('99'));
      expect(without.taxLine, isEmpty);
    });

    test('اسم فارغ يقع على البديل بدل طباعة فراغ', () {
      const h = DocumentCompanyHeader(name: '');
      expect(h.displayName.isNotEmpty, isTrue,
          reason: 'رأس المستند لا يُطبع بلا اسم إطلاقاً');
    });
  });

  group('إجماليات كشف الحساب', () {
    final items = [
      StatementItem(
          date: DateTime(2026, 7, 1),
          description: 'فاتورة',
          debit: 0,
          credit: 1000,
          balance: 1000),
      StatementItem(
          date: DateTime(2026, 7, 5),
          description: 'سداد',
          debit: 400,
          credit: 0,
          balance: 600),
      StatementItem(
          date: DateTime(2026, 7, 9),
          description: 'مرتجع',
          debit: 100,
          credit: 0,
          balance: 500),
    ];

    test('صف الإجماليات يجمع المدين والدائن ويأخذ الرصيد الختامي', () {
      final t = StatementTotals.from(items);
      expect(t.totalDebit, closeTo(500, 0.001));
      expect(t.totalCredit, closeTo(1000, 0.001));
      expect(t.closingBalance, closeTo(500, 0.001),
          reason: 'الرصيد الختامي هو رصيد آخر حركة لا مجموع الأرصدة');
    });

    test('كشف فارغ يعطي أصفاراً لا يرمي', () {
      final t = StatementTotals.from(const []);
      expect(t.totalDebit, 0);
      expect(t.totalCredit, 0);
      expect(t.closingBalance, 0);
    });

    test('الإجماليات تُحسب على كل الحركات لا على صفحة واحدة', () {
      final many = List.generate(
        250,
        (i) => StatementItem(
            date: DateTime(2026, 7, 1),
            description: 'حركة $i',
            debit: 10,
            credit: 0,
            balance: 0),
      );
      expect(StatementTotals.from(many).totalDebit, closeTo(2500, 0.001));
    });
  });

  group('قياس الأعمدة الديناميكي', () {
    test('عمود البيان يتمدّد والأرقام تأخذ عرضاً ثابتاً كافياً', () {
      final w = StatementColumnLayout.forItems([
        StatementItem(
            date: DateTime(2026, 7, 1),
            description: 'بيان قصير',
            documentNumber: 'INV-1',
            debit: 1,
            credit: 0,
            balance: 1),
      ]);
      // البيان هو العمود المرن الوحيد؛ البقية بأوزان أصغر ثابتة.
      expect(w.descriptionFlex, greaterThan(w.dateFlex));
      expect(w.descriptionFlex, greaterThan(w.amountFlex));
    });

    test('الأرقام الطويلة توسّع أعمدة المبالغ لا تبترها', () {
      final small = StatementColumnLayout.forItems([
        StatementItem(
            date: DateTime(2026, 7, 1),
            description: 'x',
            debit: 5,
            credit: 0,
            balance: 5),
      ]);
      final large = StatementColumnLayout.forItems([
        StatementItem(
            date: DateTime(2026, 7, 1),
            description: 'x',
            debit: 12345678.999,
            credit: 0,
            balance: 12345678.999),
      ]);
      expect(large.amountFlex, greaterThan(small.amountFlex),
          reason: 'المبالغ الكبيرة تحتاج عرضاً أكبر وإلا التفّ النص');
    });

    test('الخط يصغر تدريجياً مع كثرة الأعمدة الطويلة بدل بتر المحتوى', () {
      final normal = StatementColumnLayout.forItems([
        StatementItem(
            date: DateTime(2026, 7, 1),
            description: 'بيان',
            debit: 10,
            credit: 0,
            balance: 10),
      ]);
      final dense = StatementColumnLayout.forItems([
        StatementItem(
            date: DateTime(2026, 7, 1),
            description:
                'بيان طويل جداً يشرح تفاصيل الحركة بالكامل ويذكر المرجع والسبب',
            documentNumber: 'PUR-2026-000123456',
            debit: 12345678.999,
            credit: 0,
            balance: 12345678.999),
      ]);
      expect(dense.fontSize, lessThan(normal.fontSize),
          reason: 'التصغير النسبي مقبول — البتر ليس كذلك');
      expect(dense.fontSize, greaterThanOrEqualTo(6.0),
          reason: 'لا ينزل تحت حدّ المقروئية');
    });

    test('رقم المستند عمود مستقل حين يوجد', () {
      final withDoc = StatementColumnLayout.forItems([
        StatementItem(
            date: DateTime(2026, 7, 1),
            description: 'x',
            documentNumber: 'INV-9',
            debit: 1,
            credit: 0,
            balance: 1),
      ]);
      final without = StatementColumnLayout.forItems([
        StatementItem(
            date: DateTime(2026, 7, 1),
            description: 'x',
            debit: 1,
            credit: 0,
            balance: 1),
      ]);
      expect(withDoc.showDocumentColumn, isTrue);
      expect(without.showDocumentColumn, isFalse,
          reason: 'لا يُحجز عرض لعمود فارغ تماماً');
    });
  });
}
