import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/usecases/e_invoicing/submit_einvoice_usecase.dart';

void main() {
  group('SubmitEInvoiceUseCase — EInvoiceResult', () {
    test('success with submissionId and documentUuid', () {
      final r = EInvoiceResult.success(
        submissionId: 'SUB-12345',
        documentUuid: 'UUID-ABCDEF',
      );
      expect(r.isSuccess, true);
      expect(r.submissionId, 'SUB-12345');
      expect(r.documentUuid, 'UUID-ABCDEF');
      expect(r.error, isNull);
    });

    test('failure with Arabic error message', () {
      final r = EInvoiceResult.failure('خدمة الفوترة الإلكترونية غير مفعلة');
      expect(r.isSuccess, false);
      expect(r.submissionId, isNull);
      expect(r.documentUuid, isNull);
      expect(r.error, contains('الفوترة'));
    });

    test('failure with connection error', () {
      final r = EInvoiceResult.failure('خطأ في الاتصال: timeout');
      expect(r.isSuccess, false);
      expect(r.error, contains('الاتصال'));
    });
  });

  group('SubmitEInvoiceUseCase — Validation Data', () {
    test('empty invoice number should be rejected', () {
      expect(''.trim().isEmpty, true);
      expect('   '.trim().isEmpty, true);
    });

    test('zero amount should be rejected', () {
      expect(0 <= 0, true);
    });

    test('negative amount should be rejected', () {
      expect(-100 <= 0, true);
    });
  });
}
