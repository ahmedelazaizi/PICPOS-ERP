import 'package:flutter/material.dart';
import 'package:picpos_erp/core/i18n/tr.dart';

import '../../../core/theme/app_colors.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../../pos/services/ean13_modules.dart';
import '../../pos/services/scale_barcode_config.dart';
import '../../pos/services/scale_barcode_encoder.dart';

/// معاينةٌ حيّةٌ لباركود EAN-13 مثالٍ من إعداد الميزان الحالي: القضبان +
/// الأرقام مقسّمةً [بادئة][PLU][قيمة][تحقّق] + وصف المثال.
class ScaleBarcodePreview extends StatelessWidget {
  const ScaleBarcodePreview({
    super.key,
    required this.config,
    required this.kind,
  });

  final ScaleBarcodeConfig config;
  final ScaleBarcodeValueKind kind;

  bool get _weight => kind == ScaleBarcodeValueKind.weight;

  @override
  Widget build(BuildContext context) {
    final sample = config.sample(kind);
    final id = _weight ? 'weight' : 'price';
    final title = _weight
        ? tr('معاينة باركود الوزن')
        : tr('معاينة باركود السعر');
    final code = sample.barcode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(
          _weight
              ? tr('منتج تجريبي · PLU {plu} · الوزن {v} كجم', {
                  'plu': ScaleBarcodeConfig.samplePlu,
                  'v': ScaleBarcodeConfig.sampleWeight.toStringAsFixed(3),
                })
              : tr('منتج تجريبي · PLU {plu} · الإجمالي {v}', {
                  'plu': ScaleBarcodeConfig.samplePlu,
                  'v': (ScaleBarcodeConfig.sampleWeight *
                          ScaleBarcodeConfig.sampleUnitPrice)
                      .toStringAsFixed(2),
                }),
          style: TextStyle(fontSize: 12, color: context.picposSecondary),
        ),
        const SizedBox(height: 6),
        if (code == null)
          Text(
            sample.error == ScaleSampleError.valueOverflow
                ? tr('القيمة لا تتسع لخانات القيمة المتبقية — قلّل خانات PLU أو معامل القسمة')
                : tr('لا معاينة: صحّح أخطاء الإعداد أعلاه'),
            key: Key('scale_cfg_preview_${id}_error'),
            style: const TextStyle(color: AppColors.error, fontSize: 12),
          )
        else ...[
          _Bars(code: code),
          const SizedBox(height: 4),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text.rich(
              key: Key('scale_cfg_preview_${id}_code'),
              _segments(context, code),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 15),
            ),
          ),
          if (sample.plu != ScaleBarcodeConfig.samplePlu)
            Text(
              tr('PLU المثال قُصّ إلى {plu} ليتسع لخانات PLU', {
                'plu': sample.plu,
              }),
              style: const TextStyle(color: AppColors.warning, fontSize: 12),
            ),
        ],
      ],
    );
  }

  TextSpan _segments(BuildContext context, String code) {
    final p = config.prefixOf(kind).length;
    final l = config.codeLenOf(kind) ?? 0;
    TextSpan seg(String s, Color c) =>
        TextSpan(text: '$s ', style: TextStyle(color: c));
    return TextSpan(
      children: [
        seg(code.substring(0, p), AppColors.primary),
        seg(code.substring(p, p + l), AppColors.success),
        seg(code.substring(p + l, 12), AppColors.warning),
        seg(code.substring(12), context.picposSecondary),
      ],
    );
  }
}

class _Bars extends StatelessWidget {
  const _Bars({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    final modules = ean13Modules(code) ?? const <bool>[];
    return Container(
      width: 230,
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      // dark-ok: ورقة ملصق — القضبان تحتاج خلفية بيضاء ليقرأها الماسح من الشاشة
      color: Colors.white,
      child: CustomPaint(painter: _BarsPainter(modules)),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.modules);
  final List<bool> modules;

  @override
  void paint(Canvas canvas, Size size) {
    if (modules.isEmpty) return;
    final w = size.width / modules.length;
    // dark-ok: قضبان سوداء على ورقة بيضاء ثابتة
    final paint = Paint()..color = Colors.black;
    for (var i = 0; i < modules.length; i++) {
      if (modules[i]) {
        canvas.drawRect(Rect.fromLTWH(i * w, 0, w, size.height), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.modules != modules;
}
