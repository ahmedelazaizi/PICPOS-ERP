import 'package:flutter/material.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../../../../data/database/database.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class InvoiceDesignerToolbar extends StatelessWidget {
  final Function(String type) onAddElement;
  final VoidCallback onSave;
  final VoidCallback onPreview;
  final VoidCallback onReset;
  final InvoiceTemplate? currentTemplate;
  final String currentLanguage;
  final Function(String) onLanguageChanged;

  const InvoiceDesignerToolbar({
    super.key,
    required this.onAddElement,
    required this.onSave,
    required this.onPreview,
    required this.onReset,
    this.currentTemplate,
    this.currentLanguage = 'ar',
    required this.onLanguageChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border(bottom: BorderSide(color: context.picposHairline)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Text(
            'محرر القوالب',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 16),

          const Spacer(),

          // Actions Group
          if (currentTemplate != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Chip(
                label: Text('جاري تعديل: ${currentTemplate!.name}'),
                backgroundColor: Colors.blue.shade50,
                side: BorderSide.none,
              ),
            ),

          // Language toggle
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: currentLanguage,
                isDense: true,
                icon: const Icon(PhosphorIconsBold.translate, size: 16),
                items: const [
                  DropdownMenuItem(value: 'ar', child: Text('عربي')),
                  DropdownMenuItem(value: 'en', child: Text('English')),
                ],
                onChanged: (val) {
                  if (val != null) onLanguageChanged(val);
                },
              ),
            ),
          ),

          _buildActionButton(
            icon: PhosphorIconsBold.eye,
            label: 'معاينة',
            onTap: onPreview,
            color: Colors.purple,
          ),
          const SizedBox(width: 8),
          _buildActionButton(
            icon: PhosphorIconsBold.arrowCounterClockwise,
            label: 'إعادة ضبط',
            onTap: onReset,
            color: Colors.orange,
          ),
          const SizedBox(width: 8),
          _buildActionButton(
            icon: PhosphorIconsBold.floppyDisk,
            label: 'حفظ القالب',
            onTap: onSave,
            color: Colors.green,
            isPrimary: true,
          ),
        ],
      ),
    );
  }



  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color color,
    bool isPrimary = false,
  }) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: isPrimary ? Colors.white : color),
      label: Text(
        label,
        style: TextStyle(color: isPrimary ? Colors.white : color),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: isPrimary ? color : Colors.white,
        side: isPrimary ? null : BorderSide(color: color),
        elevation: isPrimary ? 2 : 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    );
  }
}
