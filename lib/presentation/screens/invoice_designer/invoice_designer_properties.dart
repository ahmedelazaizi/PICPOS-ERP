import 'package:ural_erp/core/theme/app_colors.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../picpos_shell/picpos_surface.dart';
import 'package:drift/drift.dart' show Value;
import '../../../../data/database/database.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class InvoiceDesignerProperties extends StatefulWidget {
  final InvoiceTemplateElement? selectedElement;
  final Function(InvoiceTemplateElement) onUpdate;
  final VoidCallback onDelete;
  final InvoiceTableSetting? tableSettings; // For table properties
  final Function(InvoiceTableSetting)? onUpdateTable; // For table update

  const InvoiceDesignerProperties({
    super.key,
    this.selectedElement,
    required this.onUpdate,
    required this.onDelete,
    this.tableSettings,
    this.onUpdateTable,
  });

  @override
  State<InvoiceDesignerProperties> createState() =>
      _InvoiceDesignerPropertiesState();
}

class _InvoiceDesignerPropertiesState extends State<InvoiceDesignerProperties> {
  // Controllers
  late TextEditingController _contentController;
  late TextEditingController _xController;
  late TextEditingController _yController;
  late TextEditingController _widthController;
  late TextEditingController _heightController;
  late TextEditingController _fontSizeController;

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  @override
  void didUpdateWidget(covariant InvoiceDesignerProperties oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedElement != oldWidget.selectedElement ||
        widget.tableSettings != oldWidget.tableSettings) {
      _initControllers();
    }
  }

  void _initControllers() {
    if (widget.selectedElement != null) {
      final e = widget.selectedElement!;
      _contentController = TextEditingController(text: e.content);
      _xController = TextEditingController(
        text: e.xPosition.toStringAsFixed(1),
      );
      _yController = TextEditingController(
        text: e.yPosition.toStringAsFixed(1),
      );
      _widthController = TextEditingController(
        text: e.width.toStringAsFixed(1),
      );
      _heightController = TextEditingController(
        text: e.height.toStringAsFixed(1),
      );
      _fontSizeController = TextEditingController(
        text: e.fontSize.toStringAsFixed(1),
      );
    } else if (widget.tableSettings != null) {
      // Initialize table specific controllers if needed
      final t = widget.tableSettings!;
      _xController = TextEditingController(
        text: t.xPosition.toStringAsFixed(1),
      );
      _yController = TextEditingController(
        text: t.yPosition.toStringAsFixed(1),
      );
      _widthController = TextEditingController(
        text: t.width.toStringAsFixed(1),
      );
      _contentController = TextEditingController(); // Not used for table
      _heightController = TextEditingController(); // Not used directly
      _fontSizeController = TextEditingController(
        text: t.fontSize.toStringAsFixed(1),
      );
    } else {
      _contentController = TextEditingController();
      _xController = TextEditingController();
      _yController = TextEditingController();
      _widthController = TextEditingController();
      _heightController = TextEditingController();
      _fontSizeController = TextEditingController();
    }
  }

  @override
  void dispose() {
    _contentController.dispose();
    _xController.dispose();
    _yController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    _fontSizeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.selectedElement == null && widget.tableSettings == null) {
      return Container(
        width: 300,
        padding: const EdgeInsets.all(16),
        color: Colors.grey.shade50,
        child: const Center(
          child: Text(
            'اختر عنصراً للتعديل',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    // Determine if we are editing an Element or Table Settings
    final isTable =
        widget.selectedElement == null && widget.tableSettings != null;

    return Container(
      width: 300,
      color: Colors.grey.shade50,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.picposCard,
              border: Border(bottom: BorderSide(color: context.picposHairline)),
            ),
            child: Row(
              children: [
                Icon(
                  isTable ? PhosphorIconsBold.table : PhosphorIconsBold.gear,
                  color: Colors.blue,
                ),
                const SizedBox(width: 8),
                Text(
                  isTable ? 'خصائص الجدول' : 'خصائص العنصر',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                if (!isTable)
                  IconButton(
                    icon: const Icon(
                      PhosphorIconsBold.trash,
                      color: AppColors.error,
                    ),
                    onPressed: widget.onDelete,
                    tooltip: 'حذف العنصر',
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (!isTable &&
                    widget.selectedElement!.elementType != 'variable' &&
                    widget.selectedElement!.elementType != 'line' &&
                    widget.selectedElement!.elementType != 'rectangle')
                  _buildTextField('المحتوى', _contentController, (val) {
                    widget.onUpdate(
                      widget.selectedElement!.copyWith(content: Value(val)),
                    );
                  }),

                if (!isTable &&
                    widget.selectedElement!.elementType == 'variable')
                  _buildGroupedVariableDropdown(
                    'المتغير',
                    widget.selectedElement!.content ?? 'invoice_number',
                    (val) {
                      if (val != null) {
                        widget.onUpdate(
                          widget.selectedElement!.copyWith(content: Value(val)),
                        );
                      }
                    },
                  ),

                const Divider(),
                const Text(
                  'الأبعاد والموضع',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildNumberField('X', _xController, (val) {
                        if (isTable) {
                          widget.onUpdateTable!(
                            widget.tableSettings!.copyWith(xPosition: val),
                          );
                        } else {
                          widget.onUpdate(
                            widget.selectedElement!.copyWith(xPosition: val),
                          );
                        }
                      }),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildNumberField('Y', _yController, (val) {
                        if (isTable) {
                          widget.onUpdateTable!(
                            widget.tableSettings!.copyWith(yPosition: val),
                          );
                        } else {
                          widget.onUpdate(
                            widget.selectedElement!.copyWith(yPosition: val),
                          );
                        }
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildNumberField('العرض', _widthController, (
                        val,
                      ) {
                        if (isTable) {
                          widget.onUpdateTable!(
                            widget.tableSettings!.copyWith(width: val),
                          );
                        } else {
                          widget.onUpdate(
                            widget.selectedElement!.copyWith(width: val),
                          );
                        }
                      }),
                    ),
                    const SizedBox(width: 8),
                    if (!isTable &&
                        widget.selectedElement!.elementType != 'line')
                      Expanded(
                        child: _buildNumberField(
                          'الارتفاع',
                          _heightController,
                          (val) {
                            widget.onUpdate(
                              widget.selectedElement!.copyWith(height: val),
                            );
                          },
                        ),
                      ),
                  ],
                ),

                const Divider(),
                const Text(
                  'تنسيق الخط',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),

                _buildNumberField('حجم الخط', _fontSizeController, (val) {
                  if (isTable) {
                    widget.onUpdateTable!(
                      widget.tableSettings!.copyWith(fontSize: val),
                    );
                  } else {
                    widget.onUpdate(
                      widget.selectedElement!.copyWith(fontSize: val),
                    );
                  }
                }),

                if (!isTable) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildStyleToggle(
                        icon: PhosphorIconsBold.textB,
                        isActive: widget.selectedElement!.isBold,
                        onTap: () => widget.onUpdate(
                          widget.selectedElement!.copyWith(
                            isBold: !widget.selectedElement!.isBold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildStyleToggle(
                        icon: PhosphorIconsBold.textItalic,
                        isActive: widget.selectedElement!.isItalic,
                        onTap: () => widget.onUpdate(
                          widget.selectedElement!.copyWith(
                            isItalic: !widget.selectedElement!.isItalic,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // ═══ Section assignment ═══
                  const Divider(),
                  const Text(
                    'القسم',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  _buildDropdownField(
                    'قسم العنصر',
                    widget.selectedElement!.section,
                    ['header', 'body', 'details', 'footer'],
                    (val) {
                      if (val != null) {
                        widget.onUpdate(
                          widget.selectedElement!.copyWith(section: val),
                        );
                      }
                    },
                  ),
                  // ═══ Formula field ═══
                  const Text(
                    'الصيغة الرياضية',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'مثال: [subtotal] - [discount]',
                    style: TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  _buildTextField(
                    'الصيغة',
                    TextEditingController(text: widget.selectedElement!.formula),
                    (val) {
                      widget.onUpdate(
                        widget.selectedElement!.copyWith(
                          formula: Value(val.isEmpty ? null : val),
                        ),
                      );
                    },
                  ),
                ],

                // Table Specific Settings - Column Visibility
                if (isTable) ...[
                  const Divider(),
                  const Text(
                    'أعمدة الجدول',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'اختر الأعمدة التي تظهر في الفاتورة:',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  _buildTableColumnToggle(
                    'م (ترقيم)',
                    widget.tableSettings!.showIndex,
                    (val) => widget.onUpdateTable!(
                      widget.tableSettings!.copyWith(showIndex: val),
                    ),
                  ),
                  _buildTableColumnToggle(
                    'كود المنتج',
                    widget.tableSettings!.showProductCode,
                    (val) => widget.onUpdateTable!(
                      widget.tableSettings!.copyWith(showProductCode: val),
                    ),
                  ),
                  _buildTableColumnToggle(
                    'اسم المنتج',
                    widget.tableSettings!.showProductName,
                    (val) => widget.onUpdateTable!(
                      widget.tableSettings!.copyWith(showProductName: val),
                    ),
                  ),
                  _buildTableColumnToggle(
                    'الكمية',
                    widget.tableSettings!.showQuantity,
                    (val) => widget.onUpdateTable!(
                      widget.tableSettings!.copyWith(showQuantity: val),
                    ),
                  ),
                  _buildTableColumnToggle(
                    'سعر الوحدة',
                    widget.tableSettings!.showUnitPrice,
                    (val) => widget.onUpdateTable!(
                      widget.tableSettings!.copyWith(showUnitPrice: val),
                    ),
                  ),
                  _buildTableColumnToggle(
                    'الخصم',
                    widget.tableSettings!.showDiscount,
                    (val) => widget.onUpdateTable!(
                      widget.tableSettings!.copyWith(showDiscount: val),
                    ),
                  ),
                  _buildTableColumnToggle(
                    'الضريبة',
                    widget.tableSettings!.showTax,
                    (val) => widget.onUpdateTable!(
                      widget.tableSettings!.copyWith(showTax: val),
                    ),
                  ),
                  _buildTableColumnToggle(
                    'الإجمالي',
                    widget.tableSettings!.showTotal,
                    (val) => widget.onUpdateTable!(
                      widget.tableSettings!.copyWith(showTotal: val),
                    ),
                  ),
                  _buildTableColumnToggle(
                    'الوحدة',
                    widget.tableSettings!.showUnit,
                    (val) => widget.onUpdateTable!(
                      widget.tableSettings!.copyWith(showUnit: val),
                    ),
                  ),
                  _buildTableColumnToggle(
                    'الباركود',
                    widget.tableSettings!.showBarcode,
                    (val) => widget.onUpdateTable!(
                      widget.tableSettings!.copyWith(showBarcode: val),
                    ),
                  ),
                  _buildTableColumnToggle(
                    'ملاحظات الصنف',
                    widget.tableSettings!.showNotes,
                    (val) => widget.onUpdateTable!(
                      widget.tableSettings!.copyWith(showNotes: val),
                    ),
                  ),
                  const Divider(),
                  const Text(
                    'عرض الأعمدة',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'تحكم في عرض كل عمود (نسبة):',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  ..._buildColumnWidthSliders(),

                  const Divider(),
                  const Text(
                    'تنسيق الجدول',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  _TableNumberField(
                    label: 'ارتفاع الصف',
                    value: widget.tableSettings!.rowHeight,
                    onChanged: (val) => widget.onUpdateTable!(
                      widget.tableSettings!.copyWith(rowHeight: val),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _TableNumberField(
                    label: 'حجم خط العنوان',
                    value: widget.tableSettings!.headerFontSize,
                    onChanged: (val) => widget.onUpdateTable!(
                      widget.tableSettings!.copyWith(headerFontSize: val),
                    ),
                  ),
                  const SizedBox(height: 4),
                  _buildTableColumnToggle(
                    'عنوان الجدول بولد (عريض)',
                    _getJsonBool('_headerBold', true),
                    (val) => _setJsonBool('_headerBold', val),
                  ),
                  const SizedBox(height: 8),
                  _TableNumberField(
                    label: 'حجم خط البيانات',
                    value: widget.tableSettings!.fontSize,
                    onChanged: (val) => widget.onUpdateTable!(
                      widget.tableSettings!.copyWith(fontSize: val),
                    ),
                  ),
                  const SizedBox(height: 4),
                  _buildTableColumnToggle(
                    'بيانات الجدول بولد (عريض)',
                    _getJsonBool('_bodyBold', false),
                    (val) => _setJsonBool('_bodyBold', val),
                  ),
                  const SizedBox(height: 12),
                  // Decimal places control
                  Row(
                    children: [
                      const SizedBox(width: 4),
                      const Expanded(
                        child: Text(
                          'تنسيق الأرقام',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                      DropdownButton<int>(
                        value: _getDecimalPlaces(),
                        isDense: true,
                        items: const [
                          DropdownMenuItem(
                            value: 0,
                            child: Text('عدد صحيح (100)'),
                          ),
                          DropdownMenuItem(
                            value: 1,
                            child: Text('خانة (100.0)'),
                          ),
                          DropdownMenuItem(
                            value: 2,
                            child: Text('خانتين (100.00)'),
                          ),
                          DropdownMenuItem(
                            value: 3,
                            child: Text('3 خانات (100.000)'),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) _setDecimalPlaces(val);
                        },
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller,
    Function(String) onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          onChanged: onChanged,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.all(8),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildDropdownField(
    String label,
    String value,
    List<String> items,
    Function(String?) onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue: items.contains(value) ? value : null,
          items: items
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: onChanged,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.all(8),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildNumberField(
    String label,
    TextEditingController controller,
    Function(double) onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14),
          onSubmitted: (val) {
            final num = double.tryParse(val);
            if (num != null) onChanged(num);
          },
          onTapOutside: (_) {
            // Update when focus is lost
            final num = double.tryParse(controller.text);
            if (num != null) onChanged(num);
          },
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            isDense: true,
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Decrement button
                InkWell(
                  onTap: () {
                    final current = double.tryParse(controller.text) ?? 0;
                    final newVal = (current - 1).clamp(0, 9999);
                    controller.text = newVal.toStringAsFixed(1);
                    onChanged(newVal.toDouble());
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.remove, size: 16, color: Colors.grey),
                  ),
                ),
                // Increment button
                InkWell(
                  onTap: () {
                    final current = double.tryParse(controller.text) ?? 0;
                    final newVal = current + 1;
                    controller.text = newVal.toStringAsFixed(1);
                    onChanged(newVal);
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.add, size: 16, color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStyleToggle({
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isActive
              ? Colors.blue.withValues(alpha: 0.1)
              : Colors.transparent,
          border: Border.all(
            color: isActive ? Colors.blue : Colors.grey.shade300,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon, color: isActive ? Colors.blue : Colors.grey),
      ),
    );
  }

  Widget _buildTableColumnToggle(
    String label,
    bool value,
    Function(bool) onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Checkbox(
            value: value,
            onChanged: (v) => onChanged(v ?? false),
            visualDensity: VisualDensity.compact,
          ),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  // Column classification constants
  static const _numericColumns = {'quantity', 'price', 'discount', 'tax', 'total'};
  static const _textColumns = {'product', 'code', 'notes', 'barcode', 'unit'};
  static const _columnLabels = {
    'product': 'اسم الصنف',
    'code': 'كود الصنف',
    'index': 'الترتيب',
    'quantity': 'الكمية',
    'price': 'السعر',
    'discount': 'الخصم',
    'tax': 'الضريبة',
    'total': 'الإجمالي',
    'unit': 'الوحدة',
    'barcode': 'الباركود',
    'notes': 'الملاحظات',
  };

  /// Parse columnWidths from JSON, returning defaults if null.
  /// Supports both old format (plain numbers) and new format (maps with settings).
  Map<String, double> _parseColumnWidths() {
    final ts = widget.tableSettings!;
    final defaults = <String, double>{
      'product': 3.0,
      'code': 1.5,
      'index': 0.8,
      'quantity': 1.0,
      'price': 1.2,
      'discount': 1.0,
      'tax': 1.0,
      'total': 1.5,
      'unit': 1.0,
      'barcode': 1.5,
      'notes': 2.0,
    };
    if (ts.columnWidths != null && ts.columnWidths!.isNotEmpty) {
      try {
        final decoded = jsonDecode(ts.columnWidths!) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          if (entry.key.startsWith('_')) continue; // skip meta keys
          if (entry.value is num) {
            // Old format: plain number
            defaults[entry.key] = (entry.value as num).toDouble();
          } else if (entry.value is Map) {
            // New format: map with 'width' key
            final map = entry.value as Map<String, dynamic>;
            defaults[entry.key] = (map['width'] as num?)?.toDouble() ?? defaults[entry.key]!;
          }
        }
      } catch (_) {}
    }
    return defaults;
  }

  /// Get width for a column, supporting both old and new JSON format
  // ignore: unused_element
  double _getColWidth(String key) {
    final widths = _parseColumnWidths();
    return widths[key] ?? 1.0;
  }

  /// Get per-column font size, or fallback to global body font size
  int _getColFontSize(String key) {
    final json = _getFullJson();
    final val = json[key];
    if (val is Map) {
      return (val['fontSize'] as num?)?.toInt() ?? widget.tableSettings!.fontSize.toInt();
    }
    return widget.tableSettings!.fontSize.toInt();
  }

  /// Get per-column decimal places, or fallback to global default
  int _getColDecimals(String key) {
    final json = _getFullJson();
    final val = json[key];
    if (val is Map) {
      return (val['decimals'] as num?)?.toInt() ?? _getDecimalPlaces();
    }
    return _getDecimalPlaces();
  }

  /// Get per-column text wrap setting, or fallback to false
  bool _getColWrap(String key) {
    final json = _getFullJson();
    final val = json[key];
    if (val is Map) {
      return (val['wrap'] as bool?) ?? false;
    }
    return false;
  }

  /// Update a single property for a column, preserving all other settings.
  /// Converts old format entries to new format as needed.
  void _setColSetting(String key, String prop, dynamic value) {
    final json = _getFullJson();
    // Get existing value for this column
    final existing = json[key];
    Map<String, dynamic> colMap;
    if (existing is Map) {
      colMap = Map<String, dynamic>.from(existing as Map<String, dynamic>);
    } else if (existing is num) {
      // Convert old format to new format, preserving width
      colMap = {'width': existing.toDouble()};
    } else {
      // New entry — use current default width
      final widths = _parseColumnWidths();
      colMap = {'width': widths[key] ?? 1.0};
    }
    colMap[prop] = value;
    json[key] = colMap;
    widget.onUpdateTable!(
      widget.tableSettings!.copyWith(columnWidths: Value(jsonEncode(json))),
    );
  }

  /// Save column width, preserving per-column settings if they exist
  void _saveColumnWidth(String key, double value) {
    final fullJson = _getFullJson();
    final existing = fullJson[key];
    if (existing is Map) {
      // New format: update width inside the map
      final colMap = Map<String, dynamic>.from(existing as Map<String, dynamic>);
      colMap['width'] = value;
      fullJson[key] = colMap;
    } else {
      // Old format or new entry: just set the width
      // Check if there's already a map we should use
      fullJson[key] = value;
    }
    // Also ensure all other column widths are preserved
    final widths = _parseColumnWidths();
    for (final entry in widths.entries) {
      if (!fullJson.containsKey(entry.key)) {
        fullJson[entry.key] = entry.value;
      }
    }
    widget.onUpdateTable!(
      widget.tableSettings!.copyWith(columnWidths: Value(jsonEncode(fullJson))),
    );
  }

  /// Get the full JSON map (including non-width keys like _decimalPlaces)
  Map<String, dynamic> _getFullJson() {
    final ts = widget.tableSettings!;
    if (ts.columnWidths != null && ts.columnWidths!.isNotEmpty) {
      try {
        return Map<String, dynamic>.from(
          jsonDecode(ts.columnWidths!) as Map<String, dynamic>,
        );
      } catch (_) {}
    }
    return {};
  }

  /// Get decimal places from columnWidths JSON (default 2)
  int _getDecimalPlaces() {
    final json = _getFullJson();
    return (json['_decimalPlaces'] as num?)?.toInt() ?? 2;
  }

  /// Set decimal places in the columnWidths JSON
  void _setDecimalPlaces(int places) {
    final json = _getFullJson();
    // Merge with current column width defaults (only add missing keys)
    final widths = _parseColumnWidths();
    for (final entry in widths.entries) {
      if (!json.containsKey(entry.key)) {
        json[entry.key] = entry.value;
      }
    }
    json['_decimalPlaces'] = places;
    widget.onUpdateTable!(
      widget.tableSettings!.copyWith(columnWidths: Value(jsonEncode(json))),
    );
  }

  /// Get a boolean flag from the columnWidths JSON (e.g., _headerBold, _bodyBold)
  bool _getJsonBool(String key, bool defaultValue) {
    final json = _getFullJson();
    return (json[key] as bool?) ?? defaultValue;
  }

  /// Set a boolean flag in the columnWidths JSON
  void _setJsonBool(String key, bool value) {
    final json = _getFullJson();
    // Merge with current column width defaults (only add missing keys)
    final widths = _parseColumnWidths();
    for (final entry in widths.entries) {
      if (!json.containsKey(entry.key)) {
        json[entry.key] = entry.value;
      }
    }
    json[key] = value;
    widget.onUpdateTable!(
      widget.tableSettings!.copyWith(columnWidths: Value(jsonEncode(json))),
    );
  }

  /// Build list of column settings tiles for visible columns only.
  /// Each column gets an ExpansionTile with width slider, font size,
  /// decimal places (numeric columns), and text wrap (text columns).
  List<Widget> _buildColumnWidthSliders() {
    final ts = widget.tableSettings!;
    final widths = _parseColumnWidths();

    final columns = <String>[];
    if (ts.showIndex) columns.add('index');
    if (ts.showProductName) columns.add('product');
    if (ts.showProductCode) columns.add('code');
    if (ts.showQuantity) columns.add('quantity');
    if (ts.showUnitPrice) columns.add('price');
    if (ts.showDiscount) columns.add('discount');
    if (ts.showTax) columns.add('tax');
    if (ts.showTotal) columns.add('total');
    if (ts.showUnit) columns.add('unit');
    if (ts.showBarcode) columns.add('barcode');
    if (ts.showNotes) columns.add('notes');

    return columns.map((key) {
      return _buildColumnSettingsTile(key, widths[key] ?? 1.0);
    }).toList();
  }

  /// Build an ExpansionTile for a single column with all its settings
  Widget _buildColumnSettingsTile(String key, double currentWidth) {
    final columnLabel = _columnLabels[key] ?? key;
    final isNumeric = _numericColumns.contains(key);
    final isText = _textColumns.contains(key);
    final fontSize = _getColFontSize(key);
    final decimals = _getColDecimals(key);
    final wrap = _getColWrap(key);
    final globalFontSize = widget.tableSettings!.fontSize.toInt();

    return ExpansionTile(
      title: Text(columnLabel, style: const TextStyle(fontSize: 13)),
      subtitle: Text(
        'العرض: ${currentWidth.toStringAsFixed(1)}',
        style: const TextStyle(fontSize: 11, color: Colors.grey),
      ),
      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
      childrenPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      dense: true,
      children: [
        // Width slider (existing)
        Row(
          children: [
            const SizedBox(
              width: 50,
              child: Text('العرض:', style: TextStyle(fontSize: 12)),
            ),
            Expanded(
              child: Slider(
                value: currentWidth.clamp(0.5, 5.0),
                min: 0.5,
                max: 5.0,
                divisions: 18,
                label: currentWidth.toStringAsFixed(1),
                onChanged: (val) {
                  _saveColumnWidth(key, double.parse(val.toStringAsFixed(1)));
                },
              ),
            ),
            SizedBox(
              width: 30,
              child: Text(
                currentWidth.toStringAsFixed(1),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        // Font size dropdown
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              const SizedBox(
                width: 70,
                child: Text('حجم الخط:', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButton<int>(
                  value: fontSize,
                  isDense: true,
                  isExpanded: true,
                  items: [8, 9, 10, 11, 12, 13, 14, 16].map((size) {
                    final label = size == globalFontSize
                        ? '$size (افتراضي)'
                        : '$size';
                    return DropdownMenuItem<int>(
                      value: size,
                      child: Text(label, style: const TextStyle(fontSize: 12)),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      _setColSetting(key, 'fontSize', val);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        // Decimal places dropdown (only for numeric columns)
        if (isNumeric)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                const SizedBox(
                  width: 110,
                  child: Text('المنازل العشرية:', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<int>(
                    value: decimals,
                    isDense: true,
                    isExpanded: true,
                    items: [0, 1, 2, 3].map((d) {
                      final example = (100.0).toStringAsFixed(d);
                      return DropdownMenuItem<int>(
                        value: d,
                        child: Text('$d ($example)', style: const TextStyle(fontSize: 12)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        _setColSetting(key, 'decimals', val);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        // Text wrap checkbox (only for text columns)
        if (isText)
          CheckboxListTile(
            title: const Text('التفاف النص', style: TextStyle(fontSize: 12)),
            value: wrap,
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (val) {
              _setColSetting(key, 'wrap', val ?? false);
            },
          ),
        const SizedBox(height: 4),
      ],
    );
  }

  /// Grouped variable dropdown with Arabic labels
  Widget _buildGroupedVariableDropdown(
    String label,
    String value,
    Function(String?) onChanged,
  ) {
    const variableGroups = <String, List<MapEntry<String, String>>>{
      '🏢 بيانات الشركة': [
        MapEntry('company_name', 'اسم الشركة'),
        MapEntry('company_address', 'عنوان الشركة'),
        MapEntry('company_phone', 'هاتف الشركة'),
        MapEntry('company_tax_number', 'الرقم الضريبي'),
      ],
      '📄 بيانات الفاتورة': [
        MapEntry('invoice_number', 'رقم الفاتورة'),
        MapEntry('order_number', 'رقم الطلب'),
        MapEntry('date', 'التاريخ'),
        MapEntry('time', 'الوقت'),
        MapEntry('invoice_type_label', 'نوع الفاتورة'),
      ],
      '👤 العميل / المورد': [
        MapEntry('customer_name', 'اسم العميل'),
        MapEntry('customer_phone', 'هاتف العميل'),
        MapEntry('customer_address', 'عنوان العميل'),
        MapEntry('adhoc_customer_name', 'اسم العميل النصي'),
        MapEntry('adhoc_customer_phone', 'هاتف العميل النصي'),
        MapEntry('supplier_name', 'اسم المورد'),
      ],
      '💰 المبالغ': [
        MapEntry('subtotal', 'المجموع الفرعي'),
        MapEntry('discount', 'الخصم'),
        MapEntry('tax', 'الضريبة'),
        MapEntry('total_amount', 'الإجمالي'),
        MapEntry('net_amount', 'الصافي'),
        MapEntry('paid', 'المدفوع'),
        MapEntry('remaining', 'المتبقي'),
        MapEntry('cash_amount', 'المدفوع نقداً'),
        MapEntry('bank_amount', 'مدفوع بنكي'),
        MapEntry('click_amount', 'مدفوع كليك'),
      ],
      '🚚 التوصيل': [
        MapEntry('delivery_fee', 'رسوم التوصيل'),
        MapEntry('delivery_type', 'نوع التوصيل'),
        MapEntry('delivery_address', 'عنوان التوصيل'),
      ],
      '🏪 البيع': [
        MapEntry('sale_type', 'نوع البيع'),
        MapEntry('payment_method', 'طريقة الدفع'),
        MapEntry('cashier_name', 'اسم الكاشير'),
        MapEntry('warehouse_name', 'المخزن'),
        MapEntry('branch_name', 'الفرع'),
      ],
      '🍽️ المطعم': [
        MapEntry('table_number', 'رقم الطاولة'),
        MapEntry('waiter_name', 'اسم الويتر'),
        MapEntry('kitchen_notes', 'ملاحظات المطبخ'),
      ],
      '⏱️ الوردية': [
        MapEntry('shift_number', 'رقم الوردية'),
        MapEntry('shift_date', 'تاريخ الوردية'),
      ],
      '📝 أخرى': [
        MapEntry('notes', 'الملاحظات'),
        MapEntry('footer_text', 'نص التذييل'),
      ],
    };

    // Flatten all values to find current
    final allValues = <String>[];
    for (final group in variableGroups.values) {
      for (final entry in group) {
        allValues.add(entry.key);
      }
    }

    // Build dropdown items with group headers
    final items = <DropdownMenuItem<String>>[];
    for (final entry in variableGroups.entries) {
      // Group header (disabled)
      items.add(DropdownMenuItem<String>(
        enabled: false,
        value: '__group_${entry.key}',
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Text(
            entry.key,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: Colors.blue,
            ),
          ),
        ),
      ));
      // Items
      for (final variable in entry.value) {
        items.add(DropdownMenuItem<String>(
          value: variable.key,
          child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(variable.value, style: const TextStyle(fontSize: 13)),
                ),
                Text(
                  variable.key,
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue: allValues.contains(value) ? value : null,
          items: items,
          onChanged: onChanged,
          isExpanded: true,
          menuMaxHeight: 400,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.all(8),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}


/// حقلٌ رقميٌّ يملك مُتحكّمَه.
///
/// ── لماذا ودجت لا دالّة ───────────────────────────────────────────────────
/// الحقولُ الثلاثةُ لإعدادات الجدول كانت تبني `TextEditingController` **داخل
/// `build`**. وكلُّ إعادةِ بناءٍ — وهي تقع مع أيّ تعديلٍ آخرَ في اللوحة —
/// تنشئ مُتحكّماً جديداً بالقيمة المخزَّنة، فيُمحى ما كتبه المستخدمُ قبل أن
/// يفقد الحقلُ التركيز. والكتابةُ تقع عند `onSubmitted`/`onTapOutside`، فما
/// لم يُسلَّم يضيع بلا أثر.
///
/// قِيس في قاعدة المالك 2026-08-12: `header_font_size = 1.0` بينما المحرّرُ
/// يعرض 9pt — قيمةٌ في الذاكرة لم تصل القاعدةَ قط.
///
/// المُتحكّمُ هنا يعيش مع الحالة، ويُزامَن من الخارج **فقط حين لا يكون
/// الحقلُ مركَّزاً** — فلا تُقتلع القيمةُ من تحت أصابع من يكتب.
class _TableNumberField extends StatefulWidget {
  const _TableNumberField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  State<_TableNumberField> createState() => _TableNumberFieldState();
}

class _TableNumberFieldState extends State<_TableNumberField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value.toStringAsFixed(1));
  final FocusNode _focus = FocusNode();

  @override
  void didUpdateWidget(covariant _TableNumberField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && widget.value != old.value) {
      _controller.text = widget.value.toStringAsFixed(1);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final parsed = double.tryParse(_controller.text.trim());
    if (parsed != null && parsed != widget.value) widget.onChanged(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label,
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        TextField(
          controller: _controller,
          focusNode: _focus,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14),
          onSubmitted: (_) => _commit(),
          onTapOutside: (_) {
            _commit();
            _focus.unfocus();
          },
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}
