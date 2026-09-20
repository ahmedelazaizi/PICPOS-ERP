// تحذيرُ تعديل فاتورة المشتريات — **يُقاس بالأستاذ، لا بـ`isLocked`.**
//
// ═══ ما كان ═══
//
// `_confirmEditInvoice` كان يعرض الحوارَ عند `invoice.paid > 0 ||
// invoice.isLocked` فقط. ونصُّ الحوار صادقٌ فيما يصف: التعديلُ **يعكس**
// القيدَ المحاسبيَّ وحركةَ المخزون والتكلفةَ المتوسّطة ثمّ يعيد ترحيلَها.
// لكنّ **الشرطَ** كان يقيس رايةً لا تعني ذلك:
//
//   • `updatePurchaseInvoice` ينادي `_reverseOldPurchaseJournalEntry`
//     **بلا شرط**، ثمّ `autoPostPurchase` يعيد الترحيل.
//   • و`createPurchaseInvoice` يرحّل قيدَه مُدمَجاً و**لا يرفع `isLocked`
//     قطّ** — موثَّقٌ حرفيّاً في `purchase_dao.dart` عند مسار الإلغاء.
//
// فالحالةُ **الشائعة** — فاتورةٌ آجلةٌ أُنشئت من شاشة المشتريات:
// `paid == 0` و`isLocked == false` وقيدُها في الأستاذ — كانت تُعدَّل
// فيُعكَس قيدُها ويُعاد ترحيلُه **بلا تحذيرٍ أصلاً**.
//
// ═══ والمقروءُ الآن ═══
//
// `postedInvoiceIds` من حالة المتحكّم — وهي مخرَجُ
// `AppDatabase.postedPurchaseInvoiceIds` التي تقرأ `journal_entries`
// بـ`kPurchaseJeReferenceTypes`. و`null` فيها = «لم يُعرَف بعد» لا «لا شيء
// مُرحَّل»، فتُسأل القاعدةُ عندها بدل تخطّي التحذير صامتاً.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/domain/entities/invoice_entity.dart';
import 'package:ural_erp/domain/repositories/purchases_repository.dart';
import 'package:ural_erp/presentation/purchases_picpos/screens/purchases_picpos_screen.dart';
import 'package:ural_erp/presentation/screens/purchases/purchase_invoices_controller.dart';

const int _kInvoiceId = 1;

/// عنوانا الحوار — والفاصلُ بينهما أيُّ خطرٍ استدعاه.
const _kPostedTitle = 'تعديل فاتورة مُرحّلة محاسبياً';
const _kPaidTitle = 'تعديل فاتورة مدفوعة';

InvoiceEntity _inv({
  required double paid,
  required bool isLocked,
}) =>
    InvoiceEntity(
      id: _kInvoiceId,
      invoiceNumber: 'PINV-0301',
      type: InvoiceType.purchase,
      invoiceDate: DateTime(2026, 9, 18),
      lines: const [],
      subtotal: 900,
      total: 900,
      paid: paid,
      status: paid > 0 ? InvoiceStatus.paid : InvoiceStatus.pending,
      isLocked: isLocked,
    );

class _FrozenController extends PurchaseInvoicesController {
  _FrozenController(this._invoice, this._posted);
  final InvoiceEntity _invoice;
  final Set<int>? _posted;

  @override
  PurchaseInvoicesScreenState build() => PurchaseInvoicesScreenState(
        isLoading: false,
        allInvoices: [_invoice],
        filteredInvoices: [_invoice],
        postedInvoiceIds: _posted,
      );
}

/// مستودعٌ يسجّل «هل مضى التعديلُ فعلاً؟» ويرجع `null` فلا تُفتَح استمارة.
class _RecordingPurchasesRepo implements PurchasesRepository {
  int rawFetches = 0;

