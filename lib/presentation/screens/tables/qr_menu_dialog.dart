import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/database/database_barrel.dart';
import '../../../services/network_service.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../services/generators/base_generator.dart';
import 'package:printing/printing.dart' as printing_pkg;

class QrMenuDialog extends StatelessWidget {
  final List<RestaurantTable> tables;

  const QrMenuDialog({super.key, required this.tables});

  @override
  Widget build(BuildContext context) {
    final ns = NetworkService.instance;
    final serverIp = ns.serverAddress ?? 'localhost';
    final port = ns.serverPort;
    final menuUrl = 'http://$serverIp:$port/menu';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Row(
          children: [
            Icon(PhosphorIconsBold.qrCode, color: AppColors.primary),
            SizedBox(width: 8),
            Text('أكواد المنيو الرقمي للطاولات'),
          ],
        ),
        content: SizedBox(
          width: 600,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      PhosphorIconsBold.info,
                      color: AppColors.info,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'يمكن للعملاء مسح هذه الأكواد للوصول إلى المنيو الرقمي على هواتفهم. الرابط الأساسي: $menuUrl',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: GridView.builder(
                  shrinkWrap: true,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 1,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                  ),
                  itemCount: tables.length,
                  itemBuilder: (context, index) {
                    final table = tables[index];
                    final tableUrl = '$menuUrl?table=${table.id}';
                    // Using public QR API for generation
                    final qrUrl =
                        'https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=${Uri.encodeComponent(tableUrl)}';

                    return Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Image.network(
                                qrUrl,
                                loadingBuilder:
                                    (context, child, loadingProgress) {
                                      if (loadingProgress == null) return child;
                                      return const Center(
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      );
                                    },
                                errorBuilder: (context, error, stackTrace) =>
                                    const Center(
                                      child: Icon(
                                        Icons.broken_image,
                                        color: Colors.grey,
                                      ),
                                    ),
                              ),
                            ),
                          ),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            decoration: const BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.vertical(
                                bottom: Radius.circular(11),
                              ),
                            ),
                            child: Text(
                              table.name,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              final pdf = await BaseGenerator.newDocument();
              for (final table in tables) {
                final tableUrl = '$menuUrl?table=${table.id}';
                pdf.addPage(
                  pw.Page(
                    pageFormat: PdfPageFormat.a4,
                    // بدونه تؤول الصفحةُ إلى LTR فلا تُشكَّل «طاولة …» ولا
                    // يُعاد ترتيبُها. وهذه الصفحةُ تعيش في طبقة العرض بعيداً
                    // عن خدمات الطباعة، فنجت من كلّ تدقيقٍ سابق.
                    textDirection: pw.TextDirection.rtl,
                    build: (context) => pw.Center(
                      child: pw.Column(
                        mainAxisAlignment: pw.MainAxisAlignment.center,
                        children: [
                          pw.Text(
                            'طاولة ${table.name}',
                            style: pw.TextStyle(
                              fontSize: 24,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.SizedBox(height: 20),
                          pw.BarcodeWidget(
                            data: tableUrl,
                            barcode: pw.Barcode.qrCode(),
                            width: 200,
                            height: 200,
                          ),
                          pw.SizedBox(height: 12),
                          pw.Text(
                            tableUrl,
                            style: const pw.TextStyle(fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
              await printing_pkg.Printing.layoutPdf(
                onLayout: (format) async => pdf.save(),
              );
            },
            icon: const Icon(PhosphorIconsBold.printer),
            label: const Text('طباعة الكل'),
          ),
        ],
      ),
    );
  }
}
