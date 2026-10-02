// ═══════════════════════════════════════════════════════════════════════════
// API VOUCHER HANDLER — سندات القبض والصرف من جهاز العميل (E-fix ١)
// ═══════════════════════════════════════════════════════════════════════════
//
// جهازُ العميل (LAN client / mirror) لا يكتب السندَ محلّيّاً: يرسل **حمولةً
// واحدة** يُعيد الخادمُ بها نفسَ ما يكتبه الجهازُ الرئيسيّ حرفاً بحرف:
//
//   • `mode = transfer` — تحويلٌ محاسبيّ (`transfer_receipt`/`transfer_payment`)
//     ⇒ [createAccountTransferVoucher]: قيدٌ بين حساب الخزينة المختار
//     والمستفيد، بلا حركةِ خزنة.
//   • `mode = standard` — سندٌ نقديّ/شيك بخزنة، ومستفيدُه قد يكون حساباً
//     تفصيليّاً لا طرفاً (`beneficiaryAccount` ⇒ `linkedAccountId`) — نفسُ
//     ما يفعله `TreasuryRepositoryImpl.createReceiptVoucher/createPaymentVoucher`.
//   • ورقةُ دفتر السندات (`bookId` + `bookNumber`) تُفحَص **داخل** معاملة
//     السند بنفس [validateVoucherBookLeaf] — خارجَ المدى أو مكرّرةً أو ملغاة
//     ⇒ `409` ولا يُكتَب شيء — ثمّ تُختَم بـ[assignVoucherBookLeaf].
//   • ختمُ المندوب والخط: يحلّه الخادمُ من خط العميل على الخادم (نفسُ
//     نهج المبيعات) — الـDAO يختم سندَ القبض بـ`stampDocumentRep`.
//
// المعرّفاتُ المحلّيّةُ للعميل لا تُوثَق: الطرفُ والخزنةُ والحساباتُ والدفترُ
// تُحَلّ بـ`globalId` أوّلاً (ثمّ الرمزُ للحساب، ثمّ المعرّف).
//
// Idempotency: الحمولةُ تحمل `globalId` السند؛ إعادةُ الإرسال (إعادةُ
// محاولةٍ أو تصريفُ صندوق الصادر) تعيد الصفَّ القائم ولا تقيّد مرّتين.

import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:shelf/shelf.dart';

import '../../core/permissions/permission_codes.dart';
import '../../data/database/database.dart';
import '../../domain/models/voucher_book.dart';
import '../cheque_receipt_jes.dart';
import 'api_handler_base.dart';
import 'api_user_context.dart';

/// A client account reference `{id, code, globalId}` → the server's account
/// id: globalId, then the chart code (seeded identically on every device),
/// then the raw id. `null` for no reference.
Future<int?> resolveClientAccountId(AppDatabase db, Object? raw) async {
  if (raw is! Map) return null;
  final gid = raw['globalId'] as String?;
  if (gid != null && gid.isNotEmpty) {
    final byGid = await (db.select(db.accounts)
          ..where((a) => a.globalId.equals(gid))
          ..limit(1))
        .getSingleOrNull();
    if (byGid != null) return byGid.id;
  }
  final code = raw['code'] as String?;
  if (code != null && code.isNotEmpty) {
    final byCode = await (db.select(db.accounts)
          ..where((a) => a.code.equals(code))
          ..limit(1))
        .getSingleOrNull();
    if (byCode != null) return byCode.id;
  }
  final id = raw['id'];
  return id is num ? id.toInt() : int.tryParse('${id ?? ''}');
}

class ApiVoucherHandler extends ApiHandlerBase {
  ApiVoucherHandler(super.db, super.wsClients);

  static const _tables = {
    'safe_transactions',
    'safes',
    'parties',
    'journal_entries',
    'accounting',
    'voucher_books',
  };

  /// POST /api/vouchers/receipt
  Future<Response> postReceiptVoucher(Request request) async {
    final perm = await ApiUserCtx.requirePermission(
        request, db, PermissionCodes.treasuryReceiptsCreate);
    if (perm != null) return perm;
    return _post(request, isReceipt: true);
  }

  /// POST /api/vouchers/payment
  Future<Response> postPaymentVoucher(Request request) async {
    final perm = await ApiUserCtx.requirePermission(
        request, db, PermissionCodes.treasuryPaymentsCreate);
    if (perm != null) return perm;
    return _post(request, isReceipt: false);
  }

