import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../data/providers/auth_providers.dart';
import '../../../../domain/entities/product_entity.dart';
import '../../../products/providers/products_controller.dart';
import '../../../../data/providers/repository_providers.dart';

class ProductDeleteDialog extends ConsumerStatefulWidget {
  final ProductEntity product;

  const ProductDeleteDialog({super.key, required this.product});

  @override
  ConsumerState<ProductDeleteDialog> createState() =>
      _ProductDeleteDialogState();
}

class _ProductDeleteDialogState extends ConsumerState<ProductDeleteDialog> {
  final confirmController = TextEditingController();

  @override
  void dispose() {
    confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canDelete = confirmController.text == widget.product.name;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Row(
          children: [
            Icon(PhosphorIconsBold.warning, color: AppColors.error),
            SizedBox(width: 8),
            Text('⚠️ تحذير: حذف صنف'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.error),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(PhosphorIconsBold.warning, color: AppColors.error),
                        SizedBox(width: 8),
                        Text(
                          'هذا الإجراء لا يمكن التراجع عنه!',
                          style: TextStyle(
                            color: AppColors.error,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    Text(
                      'حذف الصنف سيؤدي إلى:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text('• إلغاء تفعيل الصنف من القوائم'),
                    Text('• عدم ظهوره في نقطة البيع'),
                    Text('• الاحتفاظ ببيانات الفواتير السابقة'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'الصنف المراد حذفه: "${widget.product.name}"',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text('للتأكيد، اكتب اسم الصنف بالضبط:'),
              const SizedBox(height: 8),
              TextField(
                controller: confirmController,
                decoration: InputDecoration(
                  hintText: widget.product.name,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  suffixIcon: canDelete
                      ? const Icon(
                          PhosphorIconsBold.checkCircle,
                          color: AppColors.success,
                        )
                      : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: canDelete ? AppColors.error : Colors.grey,
            ),
            onPressed: canDelete
                ? () async {
                    final deleted = await ref
                        .read(productsControllerProvider.notifier)
                        .deleteProduct(widget.product.id);

                    if (deleted) {
                      try {
                        final repository = ref.read(productRepositoryProvider);
                        final user = ref.read(authProvider).user;
                        await repository.logActivity(
                          userId: user?.id,
                          userName: user?.displayName ?? 'مجهول',
                          action: 'delete_product',
                          entityId: widget.product.id,
                          description: 'حذف صنف: ${widget.product.name}',
                        );
                      } catch (e) {
                        debugPrint('[ActivityLog] Error: $e');
                      }
                    }

                    if (context.mounted) {
                      Navigator.pop(context);
                      AppToast.show(
                        context,
                        deleted ? 'تم حذف الصنف' : 'فشل حذف الصنف',
                        type: deleted ? ToastType.warning : ToastType.error,
                      );
                    }
                  }
                : null,
            child: const Text('🗑️ حذف نهائي'),
          ),
        ],
      ),
    );
  }
}
