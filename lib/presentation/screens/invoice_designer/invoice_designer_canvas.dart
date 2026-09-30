import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../data/database/database.dart';
import '../../../core/theme/app_colors.dart';

class InvoiceDesignerCanvas extends StatelessWidget {
  final List<InvoiceTemplateElement> elements;
  final InvoiceTemplateElement? selectedElement;
  final Set<int> selectedElementIds;
  final Function(InvoiceTemplateElement, [bool isCtrl]) onSelectElement;
  final Function(InvoiceTemplateElement, double, double) onUpdatePosition;
  final Function(InvoiceTemplateElement, double, double) onUpdateSize;
  final InvoiceTableSetting? tableSettings;
  final Function(InvoiceTableSetting)? onUpdateTableSettings;
  final Function(String elementType, {String? variableContent, double? x, double? y})? onDropElement;

  final String templateType;
  final double paperWidth;
  final bool showGrid;

  const InvoiceDesignerCanvas({
    super.key,
    required this.elements,
    this.selectedElement,
    this.selectedElementIds = const {},
    required this.onSelectElement,
    required this.onUpdatePosition,
    required this.onUpdateSize,
    this.tableSettings,
    this.onUpdateTableSettings,
    this.onDropElement,
    required this.templateType,
    this.paperWidth = 80,
    this.showGrid = true,
  });

