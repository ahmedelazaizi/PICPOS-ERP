import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../../services/api/table_bill_token.dart';
import '../../../services/generators/base_generator.dart';
import '../../../services/network_service.dart';
import '../../../services/printing/pdf_compute_helper.dart';

/// أكوادُ حسابِ الطاولات — ورقةٌ تُطبَع وتُلصَق على كلّ طاولة.
///
/// ⚠️ **وهذا غيرُ «المنيو الرقمي»** (‏`QrMenuDialog`): ذاك يعرض الأصنافَ
/// للطلب، وهذا يعرض **حسابَ الطاولة الجاري** لمن يجلس عليها.
///
/// ⚠️ **ولا يُرسَم رمزٌ من خدمةٍ على الإنترنت.** الحوارُ الأخُ يبني صورةَ
/// المعاينة من `api.qrserver.com`، فمطعمٌ بلا إنترنت — وهو الحالُ الشائع على
/// شبكةٍ محلّيّةٍ مغلقة — يرى مربّعاتٍ مكسورة. والرمزُ هنا يُولَّد **داخل
/// الورقة** بـ`pw.BarcodeWidget` بلا شبكةٍ أصلاً، والشاشةُ تعرض الرابطَ نصّاً.
class TableBillQrDialog extends ConsumerWidget {
  const TableBillQrDialog({super.key, required this.tables});

  final List<RestaurantTable> tables;

  static Future<void> show(
    BuildContext context,
    List<RestaurantTable> tables,
  ) =>
      showDialog<void>(
        context: context,
        builder: (_) => TableBillQrDialog(tables: tables),
      );

