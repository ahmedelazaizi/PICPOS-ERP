part of '../client_write_interceptor.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Trading module — Sales · Inventory · Commercial Papers · Safe Operations
//                  Stock Transfers · Purchase Auto-Push
//
// Part of the ClientWriteInterceptor library.
// ═══════════════════════════════════════════════════════════════════════════

/// شكل الـpayload المخزّن في الطابور لتحويل بين الخزائن.
///
/// ── ليه دالة منفصلة ─────────────────────────────────────────────────────────
/// الـ`globalId` لازم يكون **جزء من الـpayload** مش يتولّد وقت الإرسال: إعادة
/// الإرسال من الطابور بتقرا نفس الـpayload المخزّن، فلو الـid بيتولّد في كل
/// محاولة كانت كل واحدة هتاخد قيمة جديدة والـdedup بلا معنى. ده جوهر الفرق
/// بين «مفتاح idempotency» و«هوية العملية».
@visibleForTesting
Map<String, dynamic> safeTransferPayload({
  required int fromSafeId,
  required int toSafeId,
  required double amount,
  int? userId,
  String? description,
  required String globalId,
}) =>
    {
      'fromSafeId': fromSafeId,
      'toSafeId': toSafeId,
      'amount': amount,
      'userId': userId,
      'description': description,
      'globalId': globalId,
    };