  @override
  Widget build(BuildContext context) {
    const mmToPoints = 2.8346;
    final canvasWidth = templateType == 'thermal'
        ? (paperWidth * mmToPoints)
        : 595.0;
    final canvasHeight = templateType == 'thermal'
        ? 800.0
        : 842.0;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: DragTarget<PaletteDragData>(
          onAcceptWithDetails: (details) {
            if (onDropElement != null) {
              // Calculate position relative to the canvas
              final renderBox = context.findRenderObject() as RenderBox?;
              if (renderBox != null) {
                final localPos = renderBox.globalToLocal(details.offset);
                onDropElement!(
                  details.data.type,
                  variableContent: details.data.content,
                  x: localPos.dx.clamp(0, canvasWidth - 60),
                  y: localPos.dy.clamp(0, canvasHeight - 30),
                );
              } else {
                onDropElement!(details.data.type, variableContent: details.data.content);
              }
            }
          },
          builder: (context, candidateData, rejectedData) {
            final isHovering = candidateData.isNotEmpty;
            return Container(
              width: canvasWidth,
              height: canvasHeight,
              decoration: BoxDecoration(
                // ورقٌ مطبوع — تحاكي المطبوعَ فتبقى بيضاءَ في الوضعَين.
                color: Colors.white,
                border: Border.all(
                  color: isHovering ? AppColors.primary : Colors.grey.shade300,
                  width: isHovering ? 2 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Visual grid
                  if (showGrid) _buildGrid(canvasWidth, canvasHeight),

                  // Section dividers
                  ..._buildSectionDividers(canvasWidth, canvasHeight),

                  // Items Table
                  if (tableSettings != null) _buildTableElement(),

                  // Dynamic Elements
                  ...elements.map((e) => _buildDraggableElement(e)),

                  // Drop indicator
                  if (isHovering)
                    Positioned.fill(
                      child: Container(
                        color: AppColors.primary.withValues(alpha: 0.04),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                            ),
                            child:  Text(
                              tr('أفلت هنا لإضافة العنصر'),
                              style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildGrid(double width, double height) {
    return CustomPaint(
      size: Size(width, height),
      painter: _GridPainter(gridSize: 20),
    );
  }

  /// Build section divider lines (header / body / details / footer)
  List<Widget> _buildSectionDividers(double canvasWidth, double canvasHeight) {
    // Define section boundaries as fractions of canvas height
    final headerEnd = canvasHeight * 0.15;   // ~15%
    final detailsStart = canvasHeight * 0.35; // ~35%
    final detailsEnd = canvasHeight * 0.70;   // ~70%

    final sections = [
      _SectionInfo(tr('الرأس (Header)'), 0, headerEnd, const Color(0x0A2196F3)),
      _SectionInfo(tr('المحتوى (Body)'), headerEnd, detailsStart, const Color(0x0A4CAF50)),
      _SectionInfo(tr('التفاصيل (Details)'), detailsStart, detailsEnd, const Color(0x0AFF9800)),
      _SectionInfo(tr('التذييل (Footer)'), detailsEnd, canvasHeight, const Color(0x0A9C27B0)),
    ];

    final widgets = <Widget>[];
    for (final sec in sections) {
      // Section background
      widgets.add(Positioned(
        left: 0,
        top: sec.top,
        width: canvasWidth,
        height: sec.bottom - sec.top,
        child: IgnorePointer(
          child: Container(color: sec.color),
        ),
      ));

      // Dashed divider line at section boundary (skip first)
      if (sec.top > 0) {
        widgets.add(Positioned(
          left: 0,
          top: sec.top,
          width: canvasWidth,
          height: 1,
          child: IgnorePointer(
            child: CustomPaint(
              size: Size(canvasWidth, 1),
              painter: _DashedLinePainter(color: Colors.blueGrey.shade300),
            ),
          ),
        ));
      }

      // Section label
      widgets.add(Positioned(
        right: 4,
        top: sec.top + 2,
        child: IgnorePointer(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: Colors.blueGrey.shade200, width: 0.5),
            ),
            child: Text(
              sec.label,
              style: TextStyle(fontSize: 8, color: Colors.blueGrey.shade400, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ));
    }
    return widgets;
  }

  Widget _buildTableElement() {
    final settings = tableSettings!;

    return Positioned(
      left: settings.xPosition,
      top: settings.yPosition,
      width: settings.width,
      child: GestureDetector(
        onPanUpdate: (details) {
          if (onUpdateTableSettings != null) {
            final newX = settings.xPosition + details.delta.dx;
            final newY = settings.yPosition + details.delta.dy;
            onUpdateTableSettings!(
              settings.copyWith(xPosition: newX, yPosition: newY),
            );
          }
        },
        onTap: () {
          if (onUpdateTableSettings != null) onUpdateTableSettings!(settings);
        },
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.blue.shade200, width: 2),
            color: Colors.blue.withValues(alpha: 0.05),
          ),
          child: Column(
            children: [
              Container(
                height: 30,
                color: Colors.grey.shade300,
                child:  Center(
                  child: Text(tr('جدول الأصناف (اسحب للتحريك)'), style: const TextStyle(fontSize: 10)),
                ),
              ),
              for (int i = 0; i < 3; i++)
                Container(
                  height: 25,
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDraggableElement(InvoiceTemplateElement element) {
    final isSelected = selectedElement?.id == element.id;
    final isMultiSelected = selectedElementIds.contains(element.id);

    return Positioned(
      left: element.xPosition,
      top: element.yPosition,
      width: element.width,
      height: element.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The Element Content + Drag Listener
          GestureDetector(
            onPanUpdate: (details) {
              onUpdatePosition(
                element,
                element.xPosition + details.delta.dx,
                element.yPosition + details.delta.dy,
              );
            },
            onTap: () {
              final isCtrl = HardwareKeyboard.instance.logicalKeysPressed
                  .any((k) => k == LogicalKeyboardKey.controlLeft || k == LogicalKeyboardKey.controlRight);
              onSelectElement(element, isCtrl);
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.move,
              child: Container(
                decoration: BoxDecoration(
                  border: isSelected
                      ? Border.all(color: AppColors.primary, width: 2)
                      : isMultiSelected
                          ? Border.all(color: Colors.orange, width: 2)
                          : Border.all(color: Colors.grey.withValues(alpha: 0.3), width: 1),
                  color: isSelected
                      ? AppColors.primary.withValues(alpha: 0.05)
                      : isMultiSelected
                          ? Colors.orange.withValues(alpha: 0.04)
                          : Colors.transparent,
                ),
                child: _buildElementContent(element),
              ),
            ),
          ),

          // Resize Handles (8 handles when selected)
          if (isSelected) ..._buildAllResizeHandles(element),
        ],
      ),
    );
  }

  List<Widget> _buildAllResizeHandles(InvoiceTemplateElement element) {
    return [
      // Top Left
      Positioned(
        left: -5, top: -5,
        child: _buildResizeHandle(
          cursor: SystemMouseCursors.resizeUpLeftDownRight,
          onDrag: (dx, dy) {
            onUpdatePosition(element, element.xPosition + dx, element.yPosition + dy);
            onUpdateSize(element, element.width - dx, element.height - dy);
          },
        ),
      ),
      // Top Center
      Positioned(
        left: element.width / 2 - 5, top: -5,
        child: _buildResizeHandle(
          cursor: SystemMouseCursors.resizeUpDown,
          onDrag: (dx, dy) {
            onUpdatePosition(element, element.xPosition, element.yPosition + dy);
            onUpdateSize(element, element.width, element.height - dy);
          },
        ),
      ),
      // Top Right
      Positioned(
        right: -5, top: -5,
        child: _buildResizeHandle(
          cursor: SystemMouseCursors.resizeUpRightDownLeft,
          onDrag: (dx, dy) {
            onUpdatePosition(element, element.xPosition, element.yPosition + dy);
            onUpdateSize(element, element.width + dx, element.height - dy);
          },
        ),
      ),
      // Middle Left
      Positioned(
        left: -5, top: element.height / 2 - 5,
        child: _buildResizeHandle(
          cursor: SystemMouseCursors.resizeLeftRight,
          onDrag: (dx, dy) {
            onUpdatePosition(element, element.xPosition + dx, element.yPosition);
            onUpdateSize(element, element.width - dx, element.height);
          },
        ),
      ),
      // Middle Right
      Positioned(
        right: -5, top: element.height / 2 - 5,
        child: _buildResizeHandle(
          cursor: SystemMouseCursors.resizeLeftRight,
          onDrag: (dx, dy) {
            onUpdateSize(element, element.width + dx, element.height);
          },
        ),
      ),
      // Bottom Left
      Positioned(
        left: -5, bottom: -5,
        child: _buildResizeHandle(
          cursor: SystemMouseCursors.resizeUpRightDownLeft,
          onDrag: (dx, dy) {
            onUpdatePosition(element, element.xPosition + dx, element.yPosition);
            onUpdateSize(element, element.width - dx, element.height + dy);
          },
        ),
      ),
      // Bottom Center
      Positioned(
        left: element.width / 2 - 5, bottom: -5,
        child: _buildResizeHandle(
          cursor: SystemMouseCursors.resizeUpDown,
          onDrag: (dx, dy) {
            onUpdateSize(element, element.width, element.height + dy);
          },
        ),
      ),
      // Bottom Right
      Positioned(
        right: -5, bottom: -5,
        child: _buildResizeHandle(
          cursor: SystemMouseCursors.resizeUpLeftDownRight,
          onDrag: (dx, dy) {
            onUpdateSize(element, element.width + dx, element.height + dy);
          },
        ),
      ),
    ];
  }

  Widget _buildResizeHandle({
    required MouseCursor cursor,
    required Function(double dx, double dy) onDrag,
  }) {
    return MouseRegion(
      cursor: cursor,
      child: GestureDetector(
        onPanUpdate: (details) => onDrag(details.delta.dx, details.delta.dy),
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            // ورقٌ مطبوع — مقبضُ تحجيمٍ فوقَ اللوحة البيضاء.
            color: Colors.white,
            border: Border.all(color: AppColors.primary, width: 1.5),
            borderRadius: BorderRadius.circular(2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildElementContent(InvoiceTemplateElement element) {
    final style = TextStyle(
      fontSize: element.fontSize,
      fontWeight: element.isBold ? FontWeight.bold : FontWeight.normal,
      fontStyle: element.isItalic ? FontStyle.italic : FontStyle.normal,
      color: Color(int.parse(element.fontColor.replaceFirst('#', '0xFF'))),
      fontFamily: _getFontFamily(element.fontFamily),
    );

    String getDisplayText() {
      final label = element.labelAr ?? element.labelEn ?? '';
      switch (element.elementType) {
        case 'logo':
          return tr('🏪 شعار الشركة');
        case 'company_name':
          return tr('🏢 اسم الشركة');
        case 'company_address':
          return tr('📍 عنوان الشركة');
        case 'company_phone':
          return tr('📞 هاتف الشركة');
        case 'invoice_number':
          return label.isNotEmpty ? '$label: 123456' : tr('رقم الفاتورة: 123456');
        case 'date':
          return label.isNotEmpty ? '$label: 2026/01/01' : tr('التاريخ: 2026/01/01');
        case 'time':
          return label.isNotEmpty ? '$label: 12:00' : tr('الوقت: 12:00');
        case 'customer':
          return label.isNotEmpty ? tr('{label}: عميل نقدي', {'label': label}) : tr('العميل: عميل نقدي');
        case 'cashier_name':
          return label.isNotEmpty ? tr('{label}: اسم الكاشير', {'label': label}) : tr('الكاشير: اسم الكاشير');
        case 'subtotal':
          return label.isNotEmpty ? '$label: 100.00' : tr('المجموع الفرعي: 100.00');
        case 'discount':
          return label.isNotEmpty ? '$label: 10.00' : tr('الخصم: 10.00');
        case 'tax':
          return label.isNotEmpty ? '$label: 14.00' : tr('الضريبة: 14.00');
        case 'total':
          return label.isNotEmpty ? '$label: 104.00' : tr('الإجمالي: 104.00');
        case 'paid':
          return label.isNotEmpty ? '$label: 104.00' : tr('المدفوع: 104.00');
        case 'remaining':
          return label.isNotEmpty ? '$label: 0.00' : tr('المتبقي: 0.00');
        case 'payment_method':
          return label.isNotEmpty ? tr('{label}: نقدي', {'label': label}) : tr('طريقة الدفع: نقدي');
        case 'notes':
          return label.isNotEmpty ? tr('{label}: ملاحظات', {'label': label}) : tr('ملاحظات: ملاحظات الفاتورة');
        case 'adhoc_customer_name':
          return label.isNotEmpty ? tr('{label}: اسم نصي', {'label': label}) : tr('اسم العميل النصي: اسم نصي');
        case 'adhoc_customer_phone':
          return label.isNotEmpty ? '$label: 01099999999' : tr('هاتف العميل النصي: 01099999999');
        // New fields
        case 'item_additions':
          return label.isNotEmpty ? tr('{label}: كاتشب، مايونيز', {'label': label}) : tr('الإضافات: كاتشب، مايونيز');
        case 'item_options':
          return label.isNotEmpty ? tr('{label}: قليل بندورة', {'label': label}) : tr('الخيارات: قليل بندورة، كثير جبنة');
        case 'tax_registration':
          return label.isNotEmpty ? '$label: 123-456-789' : tr('الرقم الضريبي: 123-456-789');
        case 'courier_name':
          return label.isNotEmpty ? tr('{label}: مندوب', {'label': label}) : tr('المندوب: اسم المندوب');
        case 'shift_number':
          return label.isNotEmpty ? '$label: 1' : tr('رقم الوردية: 1');
        case 'customer_name':
          return label.isNotEmpty ? tr('{label}: عميل نقدي', {'label': label}) : tr('اسم العميل: عميل نقدي');
        case 'customer_phone':
          return label.isNotEmpty ? '$label: 01099999999' : tr('هاتف العميل: 01099999999');
        case 'customer_address':
          return label.isNotEmpty ? tr('{label}: العنوان', {'label': label}) : tr('عنوان العميل: القاهرة');
        case 'barcode':
          return tr('||||| باركود |||||');
        case 'qr_code':
          return '⬛ QR ⬛';
        case 'footer':
          return element.content ?? tr('شكراً لزيارتكم');
        case 'order_number':
          return label.isNotEmpty ? '$label: 001' : tr('رقم الطلب: 001');
        case 'table_number':
          return label.isNotEmpty ? '$label: 5' : tr('رقم الطاولة: 5');
        case 'supplier_name':
          return label.isNotEmpty ? tr('{label}: المورد', {'label': label}) : tr('المورد: اسم المورد');
        case 'text':
          return element.content ?? tr('نص');
        case 'variable':
          return tr('{{p0}}', {'p0': element.content ?? tr('متغير')});
        default:
          return element.content ?? element.elementType;
      }
    }

    switch (element.elementType) {
      case 'divider':
        return Container(
          height: 2,
          color: Colors.grey.shade400,
          margin: const EdgeInsets.symmetric(vertical: 2),
        );
      case 'line':
        return Container(color: Colors.black, height: 2);
      case 'rectangle':
        return Container(
          decoration: BoxDecoration(border: Border.all(color: Colors.black)),
        );
      case 'image':
      case 'logo':
        return Center(
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.image, color: Colors.grey.shade400, size: 24),
                Text(tr('شعار'), style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
              ],
            ),
          ),
        );
      case 'barcode':
        return Center(
          child: Text(
            '||||| ${element.content ?? 'BARCODE'} |||||',
            style: style.copyWith(fontFamily: 'Courier', letterSpacing: 2),
          ),
        );
      case 'qr_code':
        return Center(
          child: Container(
            width: 40,
            height: 40,
            color: Colors.black,
            child: const Center(
              child: Text('QR', style: TextStyle(color: Colors.white, fontSize: 10)),
            ),
          ),
        );
      default:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Text(
            getDisplayText(),
            style: element.elementType == 'variable'
                ? style.copyWith(color: Colors.blue)
                : style,
            textAlign: _getTextAlign(element.textAlign),
            overflow: TextOverflow.ellipsis,
          ),
        );
    }
  }

  // ignore: unused_element
  Widget _buildHandle(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 2),
          ],
        ),
        child: Icon(icon, size: 14, color: Colors.white),
      ),
    );
  }

  TextAlign _getTextAlign(String align) {
    switch (align) {
      case 'left':
        return TextAlign.left;
      case 'center':
        return TextAlign.center;
      case 'right':
        return TextAlign.right;
      default:
        return TextAlign.right;
    }
  }

  String _getFontFamily(String? fontFamily) {
    switch (fontFamily) {
      case 'Cairo':
        return 'Cairo';
      case 'Tajawal':
        return 'Tajawal';
      case 'IBM Plex Sans Arabic':
        return 'IBM Plex Sans Arabic';
      default:
        return 'Cairo';
    }
  }
}

/// Grid painter for visual alignment aid
class _GridPainter extends CustomPainter {
  final double gridSize;
  _GridPainter({this.gridSize = 20});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.08)
      ..strokeWidth = 0.5;

    // Vertical lines
    for (double x = 0; x <= size.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    // Horizontal lines
    for (double y = 0; y <= size.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Data class for drag-and-drop from palette
class PaletteDragData {
  final String type;
  final String? content;
  const PaletteDragData(this.type, this.content);
}

/// Section info for canvas dividers
class _SectionInfo {
  final String label;
  final double top;
  final double bottom;
  final Color color;
  const _SectionInfo(this.label, this.top, this.bottom, this.color);
}

/// Dashed line painter for section dividers
class _DashedLinePainter extends CustomPainter {
  final Color color;
  _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dashWidth = 5.0;
    const dashSpace = 3.0;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dashWidth, 0), paint);
      x += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