  /// رابطُ حسابِ الطاولة كما يُوضَع في الرمز.
  ///
  /// ⚠️ ويُبنى بمخطَّط **هذا** الخادم لا بمخطَّط خادمٍ بعيد: الورقةُ تُطبَع
  /// على الجهاز الذي يستضيف، و`remoteHttpScheme` على جهاز خادمٍ يساوي `http`
  /// دائماً لأن لا خادمَ بعيداً عنده — فيُطبَع رابطٌ لا يفتح على TLS.
  static String? urlFor(RestaurantTable table) {
    final ns = NetworkService.instance;
    final host = ns.serverAddress;
    if (host == null || host.isEmpty) return null;
    if (!TableBillToken.isReady) return null;
    return '${ns.httpScheme}://$host:${ns.serverPort}'
        '/t/${TableBillToken.mintTable(table.id)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(_tableBillEnabledProvider);
    final ns = NetworkService.instance;
    final serving = ns.isServer && ns.isServerRunning;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Row(
          children: [
            Icon(PhosphorIconsBold.qrCode, color: AppColors.primary),
            SizedBox(width: 8),
            Text('أكواد حساب الطاولات'),
          ],
        ),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ⚠️ **ثلاثةُ شروطٍ تُعرَض صراحةً ولا يُترَك فشلُها للتخمين.**
              // ورقةٌ تُطبَع والميزةُ مطفأةٌ أو الخادمُ لا يعمل هي ورقةٌ
              // تُلصَق على الطاولات ولا تفتح شيئاً — ولا يكتشف ذلك إلّا ضيف.
              if (!serving)
                _banner(
                  icon: PhosphorIconsBold.wifiSlash,
                  color: AppColors.error,
                  text: 'الجهازُ ليس خادماً يعمل — الرابطُ لن يفتح على هواتف '
                      'الضيوف. شغّل وضعَ الخادم أوّلاً.',
                ),
              // ⚠️ **المفتاحُ هنا لا في شاشة الإعدادات.** هذا هو الموضعُ
              // الذي يُطبَع منه الرمز؛ ومفتاحٌ في شاشةٍ أخرى يعني ورقةً
              // تُطبَع وتُلصَق ثمّ يُكتشَف أن الميزةَ مطفأة. وحارسُه هو
              // حارسُ فتح هذا الحوار نفسُه (`tables_manage`).
              if (serving)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: enabled.asData?.value ?? false,
                  title: const Text(
                    'تفعيل رمز حساب الطاولة',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  subtitle: const Text(
                    'يفتح مساراً على شبكة المحلّ يقرأ منه الضيفُ حسابَ طاولته '
                    'بلا تسجيل دخول. أطفِئه إن لم تكن تستعمله.',
                    style: TextStyle(fontSize: 11.5),
                  ),
                  onChanged: enabled.isLoading
                      ? null
                      : (v) async {
                          await ref
                              .read(databaseProvider)
                              .setSetting(kTableBillQrEnabledKey, '$v');
                          ref.invalidate(_tableBillEnabledProvider);
                        },
                ),
              const SizedBox(height: 8),
              Flexible(
                child: tables.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text('لا طاولات في النطاق المعروض'),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: tables.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final table = tables[i];
                          final url = urlFor(table);
                          return ListTile(
                            dense: true,
                            title: Text(
                              table.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              url ?? 'لا رابط — الخادمُ غيرُ مهيّأ',
                              style: TextStyle(
                                fontSize: 11,
                                color: url == null
                                    ? AppColors.error
                                    : AppColors.textMuted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: url == null
                                ? null
                                : IconButton(
                                    icon: const Icon(PhosphorIconsBold.copy,
                                        size: 16),
                                    tooltip: 'نسخ الرابط',
                                    onPressed: () async {
                                      await Clipboard.setData(
                                          ClipboardData(text: url));
                                      if (context.mounted) {
                                        AppToast.show(context, 'نُسخ الرابط');
                                      }
                                    },
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
            onPressed: tables.isEmpty ? null : () => _printSheets(context),
            icon: const Icon(PhosphorIconsBold.printer),
            label: const Text('طباعة الأكواد'),
          ),
        ],
      ),
    );
  }

  Widget _banner({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5))),
        ],
      ),
    );
  }

  Future<void> _printSheets(BuildContext context) async {
    final withUrls = <(RestaurantTable, String)>[
      for (final t in tables)
        if (urlFor(t) case final url?) (t, url),
    ];
    if (withUrls.isEmpty) {
      AppToast.show(context, 'لا رابطَ يُطبَع — الخادمُ غيرُ مهيّأ');
      return;
    }

    final pdf = await BaseGenerator.newDocument();
    for (final (table, url) in withUrls) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          // بدونه تؤول الصفحةُ إلى LTR فلا تُشكَّل «طاولة …» ولا يُعاد ترتيبُها.
          textDirection: pw.TextDirection.rtl,
          build: (context) => pw.Center(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text(
                  'طاولة ${table.name}',
                  style: pw.TextStyle(
                    fontSize: 30,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Text('امسح الرمز لترى حسابك', style: const pw.TextStyle(fontSize: 15)),
                pw.SizedBox(height: 22),
                pw.BarcodeWidget(
                  data: url,
                  barcode: pw.Barcode.qrCode(),
                  width: 230,
                  height: 230,
                ),
                pw.SizedBox(height: 18),
                pw.Text(
                  'الاتّصالُ بشبكة المحلّ شرطٌ لفتح الرابط',
                  style: const pw.TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      );
    }
    await PdfComputeHelper.layoutPdf(pdf);
  }
}

/// هل الميزةُ مُشعَلة؟ يُقرأ من القاعدة مباشرةً.
///
/// ⚠️ **ولا يمرّ بالإعدادات المخزَّنة**: تلك تُرجع `null` عند إخفاق الكاش لا
/// عند غياب المفتاح، ومفتاحٌ غيرُ مسجَّلٍ في `preloadKeys` يُقرأ فارغاً دوماً
/// — فتبدو الميزةُ مطفأةً وهي مُشعَلة، والمستخدمُ يُشعلها مرّتين.
final _tableBillEnabledProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  return (await db.getSettingValue(kTableBillQrEnabledKey)) == 'true';
});