  @override
  Future<PurchaseInvoiceData?> getRawInvoiceById(int id) async {
    rawFetches++;
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError(
      'Stub: ${inv.memberName} غيرُ متوقَّعةٍ في اختبار تحذير التعديل');
}

Future<_RecordingPurchasesRepo> _pump(
  WidgetTester tester, {
  required AppDatabase db,
  required InvoiceEntity invoice,
  required Set<int>? posted,
}) async {
  final repo = _RecordingPurchasesRepo();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        purchasesRepositoryProvider.overrideWithValue(repo),
        purchaseInvoicesControllerProvider
            .overrideWith(() => _FrozenController(invoice, posted)),
        hasPermissionProvider(PermissionCodes.purchasesEdit)
            .overrideWith((ref) async => true),
        allBranchesProvider.overrideWith((ref) => Stream.value(const [])),
        allWarehousesProvider.overrideWith((ref) => Stream.value(const [])),
        allCostCentersProvider.overrideWith((ref) => Stream.value(const [])),
      ],
      child: const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: PurchasesPicposScreen(),
        ),
      ),
    ),
  );
  // إطارٌ ثانٍ: `hasPermissionProvider` مستقبلٌ، وزرُّ التعديل معطَّلٌ قبل
  // وصولِه — فالنقرُ على الإطار الأوّل ينقر زرّاً بلا `onTap`.
  await tester.pump();
  await tester.pump();
  return repo;
}

