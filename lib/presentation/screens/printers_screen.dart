import 'package:flutter/material.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/shimmer_loading.dart';

import '../../data/providers/providers.dart';

/// Printers Management Screen
/// Allows adding, editing, and managing work order printers
class PrintersScreen extends ConsumerStatefulWidget {
  const PrintersScreen({super.key});

  @override
  ConsumerState<PrintersScreen> createState() => _PrintersScreenState();
}

class _PrintersScreenState extends ConsumerState<PrintersScreen> {
  @override
  Widget build(BuildContext context) {
    final printersAsync = ref.watch(allPrintersProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Row(
          children: [
            Icon(PhosphorIconsBold.printer),
            SizedBox(width: 8),
            Text('إدارة الطابعات'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(PhosphorIconsBold.plus),
            onPressed: () => _showPrinterDialog(null),
            tooltip: 'إضافة طابعة',
          ),
        ],
      ),
      body: printersAsync.when(
        data: (printers) => printers.isEmpty
            ? _buildEmptyState()
            : _buildPrintersList(printers, theme),
        loading: () => Padding(
          padding: const EdgeInsets.all(16),
          child: ShimmerLoading.list(itemCount: 4),
        ),
        error: (e, _) => Center(child: Text('خطأ: $e')),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(PhosphorIconsLight.printer, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'لا توجد طابعات',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'أضف طابعات لتوزيع أوامر الشغل على أقسام مختلفة',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _showPrinterDialog(null),
            icon: const Icon(PhosphorIconsBold.plus),
            label: const Text('إضافة طابعة'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrintersList(List<Printer> printers, ThemeData theme) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: printers.length,
      itemBuilder: (context, index) {
        final printer = printers[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: printer.isActive
                  ? AppColors.primary.withValues(alpha: 0.15)
                  : Colors.grey.withValues(alpha: 0.15),
              child: Icon(
                printer.printerType == 'network'
                    ? PhosphorIconsBold.wifiHigh
                    : printer.printerType == 'usb'
                    ? PhosphorIconsBold.plug
                    : PhosphorIconsBold.printer,
                color: printer.isActive ? AppColors.primary : Colors.grey,
              ),
            ),
            title: Text(
              printer.name,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: printer.isActive ? null : Colors.grey,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (printer.port != null && printer.port!.isNotEmpty)
                  Text('منفذ: ${printer.port}'),
                if (printer.ipAddress != null && printer.ipAddress!.isNotEmpty)
                  Text(
                    'IP: ${printer.ipAddress}:${printer.portNumber ?? 9100}',
                  ),
                if (printer.description != null &&
                    printer.description!.isNotEmpty)
                  Text(
                    printer.description!,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Status indicator
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: printer.isActive
                        ? Colors.green.withValues(alpha: 0.15)
                        : Colors.grey.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    printer.isActive ? 'نشط' : 'معطل',
                    style: TextStyle(
                      fontSize: 12,
                      color: printer.isActive ? Colors.green : Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Edit button
                IconButton(
                  icon: const Icon(
                    PhosphorIconsBold.pencil,
                    color: AppColors.primary,
                  ),
                  onPressed: () => _showPrinterDialog(printer),
                  tooltip: 'تعديل',
                ),
                // Delete button
                IconButton(
                  icon: const Icon(PhosphorIconsBold.trash, color: Colors.red),
                  onPressed: () => _confirmDelete(printer),
                  tooltip: 'حذف',
                ),
              ],
            ),
            isThreeLine: true,
          ),
        );
      },
    );
  }

  Future<void> _showPrinterDialog(Printer? printer) async {
    final isEditing = printer != null;
    final nameController = TextEditingController(text: printer?.name ?? '');
    final portController = TextEditingController(text: printer?.port ?? '');
    final ipController = TextEditingController(text: printer?.ipAddress ?? '');
    final portNumberController = TextEditingController(
      text: printer?.portNumber?.toString() ?? '9100',
    );
    final descriptionController = TextEditingController(
      text: printer?.description ?? '',
    );
    String printerType = printer?.printerType ?? 'thermal';
    String printerPurpose = printer?.purpose ?? 'pos_receipt';
    bool isActive = printer?.isActive ?? true;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(
                isEditing ? PhosphorIconsBold.pencil : PhosphorIconsBold.plus,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Text(isEditing ? 'تعديل طابعة' : 'إضافة طابعة جديدة'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Printer name
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'اسم الطابعة *',
                    hintText: 'مثال: طابعة المطبخ',
                    prefixIcon: Icon(PhosphorIconsLight.tag),
                  ),
                ),
                const SizedBox(height: 16),

                // Printer purpose
                const Text(
                  'الغرض من الطابعة:',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: printerPurpose,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(PhosphorIconsLight.target),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'pos_receipt',
                      child: Text('إيصال نقطة البيع'),
                    ),
                    DropdownMenuItem(
                      value: 'kitchen',
                      child: Text('طابعة المطبخ'),
                    ),
                    DropdownMenuItem(
                      value: 'tables',
                      child: Text('طابعة الطاولات'),
                    ),
                    DropdownMenuItem(
                      value: 'barcode',
                      child: Text('طابعة الباركود'),
                    ),
                  ],
                  onChanged: (v) =>
                      setDialogState(() => printerPurpose = v ?? 'pos_receipt'),
                ),
                const SizedBox(height: 16),

                // Printer type
                const Text(
                  'نوع الاتصال:',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(PhosphorIconsBold.plug, size: 16),
                          SizedBox(width: 4),
                          Text('USB'),
                        ],
                      ),
                      selected: printerType == 'usb',
                      onSelected: (selected) {
                        if (selected) setDialogState(() => printerType = 'usb');
                      },
                      selectedColor: AppColors.primary.withValues(alpha: 0.2),
                    ),
                    ChoiceChip(
                      label: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(PhosphorIconsBold.plugsConnected, size: 16),
                          SizedBox(width: 4),
                          Text('COM'),
                        ],
                      ),
                      selected: printerType == 'thermal',
                      onSelected: (selected) {
                        if (selected) {
                          setDialogState(() => printerType = 'thermal');
                        }
                      },
                      selectedColor: AppColors.primary.withValues(alpha: 0.2),
                    ),
                    ChoiceChip(
                      label: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(PhosphorIconsBold.wifiHigh, size: 16),
                          SizedBox(width: 4),
                          Text('شبكة'),
                        ],
                      ),
                      selected: printerType == 'network',
                      onSelected: (selected) {
                        if (selected) {
                          setDialogState(() => printerType = 'network');
                        }
                      },
                      selectedColor: AppColors.primary.withValues(alpha: 0.2),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // USB printer name (for USB type)
                if (printerType == 'usb')
                  TextField(
                    controller: portController,
                    decoration: const InputDecoration(
                      labelText: 'اسم الطابعة في النظام',
                      hintText: 'اختر من طابعات Windows',
                      prefixIcon: Icon(PhosphorIconsLight.plug),
                      helperText: 'اسم الطابعة كما يظهر في إعدادات الطابعات',
                    ),
                  ),

                // COM port (for thermal)
                if (printerType == 'thermal')
                  TextField(
                    controller: portController,
                    decoration: const InputDecoration(
                      labelText: 'منفذ COM',
                      hintText: 'مثال: COM3',
                      prefixIcon: Icon(PhosphorIconsLight.plugsConnected),
                    ),
                  ),

                // Network settings
                if (printerType == 'network') ...[
                  TextField(
                    controller: ipController,
                    decoration: const InputDecoration(
                      labelText: 'عنوان IP',
                      hintText: 'مثال: 192.168.1.100',
                      prefixIcon: Icon(PhosphorIconsLight.wifiHigh),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: portNumberController,
                    decoration: const InputDecoration(
                      labelText: 'رقم المنفذ',
                      hintText: '9100',
                      prefixIcon: Icon(PhosphorIconsLight.hash),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ],

                const SizedBox(height: 16),

                // Description
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'وصف (اختياري)',
                    hintText: 'مثال: للأطعمة الساخنة',
                    prefixIcon: Icon(PhosphorIconsLight.noteBlank),
                  ),
                  maxLines: 2,
                ),

                const SizedBox(height: 16),

                // Active toggle
                SwitchListTile(
                  title: const Text('طابعة نشطة'),
                  subtitle: const Text(
                    'تعطيل الطابعة يوقفها مؤقتاً عن الطباعة',
                  ),
                  value: isActive,
                  onChanged: (v) => setDialogState(() => isActive = v),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton.icon(
              onPressed: () => _savePrinter(
                printer: printer,
                name: nameController.text,
                port: portController.text,
                ipAddress: ipController.text,
                portNumber: int.tryParse(portNumberController.text),
                printerType: printerType,
                purpose: printerPurpose,
                description: descriptionController.text,
                isActive: isActive,
              ),
              icon: Icon(
                isEditing
                    ? PhosphorIconsBold.floppyDisk
                    : PhosphorIconsBold.plus,
              ),
              label: Text(isEditing ? 'حفظ' : 'إضافة'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _savePrinter({
    Printer? printer,
    required String name,
    String? port,
    String? ipAddress,
    int? portNumber,
    required String printerType,
    required String purpose,
    String? description,
    required bool isActive,
  }) async {
    if (name.trim().isEmpty) {
      AppToast.show(context, 'يجب إدخال اسم الطابعة', type: ToastType.error);
      return;
    }

    final repo = ref.read(printersRepositoryProvider);
    final nav = Navigator.of(context);

    try {
      if (printer != null) {
        // Update existing
        await repo.updatePrinter(
          id: printer.id,
          name: name.trim(),
          port: port?.isNotEmpty == true ? port : null,
          ipAddress: ipAddress?.isNotEmpty == true ? ipAddress : null,
          portNumber: portNumber,
          printerType: printerType,
          purpose: purpose,
          description: description?.isNotEmpty == true ? description : null,
          isActive: isActive,
        );
        final user = ref.read(authProvider).user;
        final activityLogRepo = ref.read(activityLogRepositoryProvider);
        await activityLogRepo.logActivity(
          userId: user?.id,
          userName: user?.displayName ?? 'مجهول',
          action: 'update_printer',
          entityType: 'printer',
          entityId: printer.id,
          description: 'تعديل طابعة: ${name.trim()} ($purpose)',
          oldValue: printer.name,
          newValue: name.trim(),
        );
      } else {
        // Insert new
        await repo.insertPrinter(
          name: name.trim(),
          port: port?.isNotEmpty == true ? port : null,
          ipAddress: ipAddress?.isNotEmpty == true ? ipAddress : null,
          portNumber: portNumber,
          printerType: printerType,
          purpose: purpose,
          description: description?.isNotEmpty == true ? description : null,
        );
        final user = ref.read(authProvider).user;
        final activityLogRepo = ref.read(activityLogRepositoryProvider);
        await activityLogRepo.logActivity(
          userId: user?.id,
          userName: user?.displayName ?? 'مجهول',
          action: 'add_printer',
          entityType: 'printer',
          description: 'إضافة طابعة: ${name.trim()} ($purpose)',
        );
      }

      nav.pop();
      if (mounted) {
        AppToast.show(
          context,
          printer != null ? 'تم تحديث الطابعة' : 'تم إضافة الطابعة',
          type: ToastType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'خطأ: $e', type: ToastType.error);
      }
    }
  }

  Future<void> _confirmDelete(Printer printer) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(PhosphorIconsBold.warning, color: Colors.orange),
            SizedBox(width: 8),
            Text('تأكيد الحذف'),
          ],
        ),
        content: Text(
          'هل تريد حذف الطابعة "${printer.name}"؟\n\nسيتم إلغاء ربطها بجميع التصنيفات.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final repo = ref.read(printersRepositoryProvider);
      await repo.deletePrinter(printer.id);
      final user = ref.read(authProvider).user;
      final activityLogRepo = ref.read(activityLogRepositoryProvider);
      await activityLogRepo.logActivity(
        userId: user?.id,
        userName: user?.displayName ?? 'مجهول',
        action: 'delete_printer',
        entityType: 'printer',
        entityId: printer.id,
        description: 'حذف طابعة: ${printer.name}',
      );
      if (mounted) {
        AppToast.show(context, 'تم حذف الطابعة', type: ToastType.success);
      }
    }
  }
}
