import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../../../data/providers/providers.dart';
import '../../entities/cart_item_entity.dart';
import '../../../presentation/pos/widgets/modifier_selection_dialog.dart';

/// Request payload for holding an order
class HoldOrderRequest {
  final List<CartItemEntity> items;
  final double subtotal;
  final double discountPercent;
  final int? customerId;
  final String? customerName;

  HoldOrderRequest({
    required this.items,
    required this.subtotal,
    required this.discountPercent,
    this.customerId,
    this.customerName,
  });
}

/// Response payload when retrieving a held order
class RetrieveHeldOrderResponse {
  final List<CartItemEntity> items;
  final int? customerId;
  final String? customerName;
  final double discountPercent;

  RetrieveHeldOrderResponse({
    required this.items,
    required this.discountPercent,
    this.customerId,
    this.customerName,
  });
}

/// A use case that encapsulates all logic related to holding, retrieving, and discarding
/// suspended POS orders (a.k.a. Held Orders) including database I/O and activity logging.
class HoldOrderUseCase {
  final Ref _ref;

  HoldOrderUseCase(this._ref);

  /// Suspend the active cart into the database
  Future<String?> executeHold(HoldOrderRequest request) async {
    if (request.items.isEmpty) return null;

    final db = _ref.read(databaseProvider);
    try {
      final now = DateTime.now();
      final holdNum =
          'H${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';

      final items = request.items
          .map(
            (item) => {
              'productId': item.productId,
              'quantity': item.quantity,
              'unitPrice': item.unitPrice,
              'customPrice': item.customPrice,
              'note': _serializeCartItemMeta(item),
            },
          )
          .toList();

      await db.createHeldOrder(
        holdNumber: holdNum,
        subtotal: request.subtotal,
        discount: request.discountPercent,
        discountIsPercent: true,
        customerId: request.customerId,
        customerName: request.customerName,
        items: items,
      );

      // Log held order creation
      try {
        final authState = _ref.read(authProvider);
        final activityLogRepo = _ref.read(activityLogRepositoryProvider);
        await activityLogRepo.logActivity(
          userId: authState.user?.id,
          userName: authState.user?.displayName ?? 'Unknown',
          action: 'hold_order',
          entityType: 'held_order',
          description: 'تعليق طلب $holdNum — ${request.items.length} أصناف',
          amount: request.subtotal,
        );
      } catch (e) {
        AppLogger.instance.warning('hold_order: activity log failed (non-critical): $e');
      }

      return holdNum;
    } catch (e) {
      AppLogger.instance.error('Failed to hold order', e, null, 'CART');
      return null;
    }
  }

  /// Retrieve held order
  Future<RetrieveHeldOrderResponse?> executeRetrieve(int id) async {
    final db = _ref.read(databaseProvider);
    try {
      final order = await db.getHeldOrderById(id);
      if (order != null) {
        final items = await db.getHeldOrderItems(id);

        final List<CartItemEntity> cartItems = [];
        for (final item in items) {
          final product = await db.getProductById(item.productId);
          if (product != null) {
            // Deserialize modifiers + itemNote from stored note
            final meta = _deserializeCartItemMeta(item.note);
            cartItems.add(
              CartItemEntity(
                productId: product.id,
                categoryId: product.categoryId,
                productName: product.name,
                productCode: product.code,
                barcode: product.barcode,
                unitPrice: item.unitPrice,
                quantity: item.quantity,
                customPrice: item.customPrice,
                isSoldByWeight: product.isSoldByWeight,
                itemNote: meta['itemNote'] as String?,
                note: meta['note'] as String?,
                modifiers: meta['modifiers'] as List<SelectedModifier>,
                // الطلباتُ المعلَّقة قبل هذا التغيير ما فيهاش المفاتيح دي،
                // فتقرأ `null` وترجع للافتراض — نفسُ سلوكها القديم بالضبط.
                discountPercent: (meta['discountPercent'] as double?) ?? 0,
                taxRate: (meta['taxRate'] as double?) ?? 0,
                selectedUnitId: meta['unitId'] as int?,
                selectedUnitName: meta['unitName'] as String?,
                quantityInBase: (meta['quantityInBase'] as double?) ?? 1.0,
              ),
            );
          }
        }

        // Log held order retrieval
        try {
          final authState = _ref.read(authProvider);
          final activityLogRepo = _ref.read(activityLogRepositoryProvider);
          await activityLogRepo.logActivity(
            userId: authState.user?.id,
            userName: authState.user?.displayName ?? 'Unknown',
            action: 'retrieve_held_order',
            entityType: 'held_order',
            entityId: id,
            description:
                'استرجاع طلب معلق ${order.holdNumber} — ${cartItems.length} أصناف',
            amount: order.subtotal,
          );
        } catch (e) {
          AppLogger.instance.warning('retrieve_held_order: activity log failed (non-critical): $e');
        }

        // Delete the held order after retrieval
        await db.deleteHeldOrder(id);

        return RetrieveHeldOrderResponse(
          items: cartItems,
          customerId: order.customerId,
          customerName: order.customerName,
          discountPercent: order.discount,
        );
      }
    } catch (e) {
      AppLogger.instance.error('Failed to retrieve held order: $e');
    }
    return null;
  }

