// ═══════════════════════════════════════════════════════════════════════════
//  مولّدُ صور معالج التثبيت (Inno Setup) — بمحرّك Flutter لا بـPillow.
//
//  الأمر:  flutter test tool/gen_installer_art.dart
//  المخرَج: installer/assets/wizard-{large,small}-<brand>[-<scale>].bmp
//
//  ── لماذا Flutter بدل Python ──────────────────────────────────────────────
//  المولّدُ السابقُ (`installer/make_wizard_images.py`) يرسم بـPillow، وPillow
//  **لا تشكّل العربيّة ولا تعكس اتّجاهها** — فالنصُّ يخرج حروفاً منفصلةً
//  مقلوبة. ولذلك حمل ذلك الملفُّ تحذيراً صريحاً ووُضع نصٌّ لاتينيٌّ في صورة
//  PicPos هرباً من العطب. ومحرّكُ Flutter يشكّل ويعكس صحيحاً، فيزول السببُ
//  من جذره بدل الالتفاف عليه. وPython ليست مثبَّتةً على جهاز البناء أصلاً.
//
//  ── ولماذا NotoNaskhArabic لا Cairo ───────────────────────────────────────
//  ⚠️ `Cairo-Regular.ttf` ينقصه **١٦** من أشكال العرض العربيّة و**٥** من
//  العربيّة الأساسيّة — ومنها الياءُ المنفصلة `U+FEF1`. وهو مقيسٌ وموثَّقٌ في
//  `pubspec.yaml` عند إعلان الخطوط: كلُّ كلمةٍ آخرُها ي بعد حرفٍ غيرِ موصولٍ
//  كانت تُطبع ناقصة. فالخطُّ الكاملُ هو `NotoNaskhArabic` وهو المستعمَلُ هنا.
//  (المولّدُ القديمُ كان يحمّل Cairo — سببٌ ثانٍ لعدم الوثوق بمخرَجه العربيّ.)
//
//  ── والشعارُ أصلٌ حقيقيٌّ لا حرفٌ مرسوم ────────────────────────────────────
//  `assets/brand/picpos/logo.png` هو الشعارُ الذي يقرؤه التطبيقُ نفسُه
//  (`Brand.logoAsset`). فاستعمالُه هنا يجعل أوّلَ ما يراه العميلُ في المثبِّت
//  هو **عينَ** العلامة التي سيراها في التطبيق — لا محاكاةً لها. ويُرسَم
//  بمرشّح لونٍ أبيضَ لأنّ أصلَه أزرقُ على شفّاف، ولا يُقرأ على تدرّجٍ أزرق.
//
//  ── وأربعةُ مقاسات ────────────────────────────────────────────────────────
//  Inno 6 يختار الصورةَ بمطابقة المقاس لنسبة تكبير الشاشة. صورةٌ واحدةٌ عند
//  ١٦٤×٣١٤ تُمطّ على شاشات ١٥٠٪ و٢٠٠٪ فتظهر ضبابيّة. فتُولَّد أربعةٌ لكلٍّ.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// ── هويّةُ كلِّ علامة ────────────────────────────────────────────────────────
//
// القيمُ مأخوذةٌ من `lib/core/theme/app_colors.dart` — لا مخترَعةٌ هنا. تغييرُ
// لون العلامة في الثيم بلا تغييره هنا يُنتج مثبِّتاً بلونٍ آخرَ غير التطبيق.
class _BrandArt {
  const _BrandArt({
    required this.id,
    required this.dark,
    required this.mid,
    required this.accent,
    required this.logoAsset,
    required this.wordLatin,
    required this.taglineArabic,
  });

  final String id;
  final Color dark;
  final Color mid;
  final Color accent;

  /// `null` ⇒ لا شعارَ مُحزَّمٌ لهذه العلامة، فيُرسَم الحرفُ الأوّلُ بديلاً.
  final String? logoAsset;
  final String wordLatin;

  /// عربيٌّ مشكولُ الاتّصال — يعمل هنا ولا يعمل في المولّد القديم.
  final String taglineArabic;
}

const _brands = <_BrandArt>[
  _BrandArt(
    id: 'picpos',
    dark: Color(0xFF012258),
    mid: Color(0xFF0250D3),
    accent: Color(0xFF5A96F0),
    logoAsset: 'assets/brand/picpos/logo.png',
    wordLatin: 'PicPos',
    taglineArabic: 'نظامُ نقاطِ البيع وإدارةِ الأعمال',
  ),
  // UralCash يبقى على ألوانه المشحونة — إعادةُ توليده تُنتج فنّاً مكافئاً
  // للقديم لا مطابقاً له بالبِكسل، فلا تُعِد توليده إلّا بقرار.
  _BrandArt(
    id: 'uralcash',
    dark: Color(0xFF134657),
    mid: Color(0xFF2B737F),
    accent: Color(0xFF469CA5),
    logoAsset: null,
    wordLatin: 'UralCash',
    taglineArabic: 'نظامُ إدارةِ الأعمال',
  ),
];