/// ينقر قلمَ التعديل ويدفع إطاراتٍ تكفي لاستقرار الحوار.
Future<void> _tapEdit(WidgetTester tester) async {
  await tester.tap(find.byIcon(PhosphorIconsBold.pencilSimple));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// تفكيكُ الشجرة ودفعُ إطار — ولا تُغلَق القاعدةُ: `close()` ينتظر مؤقّتَ
/// drift في المنطقة الوهميّة فيعلّق الاختبارَ بلا رسالة.
Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  // قاعدةٌ واحدةٌ للملفّ كلّه: `forTesting()` مرّتين على نفس المنفّذ
  // يطبع drift تحذيرَ سباقٍ، والاختباراتُ الأربعةُ الأولى لا تلمسها أصلاً.
  late AppDatabase db;

  setUpAll(() {
    db = AppDatabase.forTesting();
  });

  testWidgets('مرساةٌ — الصفُّ وزرُّ التعديل رُسما فعلاً', (tester) async {
    await _pump(tester,
        db: db,
        invoice: _inv(paid: 0, isLocked: false),
        posted: const {_kInvoiceId});
    // بلا هذه المرساة يمرّ كلُّ ما تحتها على شاشةٍ فارغة: `AppStateView`
    // ترسم «لا توجد فواتير» حين تخلو القائمة، فلا زرَّ يُنقَر أصلاً.
    expect(find.text('PINV-0301'), findsOneWidget);
    expect(find.byIcon(PhosphorIconsBold.pencilSimple), findsOneWidget);
    await _teardown(tester);
  });

  testWidgets(
      'فاتورةٌ غيرُ مدفوعةٍ و`isLocked == false` لكنّ قيدَها في الأستاذ '
      '⇒ يُحذَّر', (tester) async {
    // ⚠️ **هذه هي الحالةُ الشائعة** — فاتورةٌ آجلةٌ من شاشة المشتريات.
    // الشرطُ القديم `paid > 0 || isLocked` يقرأ صفراً وكذباً، فيمضي إلى
    // التعديل بلا حوار بينما القيدُ يُعكَس ويُعاد ترحيلُه.
    final repo = await _pump(tester,
        db: db,
        invoice: _inv(paid: 0, isLocked: false),
        posted: const {_kInvoiceId});
    await _tapEdit(tester);

    expect(find.text(_kPostedTitle), findsOneWidget,
        reason: 'قيدٌ في الأستاذ يُعكَس ويُعاد ترحيلُه بلا تحذير');
    expect(repo.rawFetches, 0,
        reason: 'مضى إلى التعديل قبل أن يجيب المستخدمُ على الحوار');
    await _teardown(tester);
  });

  testWidgets('ولا قيدَ لها ⇒ لا حوارَ، ويمضي إلى التعديل', (tester) async {
    final repo = await _pump(tester,
        db: db,
        invoice: _inv(paid: 0, isLocked: false),
        posted: const <int>{});
    await _tapEdit(tester);

    expect(find.text(_kPostedTitle), findsNothing);
    expect(find.text(_kPaidTitle), findsNothing);
    expect(repo.rawFetches, 1,
        reason: 'حوارٌ بلا خطرٍ يعترض الحالةَ الطبيعيّة بلا سبب');
    await _teardown(tester);
  });

  testWidgets('و`isLocked == true` وحدَها لا تُحذِّر — الرايةُ ليست الأستاذ',
      (tester) async {
    // ⚠️ وهذا ما يمنع «احتفظ بـ`isLocked` كشرطٍ إضافيّ»: الإلغاءُ يرفعها
    // أيضاً (‏`isLocked: const Value(true)` مع `isDeleted`)، فحوارٌ مبنيٌّ
    // عليها يُنذر على فاتورةٍ لا قيدَ لها في الأستاذ.
    final repo = await _pump(tester,
        db: db,
        invoice: _inv(paid: 0, isLocked: true),
        posted: const <int>{});
    await _tapEdit(tester);

    expect(find.text(_kPostedTitle), findsNothing,
        reason: 'الحوارُ ما زال يقرأ الرايةَ لا الأستاذ');
    expect(repo.rawFetches, 1);
    await _teardown(tester);
  });

  testWidgets('و«لم يُعرَف بعد» يسأل الأستاذَ ولا يتخطّى التحذير',
      (tester) async {
    // `null` ليست «لا شيءَ مُرحَّل» — الاستعلامُ يصل بعد التحميل الأوّل وقد
    // يُخفق. وتخطّي التحذير حينئذٍ هو بعينه العطبُ المُبلَّغ عنه.
    //
    // ⚠️ **وكلُّ لمسةِ قاعدةٍ هنا داخلَ `runAsync`**: جسمُ `testWidgets` يعمل
    // في منطقةٍ وهميّةِ الزمن، وsqlite3 يجدول على مؤقّتاتٍ **حقيقيّة** لا
    // تتقدّم فيها — فالإدراجُ والاستعلامُ يعلّقان بلا رسالةٍ ولا مهلة.
    await tester.runAsync(() async {
      await db.into(db.journalEntries).insert(
            JournalEntriesCompanion.insert(
              entryNumber: 'JE-P-0301',
              entryDate: DateTime(2026, 9, 18),
              referenceType: const Value('purchase_invoice'),
              referenceId: const Value(_kInvoiceId),
              isAutoPosted: const Value(true),
              isPosted: const Value(true),
            ),
          );
    });
    final repo = await _pump(tester,
        db: db, invoice: _inv(paid: 0, isLocked: false), posted: null);

    await tester.runAsync(() async {
      await tester.tap(find.byIcon(PhosphorIconsBold.pencilSimple));
      // النقرةُ تُرسِل الحدثَ ثمّ يمضي المعالِجُ إلى الأستاذ — وهذه المهلةُ
      // هي زمنُه الحقيقيُّ كي يعود قبل أن نبني إطاراً.
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(_kPostedTitle), findsOneWidget,
        reason: 'لم يُسأل الأستاذُ حين كانت الحالةُ مجهولةً — تُخطّي التحذير');
    expect(repo.rawFetches, 0);
    await _teardown(tester);
  });

  testWidgets('ومدفوعةٌ بلا قيدٍ ⇒ حوارُ «مدفوعة» لا حوارُ «مُرحّلة»',
      (tester) async {
    final repo = await _pump(tester,
        db: db,
        invoice: _inv(paid: 500, isLocked: false),
        posted: const <int>{});
    await _tapEdit(tester);

    expect(find.text(_kPaidTitle), findsOneWidget,
        reason: 'خطرُ المبلغ المدفوع سقط مع تصحيح شرط الترحيل');
    expect(find.text(_kPostedTitle), findsNothing);
    expect(repo.rawFetches, 0);
    await _teardown(tester);
  });

  testWidgets('وإخفاقُ قراءة الأستاذ يُحذِّر تحفّظاً ولا يصمت', (tester) async {
    // الاحتياطيُّ نفسُه قد يُخفق — والصمتُ عندها يعيد العطبَ من بابٍ آخر:
    // ثمنُ تحذيرٍ زائدٍ نقرةٌ، وثمنُ إسقاطه قيدٌ يُعكَس بلا علم المستخدم.
    //
    // وقاعدةٌ **مُغلَقة** هي المحاكاةُ الأمينةُ لذلك: أيُّ استعلامٍ بعدها
    // يرمي كما يرمي قرصٌ معطوبٌ أو ملفٌّ مقفول.
    final broken = AppDatabase.forTesting();
    await tester.runAsync(() async {
      await broken.customSelect('SELECT 1').get();
      await broken.close();
    });

    final repo = await _pump(tester,
        db: broken, invoice: _inv(paid: 0, isLocked: false), posted: null);
    await tester.runAsync(() async {
      await tester.tap(find.byIcon(PhosphorIconsBold.pencilSimple));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(_kPostedTitle), findsOneWidget,
        reason: 'أخفقت القراءةُ فمضى إلى التعديل صامتاً');
    expect(repo.rawFetches, 0);
    await _teardown(tester);
  });
}
