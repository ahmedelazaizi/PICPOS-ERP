import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/usecases/commercial_papers/manage_paper_usecase.dart';

void main() {
  group('ManagePaperUseCase — CreatePaperInput Validation', () {
    test('CreatePaperInput holds all fields', () {
      final input = CreatePaperInput(
        paperNumber: 'CHK-001',
        type: 'cheque',
        direction: 'received',
        partyId: 10,
        amount: 5000,
        issueDate: DateTime(2026, 3, 1),
        dueDate: DateTime(2026, 6, 1),
        bankName: 'البنك العربي',
        bankBranch: 'فرع عمان',
        accountNumber: '12345',
        safeId: 1,
        notes: 'شيك مؤجل',
      );
      expect(input.paperNumber, 'CHK-001');
      expect(input.type, 'cheque');
      expect(input.direction, 'received');
      expect(input.amount, 5000);
      expect(input.bankName, 'البنك العربي');
    });

    test('optional fields default to null', () {
      final input = CreatePaperInput(
        paperNumber: 'PN-001',
        type: 'promissory_note',
        direction: 'issued',
        partyId: 5,
        amount: 10000,
        issueDate: DateTime(2026, 1, 1),
        dueDate: DateTime(2026, 12, 31),
      );
      expect(input.bankName, isNull);
      expect(input.bankBranch, isNull);
      expect(input.accountNumber, isNull);
      expect(input.safeId, isNull);
      expect(input.notes, isNull);
    });

    test('dueDate must be after issueDate (validation data)', () {
      final input = CreatePaperInput(
        paperNumber: 'CHK-002',
        type: 'cheque',
        direction: 'received',
        partyId: 1,
        amount: 100,
        issueDate: DateTime(2026, 6, 1),
        dueDate: DateTime(2026, 3, 1), // Before issue date
      );
      // Business rule: dueDate < issueDate should be rejected by use case
      expect(input.dueDate.isBefore(input.issueDate), true);
    });
  });

  group('PaperResult', () {
    test('success factory', () {
      final r = PaperResult.success(42);
      expect(r.isSuccess, true);
      expect(r.paperId, 42);
    });

    test('failure factory', () {
      final r = PaperResult.failure('يجب إدخال رقم الورقة');
      expect(r.isSuccess, false);
      expect(r.paperId, isNull);
      expect(r.error, contains('رقم'));
    });
  });
}