/// مقاساتُ Inno الأربعة: ١٠٠٪ · ١٢٥٪ · ١٥٠٪ · ٢٠٠٪.
const _largeSizes = <Size>[
  Size(164, 314),
  Size(205, 393),
  Size(246, 471),
  Size(328, 628),
];
const _smallSizes = <Size>[
  Size(55, 58),
  Size(69, 73),
  Size(83, 87),
  Size(110, 116),
];

/// اللاحقةُ التي يتوقّعها Inno لكلّ مقاس؛ الأوّلُ بلا لاحقة.
const _scaleSuffix = <String>['', '-125', '-150', '-200'];

void main() {
  // ⚠️ `flutter test` لا `dart run`: الرسمُ يحتاج محرّكَ Flutter لتشكيل
  //    العربيّة ورَسْترة الصورة، و`rootBundle` لقراءة الخطّ والشعار.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('توليدُ صور معالج التثبيت', () async {
    final fontLoader = FontLoader('InstallerArabic')
      ..addFont(rootBundle.load('assets/fonts/NotoNaskhArabic-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/NotoNaskhArabic-Bold.ttf'));
    await fontLoader.load();

    final outDir = Directory('installer/assets');
    if (!outDir.existsSync()) outDir.createSync(recursive: true);

    for (final brand in _brands) {
      // العلامةُ الوحيدةُ المطلوبةُ افتراضاً هي PicPos — انظر تعليقَ UralCash.
      if (brand.id != 'picpos') continue;

      final logo = brand.logoAsset == null
          ? null
          : await _loadImage(brand.logoAsset!);

      for (var i = 0; i < _largeSizes.length; i++) {
        final bytes = await _rasterize(
          _largeSizes[i],
          (canvas, size) => _paintLarge(canvas, size, brand, logo),
        );
        _writeBmp(
          '${outDir.path}/wizard-large-${brand.id}${_scaleSuffix[i]}.bmp',
          bytes,
          _largeSizes[i],
        );
      }

      for (var i = 0; i < _smallSizes.length; i++) {
        final bytes = await _rasterize(
          _smallSizes[i],
          (canvas, size) => _paintSmall(canvas, size, brand, logo),
        );
        _writeBmp(
          '${outDir.path}/wizard-small-${brand.id}${_scaleSuffix[i]}.bmp',
          bytes,
          _smallSizes[i],
        );
      }
    }

    // مرساة: الملفُّ الأساسيُّ كُتب فعلاً وليس فارغاً.
    final probe = File('${outDir.path}/wizard-large-picpos.bmp');
    expect(probe.existsSync(), isTrue, reason: 'الصورةُ الأساسيّةُ لم تُكتَب');
    expect(probe.lengthSync(), greaterThan(1000),
        reason: 'الملفُّ أصغرُ من أن يحمل صورة');
  });
}

// ── الرسم ──────────────────────────────────────────────────────────────────