  Future<Response> _post(Request request, {required bool isReceipt}) async {
    try {
      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: isReceipt ? 'postReceiptVoucher' : 'postPaymentVoucher',
        tables: _tables,
        body: () async {
          final data =
              json.decode(await request.readAsString()) as Map<String, dynamic>;
          final gid = (data['globalId'] as String?)?.trim() ?? '';
          if (gid.isEmpty) {
            return errorResponse('globalId required', statusCode: 400);
          }
          final existing = await _existingVoucher(gid);
          if (existing != null) {
            return jsonResponse({
              'success': true,
              'duplicate': true,
              'serverId': existing,
            });
          }
          try {
            final id = await _write(request, data, gid, isReceipt: isReceipt);
            return jsonResponse({'success': true, 'serverId': id});
          } on VoucherBookException catch (e) {
            return jsonResponse({
              'success': false,
              'error': e.message,
              'voucherBookKey': e.key,
              'voucherBookParams': {
                for (final p in e.params.entries) p.key: p.value?.toString(),
              },
            }, statusCode: 409);
          }
        },
      );
    } catch (e) {
      return errorResponse('Failed to record voucher: $e');
    }
  }

  /// The voucher row already written for [gid] — the plain row, or the
  /// cheque document row (`<gid>-chq`, see `_writeChequeVoucherRow`).
  Future<int?> _existingVoucher(String gid) async {
    final row = await (db.select(db.safeTransactions)
          ..where((t) => t.globalId.isIn([gid, '$gid-chq']))
          ..limit(1))
        .getSingleOrNull();
    return row?.id;
  }

  Future<int> _write(
    Request request,
    Map<String, dynamic> data,
    String gid, {
    required bool isReceipt,
  }) async {
    final userId = ApiUserCtx.userIdOf(request) ??
        await _resolveUser(parseIntNullable(data['userId']),
            data['createdByUsername'] as String?);
    final partyId = await _resolveParty(data);
    final safeId = await _resolveSafe(
        parseIntNullable(data['safeId']), data['safeGlobalId'] as String?);
    final treasuryAccountId = await _resolveAccount(data['treasuryAccount']);
    final beneficiaryAccountId =
        await _resolveAccount(data['beneficiaryAccount']);
    final bookId = await _resolveBook(
        parseIntNullable(data['bookId']), data['bookGlobalId'] as String?);
    final bookNumber = parseIntNullable(data['bookNumber']);
    if (data['bookId'] != null || data['bookGlobalId'] != null) {
      if (bookId == null) {
        throw VoucherBookException('دفتر السندات غير موجود.');
      }
      if (bookNumber == null) {
        throw VoucherBookException('اكتب رقم ورقة الدفتر.');
      }
    }

    final amount = parseDouble(data['amount']);
    final discount = parseDouble(data['discount']);
    final category = data['category'] as String? ?? 'other';
    final description = data['description'] as String?;
    final costCenterId = parseIntNullable(data['costCenterId']);
    final branchId = parseIntNullable(data['branchId']);
    final currencyId = parseIntNullable(data['currencyId']);
    final paymentRate = parseDoubleNullable(data['exchangeRate']);
    final foreignAmount = parseDoubleNullable(data['foreignAmount']);
    final paperType = data['paperType'] as String?;
    final isCheque = paperType == 'cheque' || paperType == 'check';

    return db.transaction(() async {
      // الورقةُ تُفحَص قبل أيّ كتابة — عينُ `preValidateVoucherBookLeaf`.
      if (bookId != null) {
        await db.validateVoucherBookLeaf(bookId, bookNumber!);
      }
      int txnId;
      if (data['mode'] == 'transfer') {
        if (treasuryAccountId == null) {
          throw StateError('treasury account not found on server');
        }
        txnId = await db.createAccountTransferVoucher(
          isReceipt: isReceipt,
          amount: amount,
          treasuryAccountId: treasuryAccountId,
          category: category,
          discount: discount,
          beneficiaryAccountId: beneficiaryAccountId,
          partyId: partyId,
          description: description,
          userId: userId,
          costCenterId: costCenterId,
          documentSafeId: safeId,
          globalId: gid,
          operatingBranchId: branchId,
          currencyId: currencyId,
          paymentRate: paymentRate,
          foreignAmount: foreignAmount,
        );
      } else if (isReceipt) {
        // عينُ `TreasuryRepositoryImpl.createReceiptVoucher`.
        var targetSafeId = safeId ?? 1;
        if (!isCheque && safeId == null) {
          targetSafeId = (await db.getDefaultSafe())?.id ?? targetSafeId;
        }
        txnId = await db.createReceiptVoucher(
          amount: amount,
          category: category,
          discount: discount,
          description: description,
          partyId: partyId,
          safeId: isCheque ? null : targetSafeId,
          userId: userId,
          costCenterId: costCenterId,
          linkedAccountId: beneficiaryAccountId,
          globalId: gid,
          skipJournalEntry: isCheque,
          skipSafeTransaction: isCheque,
          chequeVoucherSafeId: isCheque ? targetSafeId : null,
          operatingBranchId: branchId,
          currencyId: currencyId,
          paymentRate: paymentRate,
          foreignAmount: foreignAmount,
        );
        if (isCheque && discount > 0 && partyId != null) {
          await ChequeReceiptJEs.postDiscountAllowedJournalEntry(
            db: db,
            partyId: partyId,
            discountAmount: discount,
            costCenterId: costCenterId,
          );
        }
      } else {
        // عينُ `TreasuryRepositoryImpl.createPaymentVoucher`.
        int? resolvedSafeId;
        if (!isCheque) {
          resolvedSafeId = safeId ?? (await db.getDefaultSafe())?.id;
        }
        txnId = await db.createPaymentVoucher(
          amount: amount,
          category: category,
          discount: discount,
          description: description,
          partyId: partyId,
          safeId: resolvedSafeId,
          userId: userId,
          costCenterId: costCenterId,
          globalId: gid,
          skipJournalEntry: isCheque,
          skipSafeTransaction: isCheque,
          chequeVoucherSafeId: isCheque ? resolvedSafeId : null,
          linkedAccountId: beneficiaryAccountId,
          operatingBranchId: branchId,
          currencyId: currencyId,
          paymentRate: paymentRate,
          foreignAmount: foreignAmount,
        );
      }
      // عينُ `stampVoucherBookLeaf` — صفرٌ يعني «لا صفَّ سندٍ يُختَم».
      if (bookId != null && txnId > 0) {
        await db.assignVoucherBookLeaf(
            txnId: txnId, bookId: bookId, number: bookNumber!);
      }
      return txnId;
    });
  }

  Future<int?> _resolveUser(int? clientUserId, String? username) async {
    if (clientUserId != null) {
      final byId = await (db.select(db.users)
            ..where((u) => u.id.equals(clientUserId)))
          .getSingleOrNull();
      if (byId != null) return byId.id;
    }
    if (username != null && username.isNotEmpty) {
      final byName = await (db.select(db.users)
            ..where((u) => u.username.equals(username))
            ..limit(1))
          .getSingleOrNull();
      if (byName != null) return byName.id;
    }
    return null;
  }

  Future<int?> _resolveParty(Map<String, dynamic> data) async {
    final clientId = parseIntNullable(data['partyId']);
    final gid = (data['partyGlobalId'] as String?)?.trim();
    if ((clientId == null || clientId <= 0) && (gid == null || gid.isEmpty)) {
      return null;
    }
    final name = (data['partyName'] as String?)?.trim();
    return resolvePartyId(
      clientPartyId: clientId,
      partyGlobalId: gid == null || gid.isEmpty ? null : gid,
      fallbackName: name == null || name.isEmpty ? null : name,
    );
  }

  Future<int?> _resolveSafe(int? clientId, String? gid) async {
    if (gid != null && gid.isNotEmpty) {
      final byGid = await (db.select(db.safes)
            ..where((s) => s.globalId.equals(gid))
            ..limit(1))
          .getSingleOrNull();
      if (byGid != null) return byGid.id;
    }
    return clientId;
  }

  Future<int?> _resolveAccount(Object? raw) => resolveClientAccountId(db, raw);

  Future<int?> _resolveBook(int? clientId, String? gid) async {
    if (gid != null && gid.isNotEmpty) {
      final row = await db.customSelect(
        'SELECT id FROM voucher_books WHERE global_id = ? LIMIT 1',
        variables: [drift.Variable<String>(gid)],
      ).getSingleOrNull();
      if (row != null) return (row.data['id'] as num).toInt();
    }
    return clientId;
  }
}
