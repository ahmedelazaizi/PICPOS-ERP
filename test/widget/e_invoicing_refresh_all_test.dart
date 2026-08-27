// test/widget/e_invoicing_refresh_all_test.dart
//
// «تحديث الحالات» — الفعلُ الثاني في رأس التصميم، وكان غائباً عن الفورك.
//
// ═══ ما يقيسه — وهو **مَن يُفحَص** لا مجرّد ظهورِ الزرّ ═══
//
// الفحصُ نداءٌ خارجيٌّ لمنظومة الضرائب لكلّ مستند. فعدُّ الصفوف الخطأ يعني
// إمّا نداءاتٍ لا لزوم لها على أحكامٍ نهائيّة، أو — وهو الأسوأ — زرّاً
// يَعِد بفحصٍ ثمّ يرتدّ صامتاً لأنّ المستندَ بلا معرِّف.
//
// فالمقيسُ هنا القاعدةُ نفسُها:
//   • `submitted` ومعه معرِّف   ⇒ يُفحَص — هو وحدَه المنتظِرُ حكماً.
//   • `submitted` بلا معرِّف     ⇒ **لا** — لا شيءَ يُسأل عنه.
//   • `pending`                  ⇒ لا — لم يُرسَل أصلاً.
//   • `valid` · `rejected` · `cancelled` ⇒ لا — أحكامٌ نهائيّة.
//   • `invalid`                  ⇒ لا — لا ينقلب إلّا بإعادة إرسال.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/auth_providers.dart';
import 'package:ural_erp/data/providers/repository_providers.dart';
import 'package:ural_erp/domain/repositories/e_invoice_repository.dart';
import 'package:ural_erp/presentation/e_invoicing_picpos/screens/e_invoicing_picpos_screen.dart';

Map<String, dynamic> _row({
  required int id,
  required String status,
  String? uuid,
}) =>
    {
      'id': id,
      'sale_id': 100 + id,
      'platform': 'eta',
      'document_type': 'invoice',
      'status': status,
      'internal_id': 'INV-2026-10$id',
      'document_uuid': uuid,
      'long_id': null,
      'submission_id': uuid == null ? null : 'SUB-$id',
      'hash_key': null,
      'qr_code': null,
      'error_message': null,
      'raw_request': null,
      'raw_response': null,
      'retry_count': 0,
      'submitted_at': null,
      'last_checked_at': null,
      'invoice_number': 'SL-10$id',
      'customer_name': 'عميل $id',
      'invoice_total': 1000.0,
    };

class _FakeRepo implements IEInvoiceRepository {
  _FakeRepo(this.rows);
  final List<Map<String, dynamic>> rows;

  @override
  Stream<List<Map<String, dynamic>>> watchSubmissionsWithInvoice() =>
      Stream.value(rows);

  @override
  Future<List<Map<String, dynamic>>> getStatusAuditTrail(int id) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(
  WidgetTester tester,
  double width,
  List<Map<String, dynamic>> rows,
) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        eInvoiceRepositoryProvider.overrideWithValue(_FakeRepo(rows)),
        currentUserPermissionsProvider
            .overrideWith((ref) async => const ['einvoice_submit']),
      ],
      child: const MaterialApp(home: EInvoicingPicposScreen()),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  for (final width in [1280.0, 1920.0]) {
    final w = width.toInt();

    group('عرض $w', () {
      testWidgets('الزرُّ حاضرٌ في الرأس بعدّاد المنتظِر', (tester) async {
        await _pump(tester, width, [
          _row(id: 1, status: 'submitted', uuid: 'u1'),
          _row(id: 2, status: 'submitted', uuid: 'u2'),
        ]);

        expect(find.text('تحديث الحالات (٢)'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('والأحكامُ النهائيّةُ لا تُعَدّ', (tester) async {
        await _pump(tester, width, [
          _row(id: 1, status: 'valid', uuid: 'u1'),
          _row(id: 2, status: 'rejected', uuid: 'u2'),
          _row(id: 3, status: 'cancelled', uuid: 'u3'),
          _row(id: 4, status: 'invalid', uuid: 'u4'),
          _row(id: 5, status: 'submitted', uuid: 'u5'),
        ]);

        // خمسةُ صفوفٍ وواحدٌ فقط ينتظر حكماً.
        expect(find.text('تحديث الحالات (١)'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('ومُرسَلٌ بلا معرِّفٍ لا يُعَدّ — الزرُّ لا يَعِد بما يرتدّ',
          (tester) async {
        await _pump(tester, width, [
          _row(id: 1, status: 'submitted', uuid: null),
          _row(id: 2, status: 'pending', uuid: null),
        ]);

        expect(find.text('تحديث الحالات (٠)'), findsOneWidget);
        // ⚠️ وصفرٌ ⇒ معطَّل: زرٌّ يُضغَط بلا عملٍ يُنتج رسالةً كاذبة.
        final btn = tester.widget<OutlinedButton>(
          find
              .ancestor(
                of: find.text('تحديث الحالات (٠)'),
                matching: find.byType(OutlinedButton),
              )
              .first,
        );
        expect(btn.onPressed, isNull);
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });
    });
  }
}