/// اللوحةُ الجانبيّةُ الكبيرة: تدرّجٌ · شريطٌ مائلٌ خافت · حلقاتٌ · شعارٌ ·
/// اسمٌ لاتينيٌّ · وسطرٌ عربيٌّ **مشكولُ الاتّصال**.
void _paintLarge(Canvas canvas, Size size, _BrandArt b, ui.Image? logo) {
  final w = size.width;
  final h = size.height;
  final k = h / 314.0; // معاملُ التحجيم عن المقاس المرجعيّ

  canvas.drawRect(
    Offset.zero & size,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(0, h),
        [b.dark, b.mid],
      ),
  );

  // شريطٌ مائلٌ خافت — يكسر رتابةَ التدرّج بلا ضجيج.
  canvas.drawPath(
    Path()
      ..moveTo(0, 210 * k)
      ..lineTo(w, 150 * k)
      ..lineTo(w, 190 * k)
      ..lineTo(0, 250 * k)
      ..close(),
    Paint()..color = b.accent.withValues(alpha: 0.24),
  );

  // حلقاتٌ متراكزة — إيحاءُ آلةِ تسجيلٍ/عملة، وهي موروثةٌ من الفنّ الأصليّ.
  final cx = w / 2;
  final cy = 92 * k;
  for (final (r, a) in [(52.0, 0.16), (40.0, 0.24), (28.0, 0.35)]) {
    canvas.drawCircle(
      Offset(cx, cy),
      r * k,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * k
        ..color = Colors.white.withValues(alpha: a),
    );
  }

  if (logo != null) {
    // الشعارُ أبيضَ: أصلُه أزرقُ على شفّاف، ولا يُقرأ على تدرّجٍ أزرق.
    // `srcIn` يُبقي قناةَ الشفافيّة ويستبدل اللون — فيبقى شكلُ الحروف كما هو.
    final target = 74.0 * k;
    final scale = target / logo.width;
    final dw = logo.width * scale;
    final dh = logo.height * scale;
    canvas.drawImageRect(
      logo,
      Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
      Rect.fromLTWH(cx - dw / 2, cy - dh / 2, dw, dh),
      Paint()
        ..colorFilter = const ColorFilter.mode(Colors.white, BlendMode.srcIn)
        ..filterQuality = FilterQuality.high,
    );
  } else {
    _text(canvas, b.wordLatin.substring(0, 1), Offset(cx, cy),
        size: 46 * k, color: Colors.white, bold: true, center: true);
  }

  // الاسمُ اللاتينيُّ: النصفُ الأوّلُ أبيضُ والثاني بلون التمييز — نفسُ
  // التقسيمِ في الفنّ الأصليّ.
  //
  // ⚠️ **الكتلتان تُتوسَّطان معاً لا كلٌّ على حدة**: المنتَجُ عربيُّ الاتّجاه،
  //    فاسمٌ لاتينيٌّ مرصوصٌ لليسار وسطرٌ عربيٌّ مرصوصٌ لليمين يقرآن مفكَّكَين.
  //    والتوسيطُ يجعلهما كتلةً واحدةً تحت الشعار المتوسّط أصلاً.
  final head = b.wordLatin.substring(0, (b.wordLatin.length / 2).ceil());
  final tail = b.wordLatin.substring((b.wordLatin.length / 2).ceil());
  final headPara = _paragraph(head, 26 * k, Colors.white, bold: true);
  final tailPara = _paragraph(tail, 26 * k, b.accent, bold: true);
  final wordWidth = headPara.maxIntrinsicWidth + tailPara.maxIntrinsicWidth;
  final wordLeft = cx - wordWidth / 2;
  canvas.drawParagraph(headPara, Offset(wordLeft, 244 * k));
  canvas.drawParagraph(
    tailPara,
    Offset(wordLeft + headPara.maxIntrinsicWidth, 244 * k),
  );

  // السطرُ العربيُّ — هذا هو ما لم يستطعه المولّدُ القديم. يُرسَم في صندوقٍ
  // بعرض اللوحة و`TextAlign.center` فيتوسّط تحت الاسم بلا حسابِ عرضٍ يدويّ.
  canvas.drawParagraph(
    _paragraph(
      b.taglineArabic,
      11.5 * k,
      Colors.white.withValues(alpha: 0.86),
      rtl: true,
      center: true,
      maxWidth: w - 20 * k,
    ),
    Offset(10 * k, 283 * k),
  );
}

/// الأيقونةُ الصغيرةُ في رأس الصفحات الداخليّة.
void _paintSmall(Canvas canvas, Size size, _BrandArt b, ui.Image? logo) {
  final w = size.width;
  final h = size.height;
  final k = h / 58.0;

  canvas.drawRect(Offset.zero & size, Paint()..color = b.mid);
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(4 * k, 4 * k, w - 9 * k, h - 9 * k),
      Radius.circular(10 * k),
    ),
    Paint()..color = b.dark,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(4 * k, 4 * k, w - 9 * k, h - 9 * k),
      Radius.circular(10 * k),
    ),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * k
      ..color = b.accent,
  );

  if (logo != null) {
    final target = w * 0.62;
    final scale = target / logo.width;
    final dw = logo.width * scale;
    final dh = logo.height * scale;
    canvas.drawImageRect(
      logo,
      Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
      Rect.fromLTWH(w / 2 - dw / 2, h / 2 - dh / 2, dw, dh),
      Paint()
        ..colorFilter = const ColorFilter.mode(Colors.white, BlendMode.srcIn)
        ..filterQuality = FilterQuality.high,
    );
  } else {
    _text(canvas, b.wordLatin.substring(0, 1), Offset(w / 2, h / 2),
        size: 30 * k, color: Colors.white, bold: true, center: true);
  }
}

// ── أدواتُ النصّ والرَسْترة ──────────────────────────────────────────────────

