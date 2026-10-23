import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/presentation/widgets/summary_card.dart';
import 'package:picpos_erp/presentation/widgets/status_badge.dart';
import 'package:picpos_erp/presentation/widgets/form_components.dart';

/// Widget tests for reusable components
void main() {
  group('StatusBadge Factories', () {
    test('fromPaymentStatus creates correct badges', () {
      final paidBadge = StatusBadge.fromPaymentStatus(PaymentStatus.paid);
      expect(paidBadge.text, equals('مدفوع'));

      final partialBadge = StatusBadge.fromPaymentStatus(PaymentStatus.partial);
      expect(partialBadge.text, equals('جزئي'));

      final pendingBadge = StatusBadge.fromPaymentStatus(PaymentStatus.pending);
      expect(pendingBadge.text, equals('معلق'));
    });

    test('fromPaymentStatusString creates correct badges', () {
      expect(StatusBadge.fromPaymentStatusString('paid').text, equals('مدفوع'));
      expect(StatusBadge.fromPaymentStatusString('partial').text, equals('جزئي'));
      expect(StatusBadge.fromPaymentStatusString('pending').text, equals('معلق'));
      expect(StatusBadge.fromPaymentStatusString('unknown').text, equals('معلق'));
    });

    test('forStock creates correct badges based on stock levels', () {
      final available = StatusBadge.forStock(currentStock: 100, minStock: 10);
      expect(available.text, equals('متوفر'));

      final low = StatusBadge.forStock(currentStock: 10, minStock: 10);
      expect(low.text, equals('منخفض'));

      final lowBelow = StatusBadge.forStock(currentStock: 5, minStock: 10);
      expect(lowBelow.text, equals('منخفض'));

      final out = StatusBadge.forStock(currentStock: 0, minStock: 10);
      expect(out.text, equals('نفذ'));
    });
  });

  group('SummaryCard Data', () {
    test('SummaryCard has required properties', () {
      const card = SummaryCard(
        title: 'Test',
        value: '100',
        icon: Icons.star,
        color: Colors.blue,
      );
      
      expect(card.title, equals('Test'));
      expect(card.value, equals('100'));
      expect(card.expanded, isTrue); // default
    });

    test('SummaryCardCompact has required properties', () {
      const card = SummaryCardCompact(
        title: 'Compact',
        value: '50',
        icon: Icons.star,
        color: Colors.red,
      );
      
      expect(card.title, equals('Compact'));
      expect(card.value, equals('50'));
    });
  });

  group('FormComponents', () {
    test('DetailRow has required properties', () {
      const row = DetailRow(
        label: 'Label',
        value: 'Value',
        bold: true,
      );
      
      expect(row.label, equals('Label'));
      expect(row.value, equals('Value'));
      expect(row.bold, isTrue);
    });

    test('FormSection has required properties', () {
      const section = FormSection(
        title: 'Section Title',
        children: [],
      );
      
      expect(section.title, equals('Section Title'));
    });

    test('DialogHeader has required properties', () {
      const header = DialogHeader(
        icon: Icons.info,
        iconColor: Colors.blue,
        title: 'Dialog Title',
      );
      
      expect(header.title, equals('Dialog Title'));
    });
  });
}
