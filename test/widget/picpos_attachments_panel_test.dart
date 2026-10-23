// لوحُ المرفقات — الحارسُ الأوّلُ من ثلاثة (§٨، الخطوة هـ).
//
// ═══ ⚠️ ولا قاعدةَ حقيقيّةً هنا ═══
//
// `AppDatabase.forTesting()` داخلَ `testWidgets` يُجمّد السويّةَ كلَّها:
// `db.close()` ينتظر مؤقّتَ drift في المنطقة الوهميّة. فالمستودعُ **وهميٌّ**
// والمزوّدُ يُتجاوَز.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/models/attachment_policy.dart';
import 'package:picpos_erp/domain/repositories/attachments_repository.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_attachments_panel.dart';

AttachmentData _row({
  required int id,
  required String gid,
  String fileName = 'bill.pdf',
  String mimeType = 'application/pdf',
  int byteSize = 2048,
  String docType = 'other',
}) =>
    AttachmentData(
      id: id,
      entityType: 'purchase_invoice',
      entityGlobalId: 'doc-A',
      entityId: 7,
      fileName: fileName,
      mimeType: mimeType,
      byteSize: byteSize,
      shaHex: 'a' * 64,
      docType: docType,
      attachedAt: DateTime(2026, 9, 20),
      globalId: gid,
      rowVersion: 0,
    );

class _FakeRepo implements IAttachmentsRepository {
  _FakeRepo({this.anchor = 'doc-A', List<AttachmentData>? rows})
      : rows = rows ?? <AttachmentData>[];

  final String? anchor;
  final List<AttachmentData> rows;

  final adds = <({String fileName, int size})>[];
  final deletes = <String>[];
  String? addError;

  @override
  Future<String?> entityGlobalId({
    required String entityType,
    required int entityId,
  }) async =>
      anchor;

  @override
  Stream<List<AttachmentData>> watchAttachments({
    required String entityType,
    int? entityId,
    String? entityGlobalId,
  }) =>
      Stream<List<AttachmentData>>.value(rows);

  @override
  Future<List<AttachmentData>> getAttachments({
    required String entityType,
    int? entityId,
    String? entityGlobalId,
  }) async =>
      rows;

  @override
  Future<AttachmentResult> addAttachment({
    required String entityType,
    int? entityId,
    String? entityGlobalId,
    required String fileName,
    required Uint8List bytes,
    String? mimeType,
    AttachmentDocType docType = AttachmentDocType.other,
    int? attachedByUserId,
    String? notes,
  }) async {
    adds.add((fileName: fileName, size: bytes.length));
    if (addError != null) return (error: addError, attachment: null);
    return (error: null, attachment: _row(id: 99, gid: 'new'));
  }

  @override
  Future<String?> deleteAttachment(String globalId) async {
    deletes.add(globalId);
    return null;
  }

  @override
  Future<Uint8List?> attachmentBytes(AttachmentData attachment) async => null;

  @override
  Future<bool> hasLocalBytes(String globalId) async => false;
}