ui.Paragraph _paragraph(
  String text,
  double size,
  Color color, {
  bool bold = false,
  bool rtl = false,
  bool center = false,
  double maxWidth = 1000,
}) {
  final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
    fontFamily: 'InstallerArabic',
    fontSize: size,
    fontWeight: bold ? FontWeight.bold : FontWeight.normal,
    textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
    textAlign: center
        ? TextAlign.center
        : (rtl ? TextAlign.right : TextAlign.left),
    maxLines: 2,
  ))
    ..pushStyle(ui.TextStyle(color: color))
    ..addText(text);
  return builder.build()
    ..layout(ui.ParagraphConstraints(width: maxWidth));
}

void _text(
  Canvas canvas,
  String text,
  Offset at, {
  required double size,
  required Color color,
  bool bold = false,
  bool center = false,
}) {
  final p = _paragraph(text, size, color, bold: bold);
  final dx = center ? at.dx - p.maxIntrinsicWidth / 2 : at.dx;
  final dy = center ? at.dy - p.height / 2 : at.dy;
  canvas.drawParagraph(p, Offset(dx, dy));
}

/// يرسم على لوحةٍ ويُعيد البِكسلات `RGBA` خامّة.
Future<Uint8List> _rasterize(
  Size size,
  void Function(Canvas canvas, Size size) paint,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Offset.zero & size);
  paint(canvas, size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.toInt(), size.height.toInt());
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return data!.buffer.asUint8List();
}

Future<ui.Image> _loadImage(String asset) async {
  final data = await rootBundle.load(asset);
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  return (await codec.getNextFrame()).image;
}

/// يكتب BMP بعمق ٢٤ بت.
///
/// ⚠️ **ثلاثُ مصائدَ في صيغة BMP، كلُّها هنا عمداً:**
///   ‏١) صفوفُ البِكسل مخزَّنةٌ **من الأسفل إلى الأعلى**؛
///   ‏٢) ترتيبُ القنوات `BGR` لا `RGB`؛
///   ‏٣) طولُ كلِّ صفٍّ يُحشى إلى مضاعَفِ **٤ بايتات**.
/// وإغفالُ أيٍّ منها يُنتج ملفّاً يفتحه العارضُ ويرفضه Inno أو يقلبه رأساً
/// على عقب. و**Inno لا يقبل PNG ولا BMP بشفافيّة** — ٢٤ بت مصمَتٌ هو العقد.
void _writeBmp(String path, Uint8List rgba, Size size) {
  final w = size.width.toInt();
  final h = size.height.toInt();
  final rowRaw = w * 3;
  final pad = (4 - (rowRaw % 4)) % 4;
  final rowPadded = rowRaw + pad;
  final pixelBytes = rowPadded * h;
  const headerSize = 54;

  final out = BytesBuilder();

  // ── رأسُ الملفّ (١٤ بايت) ──
  out.add([0x42, 0x4D]); // "BM"
  out.add(_u32(headerSize + pixelBytes));
  out.add(_u32(0)); // محجوز
  out.add(_u32(headerSize));

  // ── رأسُ المعلومات BITMAPINFOHEADER (٤٠ بايت) ──
  out.add(_u32(40));
  out.add(_u32(w));
  out.add(_u32(h)); // موجبٌ ⇒ من الأسفل إلى الأعلى
  out.add(_u16(1)); // مستوىً واحد
  out.add(_u16(24)); // بتّاتٌ لكلّ بكسل
  out.add(_u32(0)); // بلا ضغط
  out.add(_u32(pixelBytes));
  out.add(_u32(2835)); // ~٧٢ نقطةً/بوصة أفقيّاً
  out.add(_u32(2835)); // ورأسيّاً
  out.add(_u32(0)); // كلُّ الألوان
  out.add(_u32(0)); // كلُّها مهمّة

  // ── البِكسلات ──
  final row = Uint8List(rowPadded);
  for (var y = h - 1; y >= 0; y--) {
    row.fillRange(0, rowPadded, 0);
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      // الأصلُ RGBA مضروبٌ سلفاً في ألفا، والخلفيّةُ مصمتةٌ في كلّ تصاميمنا،
      // فالنسخُ المباشرُ صحيحٌ ولا يحتاج مزجاً على أبيض.
      row[x * 3] = rgba[i + 2]; // B
      row[x * 3 + 1] = rgba[i + 1]; // G
      row[x * 3 + 2] = rgba[i]; // R
    }
    out.add(row);
  }

  File(path).writeAsBytesSync(out.takeBytes());
}

List<int> _u32(int v) =>
    [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];

List<int> _u16(int v) => [v & 0xFF, (v >> 8) & 0xFF];