  /// Delete held order permanently
  Future<void> executeDelete(int id) async {
    final db = _ref.read(databaseProvider);
    try {
      await db.deleteHeldOrder(id);

      // Log held order deletion
      try {
        final authState = _ref.read(authProvider);
        final activityLogRepo = _ref.read(activityLogRepositoryProvider);
        await activityLogRepo.logActivity(
          userId: authState.user?.id,
          userName: authState.user?.displayName ?? 'Unknown',
          action: 'delete_held_order',
          entityType: 'held_order',
          entityId: id,
          description: 'حذف طلب معلق #$id',
        );
      } catch (e) {
        AppLogger.instance.warning('delete_held_order: activity log failed (non-critical): $e');
      }
    } catch (e) {
      AppLogger.instance.error('Failed to delete held order: $e');
    }
  }
}

final holdOrderUseCaseProvider = Provider<HoldOrderUseCase>((ref) {
  // Pass ref.read to interact with providers dynamically without holding a specific ref cycle
  return HoldOrderUseCase(ref);
});

// ─── Serialization Helpers ───

/// Serialize modifiers + itemNote into a JSON string for storage in held order note field
String? _serializeCartItemMeta(CartItemEntity item) {
  final hasNote = item.note != null && item.note!.isNotEmpty;
  // ⚠️ الحمولةُ كانت تحفظ productId/quantity/unitPrice/customPrice فقط، فترجع
  // كرتونةٌ (×١٢) بخصم ١٠٪ «قطعةً واحدة بلا خصم»: العميل يدفع ٥٠ بدل ٤٥،
  // ويخرج ١٢ صنفاً بينما المخزون ينزل **واحداً**. مقيس.
  //
  // فالحقولُ المالية تُرحَّل حتى لو ما فيش ملاحظاتٌ ولا إضافات — وإلا تسلسل
  // السطرُ `null` وضاع خصمُه وتحويلُ وحدته معاً.
  final hasMoneyMeta = item.discountPercent != 0 ||
      item.taxRate != 0 ||
      item.selectedUnitId != null ||
      item.quantityInBase != 1;
  if (item.modifiers.isEmpty &&
      (item.itemNote == null || item.itemNote!.isEmpty) &&
      !hasNote &&
      !hasMoneyMeta) {
    return null;
  }
  final data = <String, dynamic>{};
  // JSON حرٌّ فلا هجرةَ ولا كسرَ للطلبات المعلَّقة القديمة: المفتاحُ الغائب
  // يُقرأ `null` ⇒ نفسُ السلوك السابق بالضبط.
  if (item.discountPercent != 0) data['discountPercent'] = item.discountPercent;
  if (item.taxRate != 0) data['taxRate'] = item.taxRate;
  if (item.selectedUnitId != null) data['unitId'] = item.selectedUnitId;
  if (item.selectedUnitName != null) data['unitName'] = item.selectedUnitName;
  if (item.quantityInBase != 1) data['quantityInBase'] = item.quantityInBase;
  if (item.itemNote != null && item.itemNote!.isNotEmpty) {
    data['itemNote'] = item.itemNote;
  }
  // `note` المركّب لازم يترحّل كما هو. كان **مش متسلسل خالص**، بينما
  // `customPrice` بيتحفظ — فسطر العرض اليدوي كان يرجع بسعر العرض وبملاحظة
  // فاضية، أي «سطر أساس رخيص» في عين كل فلاتر العروض ⇒ يتعدّ ككمية مؤهّلة
  // ويتخصم فوق خصمه، والجولة اللي بعدها ترجّعه لسعر الأساس.
  // وبيخسّر كمان لافتة الإضافات اللي تذكرة المطبخ بتقراها من `item.note`.
  if (hasNote) {
    data['note'] = item.note;
  }
  if (item.modifiers.isNotEmpty) {
    data['modifiers'] = item.modifiers.map((m) => {
      'id': m.itemId,
      'name': m.itemName,
      'group': m.groupName,
      'price': m.extraPrice,
      'opt': m.isOption,
      'ql': m.quantityLevel.code,
    }).toList();
  }
  return jsonEncode(data);
}

/// Deserialize modifiers + itemNote from stored JSON note
Map<String, dynamic> _deserializeCartItemMeta(String? note) {
  final result = <String, dynamic>{
    'itemNote': null,
    'note': null,
    'modifiers': <SelectedModifier>[],
    'discountPercent': null,
    'taxRate': null,
    'unitId': null,
    'unitName': null,
    'quantityInBase': null,
  };
  if (note == null || note.isEmpty) return result;

  try {
    final data = jsonDecode(note) as Map<String, dynamic>;
    result['itemNote'] = data['itemNote'] as String?;
    // غايب في الطلبات المعلّقة القديمة ⇒ null ⇒ نفس السلوك القديم بالظبط.
    result['note'] = data['note'] as String?;
    result['discountPercent'] = (data['discountPercent'] as num?)?.toDouble();
    result['taxRate'] = (data['taxRate'] as num?)?.toDouble();
    result['unitId'] = data['unitId'] as int?;
    result['unitName'] = data['unitName'] as String?;
    result['quantityInBase'] = (data['quantityInBase'] as num?)?.toDouble();
    if (data['modifiers'] != null) {
      result['modifiers'] = (data['modifiers'] as List).map<SelectedModifier>((m) {
        final map = m as Map<String, dynamic>;
        return SelectedModifier(
          itemId: map['id'] as int,
          itemName: map['name'] as String,
          groupName: map['group'] as String,
          extraPrice: (map['price'] as num).toDouble(),
          isOption: map['opt'] as bool? ?? false,
          quantityLevel: OptionQuantityLevelX.fromCode(map['ql'] as String? ?? ''),
        );
      }).toList();
    }
  } catch (_) {
    // If note is plain text (old format), treat it as itemNote
    result['itemNote'] = note;
  }
  return result;
}
