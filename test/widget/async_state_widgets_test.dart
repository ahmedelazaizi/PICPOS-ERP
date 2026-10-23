/// Day-21 Widget Tests — Async-State UI Components
///
/// 10 tests across four closely related widgets that together handle every
/// possible data-loading state across the app:
///
///   • AsyncValueWidget   — routes `AsyncValue<T>` to the right sub-widget
///   • AppLoadingIndicator — shows CircularProgressIndicator + optional message
///   • AppErrorWidget      — shows error text + optional retry button
///   • AppEmptyState       — shows empty-state icon, message, optional action
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/presentation/widgets/async_value_widget.dart';

void main() {
// ─────────────────────────────────────────────────────────────────────────────
// AsyncValueWidget — routes AsyncValue to loading / error / data sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

  group('AsyncValueWidget — async-state routing', () {
    testWidgets('loading state shows AppLoadingIndicator, not content',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AsyncValueWidget<String>(
              value: const AsyncValue.loading(),
              data: (s) => Text(s),
            ),
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('data state renders builder output', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AsyncValueWidget<String>(
              value: const AsyncValue.data('مرحباً بالعالم'),
              data: (s) => Text(s),
            ),
          ),
        ),
      );
      expect(find.text('مرحباً بالعالم'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('error state shows AppErrorWidget with the error message',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AsyncValueWidget<String>(
              value: AsyncValue.error(
                'خطأ في الاتصال بقاعدة البيانات',
                StackTrace.current,
              ),
              data: (s) => Text(s),
            ),
          ),
        ),
      );
      // Default error handler wraps the exception in AppErrorWidget
      expect(find.byType(AppErrorWidget), findsOneWidget);
      // The raw exception message should surface somewhere in the tree
      expect(
        find.textContaining('خطأ في الاتصال بقاعدة البيانات'),
        findsOneWidget,
      );
    });
  });

// ─────────────────────────────────────────────────────────────────────────────
// AppLoadingIndicator — spinner + optional label
// ─────────────────────────────────────────────────────────────────────────────

  group('AppLoadingIndicator — spinner display', () {
    testWidgets('always renders a CircularProgressIndicator', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AppLoadingIndicator()),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows message text when message parameter is provided',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppLoadingIndicator(message: 'جاري التحميل...'),
          ),
        ),
      );
      expect(find.text('جاري التحميل...'), findsOneWidget);
    });
  });

// ─────────────────────────────────────────────────────────────────────────────
// AppErrorWidget — error message + optional retry button
// ─────────────────────────────────────────────────────────────────────────────

  group('AppErrorWidget — error display', () {
    testWidgets('renders the error message text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppErrorWidget(message: 'تعذّر تحميل البيانات'),
          ),
        ),
      );
      expect(find.text('تعذّر تحميل البيانات'), findsOneWidget);
    });

    testWidgets('shows retry button and fires callback when onRetry provided',
        (tester) async {
      bool retried = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppErrorWidget(
              message: 'خطأ',
              onRetry: () => retried = true,
            ),
          ),
        ),
      );
      // Retry button must be visible
      expect(find.text('إعادة المحاولة'), findsOneWidget);
      await tester.tap(find.text('إعادة المحاولة'));
      await tester.pump();
      expect(retried, isTrue);
    });

    testWidgets('hides retry button when onRetry is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppErrorWidget(message: 'خطأ', onRetry: null),
          ),
        ),
      );
      expect(find.text('إعادة المحاولة'), findsNothing);
    });
  });

// ─────────────────────────────────────────────────────────────────────────────
// AppEmptyState — empty-state icon, message, and optional action
// ─────────────────────────────────────────────────────────────────────────────

  group('AppEmptyState — empty-state display', () {
    testWidgets('renders the empty-state message', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppEmptyState(message: 'لا توجد نتائج'),
          ),
        ),
      );
      expect(find.text('لا توجد نتائج'), findsOneWidget);
    });

    testWidgets('shows action widget when provided', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppEmptyState(
              message: 'لا توجد فواتير',
              action: ElevatedButton(
                onPressed: () => tapped = true,
                child: const Text('إضافة فاتورة'),
              ),
            ),
          ),
        ),
      );
      expect(find.text('إضافة فاتورة'), findsOneWidget);
      await tester.tap(find.text('إضافة فاتورة'));
      await tester.pump();
      expect(tapped, isTrue);
    });
  });
}
