import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'cart_controller.dart';
import '../../../services/cfd_service.dart';

/// Controller to bridge the POS Cart state with the CFD SSE Service.
/// It listens to the CartController and triggers a broadcast on every change.
class CfdController extends Notifier<void> {
  @override
  void build() {
    // Listen to cart state changes
    ref.listen(cartControllerProvider, (previous, next) {
      if (next.items.isEmpty) {
        CfdService.instance.broadcastIdle();
      } else {
        CfdService.instance.broadcastCart(next);
      }
    });

    // Cleanup logic if needed
    ref.onDispose(() {
      // We don't want to dispose the singleton CfdService here
      // as other controllers might still need it.
    });
  }
}

/// Provider to initialize and maintain the CFD bridge.
/// Should be watched by a top-level widget in POS or AppShell.
final cfdControllerProvider = NotifierProvider<CfdController, void>(
  CfdController.new,
);