Future<void> _pump(
  WidgetTester tester, {
  required _FakeRepo repo,
  int? entityId = 7,
  String entityType = 'purchase_invoice',
  bool readOnly = false,
  Future<PickedAttachment?> Function()? pick,
}) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        attachmentsRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        locale: const Locale('ar'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('ar'), Locale('en')],
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SingleChildScrollView(
              child: PicPosAttachmentsPanel(
                entityType: entityType,
                entityId: entityId,
                readOnly: readOnly,
                pickFile: pick,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// المؤقّتُ في `AppToast` يبقى بعد التفكيك ويُسقط السويّة.
Future<void> _settleToast(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
}

void main() {
  testWidgets('مستندٌ بلا رقمٍ — يُقال «احفظ أوّلاً» ولا يُرفَق', (t) async {
    final repo = _FakeRepo();
    await _pump(t, repo: repo, entityId: null);

    expect(find.byKey(const Key('attachments_locked')), findsOneWidget);
    final add = t.widget<TextButton>(
        find.ancestor(
              of: find.text('إضافة'),
              matching: find.byType(TextButton),
            ).first);
    expect(add.onPressed, isNull,
        reason: 'زرُّ الإضافة حيٌّ على مستندٍ لا رقمَ له ⇒ ورقةٌ معلَّقةٌ '
            'على لا شيء.');
    await _settleToast(t);
  });

  testWidgets('🔴 ومستندٌ لم ينل هُويّتَه — يُقال ذلك لا يفشل صامتاً',
      (t) async {
    final repo = _FakeRepo(anchor: null);
    await _pump(t, repo: repo);

    expect(find.byKey(const Key('attachments_locked')), findsOneWidget);
    await _settleToast(t);
  });

  testWidgets('ونوعُ مستندٍ غيرُ مدعومٍ يُقال صراحةً', (t) async {
    final repo = _FakeRepo();
    await _pump(t, repo: repo, entityType: 'stock_movement');

    expect(find.byKey(const Key('attachments_unsupported')), findsOneWidget);
    await _settleToast(t);
  });

  testWidgets('ولا مرفقاتٍ — حالةُ فراغٍ تقول الحدَّ والأنواع', (t) async {
    final repo = _FakeRepo();
    await _pump(t, repo: repo);

    expect(find.byKey(const Key('attachments_empty')), findsOneWidget);
    expect(find.textContaining('PDF'), findsOneWidget);
    await _settleToast(t);
  });

  testWidgets('والمرفقاتُ تُعرَض باسمها وحجمها وتصنيفها', (t) async {
    final repo = _FakeRepo(rows: [
      _row(id: 1, gid: 'g1', fileName: 'customs.pdf', byteSize: 2048,
          docType: 'customs_declaration'),
    ]);
    await _pump(t, repo: repo);

    expect(find.byKey(const Key('attachment_tile_g1')), findsOneWidget);
    expect(find.text('customs.pdf'), findsOneWidget);
    expect(find.textContaining('بيان جمركي'), findsOneWidget);
    expect(find.textContaining('2.0 ك.ب'), findsOneWidget);
    await _settleToast(t);
  });

  testWidgets('🔴 وبلوغُ السقف يُخمِد زرَّ الإضافة — لا يُخفيه', (t) async {
    final repo = _FakeRepo(rows: [
      for (var i = 0; i < kAttachmentMaxPerDocument; i++)
        _row(id: i + 1, gid: 'g$i'),
    ]);
    await _pump(t, repo: repo);

    final add = t.widget<TextButton>(find
        .ancestor(of: find.text('إضافة'), matching: find.byType(TextButton))
        .first);
    expect(add.onPressed, isNull);
    expect(find.textContaining('/$kAttachmentMaxPerDocument'), findsOneWidget,
        reason: 'العدّادُ لا يُعرَض ⇒ المستخدمُ لا يعرف لِمَ خمد الزرّ.');
    await _settleToast(t);
  });

  testWidgets('و`readOnly` يمنع الإضافةَ والحذفَ معاً', (t) async {
    final repo = _FakeRepo(rows: [_row(id: 1, gid: 'g1')]);
    await _pump(t, repo: repo, readOnly: true);

    expect(find.byKey(const Key('attachment_delete_g1')), findsNothing);
    final add = t.widget<TextButton>(find
        .ancestor(of: find.text('إضافة'), matching: find.byType(TextButton))
        .first);
    expect(add.onPressed, isNull);
    await _settleToast(t);
  });

  testWidgets('والإضافةُ تمرّر الاسمَ والبايتاتِ إلى المستودع', (t) async {
    final repo = _FakeRepo();
    await _pump(
      t,
      repo: repo,
      pick: () async =>
          (name: 'scan.png', bytes: Uint8List.fromList([1, 2, 3, 4])),
    );

    await t.tap(find.byKey(const Key('attachments_add')));
    await t.pump();
    await t.pump();

    expect(repo.adds, hasLength(1));
    expect(repo.adds.single.fileName, 'scan.png');
    expect(repo.adds.single.size, 4);
    await _settleToast(t);
  });

  testWidgets('🔴 ورسالةُ الرفض تُعرَض كما هي — لا «حدث خطأ»', (t) async {
    final repo = _FakeRepo()..addError = 'الملفُّ أكبرُ من 5.0 م.ب';
    await _pump(
      t,
      repo: repo,
      pick: () async => (name: 'big.png', bytes: Uint8List(8)),
    );

    await t.tap(find.byKey(const Key('attachments_add')));
    await t.pump();
    await t.pump();

    expect(find.textContaining('أكبرُ من 5.0 م.ب'), findsOneWidget,
        reason: 'رسالةٌ عامّةٌ تترك المستخدمَ يجرّب نفسَ الملفّ مراراً.');
    await _settleToast(t);
  });

  testWidgets('وإلغاءُ المُنتقي لا يكتب شيئاً', (t) async {
    final repo = _FakeRepo();
    await _pump(t, repo: repo, pick: () async => null);

    await t.tap(find.byKey(const Key('attachments_add')));
    await t.pump();
    await t.pump();

    expect(repo.adds, isEmpty);
    await _settleToast(t);
  });
}
