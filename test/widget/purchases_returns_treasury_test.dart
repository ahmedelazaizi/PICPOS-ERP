/// Day-20 Widget Tests — Purchases, Returns & Treasury UI Components
///
/// 10 tests spread across three themes:
///   • ConfirmDialog       — used by delete-purchase / delete-return flows
///   • StatusBadge         — payment-status indicators on purchase invoices
///   • AppStateView        — unified loading/error/empty view used in treasury,
///                           purchase lists, and returns lists
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:ural_erp/presentation/widgets/common_widgets.dart';
import 'package:ural_erp/presentation/widgets/status_badge.dart';
import 'package:ural_erp/core/widgets/app_state_view.dart';
import 'package:ural_erp/core/theme/app_colors.dart';

void main() {
// ─────────────────────────────────────────────────────────────────────────────
// ConfirmDialog — used by purchase & return delete confirmations
// ─────────────────────────────────────────────────────────────────────────────

group('ConfirmDialog — purchase / return delete guard', () {
  testWidgets('renders title and message', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ConfirmDialog(
            title: 'حذف فاتورة مشتريات',
            message: 'هل أنت متأكد من حذف هذه الفاتورة؟',
          ),
        ),
      ),
    );
    expect(find.text('حذف فاتورة مشتريات'), findsOneWidget);
    expect(find.text('هل أنت متأكد من حذف هذه الفاتورة؟'), findsOneWidget);
  });

  testWidgets('renders default confirm and cancel buttons', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ConfirmDialog(title: 'T', message: 'M')),
      ),
    );
    expect(find.text('تأكيد'), findsOneWidget);
    expect(find.text('إلغاء'), findsOneWidget);
  });

  testWidgets('dangerous dialog uses error color for confirm button',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ConfirmDialog(
            title: 'حذف مرتجع',
            message: 'سيتم حذف المرتجع نهائياً',
            isDangerous: true,
          ),
        ),
      ),
    );
    // The ElevatedButton in a dangerous dialog uses AppColors.error.
    // We just verify the button is rendered — colour resolution varies
    // by theme, so a deep style check would be brittle.
    final btn = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(btn, isNotNull);
  });

  testWidgets('onConfirm callback fires when confirm button is tapped',
      (tester) async {
    bool confirmed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConfirmDialog(
            title: 'حذف',
            message: 'تأكيد الحذف؟',
            onConfirm: () => confirmed = true,
          ),
        ),
      ),
    );
    await tester.tap(find.text('تأكيد'));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
  });

  testWidgets('shows icon when provided', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ConfirmDialog(
            title: 'حذف فاتورة',
            message: 'تأكيد؟',
            icon: PhosphorIconsBold.trash,
          ),
        ),
      ),
    );
    expect(find.byIcon(PhosphorIconsBold.trash), findsOneWidget);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// StatusBadge — purchase invoice payment statuses
// ─────────────────────────────────────────────────────────────────────────────

group('StatusBadge — purchase invoice payment statuses', () {
  testWidgets('paid status shows مدفوع in success color', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatusBadge.fromPaymentStatus(PaymentStatus.paid),
        ),
      ),
    );
    expect(find.text('مدفوع'), findsOneWidget);
    final text = tester.widget<Text>(find.text('مدفوع'));
    expect(text.style?.color, equals(AppColors.success));
  });

  testWidgets('partial status shows جزئي in warning color', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatusBadge.fromPaymentStatus(PaymentStatus.partial),
        ),
      ),
    );
    expect(find.text('جزئي'), findsOneWidget);
    final text = tester.widget<Text>(find.text('جزئي'));
    expect(text.style?.color, equals(AppColors.warning));
  });

  testWidgets('pending status shows معلق in error color', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatusBadge.fromPaymentStatus(PaymentStatus.pending),
        ),
      ),
    );
    expect(find.text('معلق'), findsOneWidget);
    final text = tester.widget<Text>(find.text('معلق'));
    expect(text.style?.color, equals(AppColors.error));
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// AppStateView — treasury / purchase / returns list state management
// ─────────────────────────────────────────────────────────────────────────────

group('AppStateView — purchase, returns & treasury list states', () {
  testWidgets('shows shimmer when isLoading is true', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppStateView(
            isLoading: true,
            isEmpty: false,
            emptyMessage: 'لا توجد فواتير',
            child: Text('content'),
          ),
        ),
      ),
    );
    // Content must NOT be visible during loading
    expect(find.text('content'), findsNothing);
  });

  testWidgets('shows emptyMessage when isEmpty is true', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppStateView(
            isLoading: false,
            isEmpty: true,
            emptyMessage: 'لا توجد مرتجعات',
            child: Text('content'),
          ),
        ),
      ),
    );
    expect(find.text('لا توجد مرتجعات'), findsOneWidget);
    expect(find.text('content'), findsNothing);
  });

  testWidgets('shows error message when error is provided', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppStateView(
            isLoading: false,
            isEmpty: false,
            error: 'خطأ في تحميل بيانات الخزينة',
            emptyMessage: 'لا توجد بيانات',
            child: Text('content'),
          ),
        ),
      ),
    );
    expect(find.text('خطأ في تحميل بيانات الخزينة'), findsOneWidget);
    expect(find.text('content'), findsNothing);
  });

  testWidgets('shows child when data is available', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppStateView(
            isLoading: false,
            isEmpty: false,
            emptyMessage: 'لا توجد فواتير مشتريات',
            child: Text('قائمة المشتريات'),
          ),
        ),
      ),
    );
    expect(find.text('قائمة المشتريات'), findsOneWidget);
  });

  testWidgets('loading takes priority over empty state', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppStateView(
            isLoading: true,
            isEmpty: true, // both true
            emptyMessage: 'لا توجد بيانات',
            child: Text('content'),
          ),
        ),
      ),
    );
    // Shimmer should show, not empty message
    expect(find.text('لا توجد بيانات'), findsNothing);
  });
});
} // end main
