import '../../entities/cart_item_entity.dart';

/// Use case for removing item from cart
///
/// Pure business logic
class RemoveFromCartUseCase {
  /// Execute the use case
  ///
  /// Returns updated cart list with the item removed
  List<CartItemEntity> execute({
    required List<CartItemEntity> currentCart,
    required int index,
  }) {
    if (index < 0 || index >= currentCart.length) {
      return currentCart;
    }

    return [
      ...currentCart.sublist(0, index),
      ...currentCart.sublist(index + 1),
    ];
  }
}

/// Use case for updating cart item quantity
class UpdateCartQuantityUseCase {
  /// Execute the use case
  List<CartItemEntity> execute({
    required List<CartItemEntity> currentCart,
    required int index,
    required double newQuantity,
  }) {
    if (index < 0 || index >= currentCart.length) {
      return currentCart;
    }

    if (newQuantity <= 0) {
      // Remove item if quantity is zero or negative
      return RemoveFromCartUseCase().execute(
        currentCart: currentCart,
        index: index,
      );
    }

    final updated = currentCart[index].copyWith(quantity: newQuantity);

    return [
      ...currentCart.sublist(0, index),
      updated,
      ...currentCart.sublist(index + 1),
    ];
  }
}

/// Use case for updating cart item price
class UpdateCartPriceUseCase {
  /// Execute the use case
  List<CartItemEntity> execute({
    required List<CartItemEntity> currentCart,
    required int index,
    required double newPrice,
  }) {
    if (index < 0 || index >= currentCart.length) {
      return currentCart;
    }

    final updated = currentCart[index].copyWith(customPrice: newPrice);

    return [
      ...currentCart.sublist(0, index),
      updated,
      ...currentCart.sublist(index + 1),
    ];
  }
}

/// Use case for clearing cart
class ClearCartUseCase {
  /// Execute the use case
  List<CartItemEntity> execute() => [];
}
