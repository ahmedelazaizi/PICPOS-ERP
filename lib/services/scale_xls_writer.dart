/// كاتب ملف PLU لموازين NVK TMA و TEM (البرنامج الرسمي `mscale`).
///
/// ## لماذا هذا الملف موجود
///
/// بلاغ العميل 2026-07-30: موازين NVK و TEM لا تُكتشف بالـIP. تفكيك ملفَّي
/// تصدير حقيقيين من `mscale` (النسخة EN3.1 المرفقة مع TM-A20B / TM-21) أثبت
/// أن مسار الرفع الحالي لم يكن ليعمل بأي إعداد: الكود يرسل بايتات
/// `STX + "PLUSTART" + ETX` أو نصاً بصيغة CSV، بينما البرنامج يقرأ **مصنَّف
/// Excel BIFF8**. صيغة مختلفة تماماً — لا «منفذ خطأ» ولا «IP خطأ».
///
/// ومسار التكامل الحقيقي ليس شبكياً أصلاً:
/// ```
/// UralCash → ملف .xls → [mscale: Import] → [mscale: Download] → الميزان
/// ```
/// `mscale` هو مالك الاتصال بالميزان، لا نحن.
///
/// ## البنية المستخلَصة من الملفين (حقيقة أرضية، لا افتراض)
///
/// حاوية OLE2/CFB، تدفّق `Workbook` بصيغة BIFF8، ورقة اسمها `Merchandise`،
/// الصف 0 ترويسة، وتسعة أعمدة بهذا الترتيب:
///
/// | # | العمود | النوع | ملاحظة |
/// |---|---|---|---|
/// | 0 | `PLU NO`    | رقم | |
/// | 1 | `Name`      | **نص** | العربي يُخزَّن UTF-16 في الـSST |
/// | 2 | `Code`      | **نص** | الأصفار البادئة محفوظة (`0065765`) |
/// | 3 | `Price`     | رقم | عملة عادية بكسور — **بلا أي ضرب** (10.5 · 12.76) |
/// | 4 | `Mode`      | رقم | `0` وزن · `1` عدد بالقطعة |
/// | 5 | `Shelflife` | رقم | |
/// | 6 | `Tare`      | رقم | |
/// | 7 | `Label NO`  | رقم | رقم قالب الملصق داخل الميزان |
/// | 8 | `Shop NO`   | رقم | |
///
/// `Code` نص وليس رقماً: كتابته رقماً تُسقط الصفر البادئ فيتحوّل `0065765`
/// إلى `65765` — والباركود يفسد بصمت.
///
/// ## لماذا كاتب يدوي بدل حزمة جاهزة
///
/// حزمة `excel` في Dart تكتب **`.xlsx` (OOXML)**، وهي صيغة مختلفة كلياً عن
/// **`.xls` (BIFF8)**. الملف الأصلي كتبه محرّك Microsoft JET (بصمة
/// `[Microsoft JET Created Table]` داخله)، فمسار الاستيراد يقرأ BIFF8.
///
/// ## ما يمكن التحقق منه بلا جهاز
///
/// الناتج هنا قابل للتفكيك والفحص آلياً — انظر
/// `test/unit/scale_xls_writer_test.dart`. لأول مرة يمكن اختبار تكامل ميزان
/// دون امتلاك الميزان.
library;

import 'dart:typed_data';

/// صنف واحد في ورقة `Merchandise`.
class MerchandiseRow {
  /// رقم الـPLU داخل الميزان.
  final int pluNo;

  /// اسم الصنف كما يُطبع على الملصق. العربي مدعوم على مستوى الملف
  /// (UTF-16)، لكن عرضه في `mscale` يتوقف على ترميز نظام ويندوز — انظر
  /// ملاحظة العربي في نهاية الملف.
  final String name;

  /// كود الصنف. **نص** — الأصفار البادئة جزء من الكود.
  final String code;

  /// السعر بعملة عادية بكسور (10.5 = عشرة ونصف).
  final double price;

  /// `0` = وزن · `1` = عدد بالقطعة. استخدم [MerchandiseMode].
  final int mode;

  /// مدة الصلاحية (بالأيام حسب إعداد الميزان).
  final int shelfLife;

  /// وزن الفارغ.
  final double tare;

  /// رقم قالب الملصق المخزَّن داخل الميزان.
  final int labelNo;

  /// رقم المحل/الفرع.
  final int shopNo;

  const MerchandiseRow({
    required this.pluNo,
    required this.name,
    required this.code,
    required this.price,
    this.mode = MerchandiseMode.weight,
    this.shelfLife = 0,
    this.tare = 0,
    this.labelNo = 0,
    this.shopNo = 0,
  });
}

/// قيم عمود `Mode` كما يعرضها `mscale` نصّاً.
abstract final class MerchandiseMode {
  /// يُعرض في mscale كـ `weight`.
  static const int weight = 0;

  /// يُعرض في mscale كـ `count by Pieces`.
  static const int countByPieces = 1;
}

/// ترويسة الورقة — الأسماء والترتيب مأخوذان حرفياً من ملف التصدير الحقيقي.
/// أي تغيير هنا يكسر الاستيراد في `mscale`.
const List<String> kMerchandiseHeaders = [
  'PLU NO',
  'Name',
  'Code',
  'Price',
  'Mode',
  'Shelflife',
  'Tare',
  'Label NO',
  'Shop NO',
];

/// اسم الورقة داخل المصنَّف. `mscale` يبحث عن هذا الاسم تحديداً.
const String kMerchandiseSheetName = 'Merchandise';

/// يبني ملف `.xls` (OLE2 + BIFF8) جاهزاً للاستيراد في `mscale`.
Uint8List buildMerchandiseXls(List<MerchandiseRow> rows) {
  final workbook = _buildWorkbookStream(rows);
  return _wrapInOle2(workbook);
}

// ═══════════════════════════════════════════════════════════════════════
// BIFF8 — تدفّق Workbook
// ═══════════════════════════════════════════════════════════════════════

class _ByteWriter {
  final BytesBuilder _b = BytesBuilder();
  int get length => _b.length;
  void u8(int v) => _b.addByte(v & 0xFF);
  void u16(int v) => _b.add([v & 0xFF, (v >> 8) & 0xFF]);
  void u32(int v) =>
      _b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
  void f64(double v) {
    final d = ByteData(8)..setFloat64(0, v, Endian.little);
    _b.add(d.buffer.asUint8List());
  }

  void bytes(List<int> v) => _b.add(v);
  Uint8List take() => _b.toBytes();
}

/// سجل BIFF: [نوع u16][طول u16][بيانات].
Uint8List _rec(int type, Uint8List data) {
  final w = _ByteWriter()
    ..u16(type)
    ..u16(data.length)
    ..bytes(data);
  return w.take();
}

/// هل تحتاج السلسلة تخزيناً بـUTF-16؟ ASCII يُخزَّن مضغوطاً بايتاً لكل حرف،
/// وهو ما يفعله الملف الأصلي بالضبط (الترويسات والأكواد مضغوطة، والأسماء
/// العربية UTF-16).
bool _needsUtf16(String s) => s.codeUnits.any((c) => c > 0xFF);

/// سلسلة SST: [طول u16][أعلام u8][الأحرف].
Uint8List _sstString(String s) {
  final w = _ByteWriter()..u16(s.length);
  if (_needsUtf16(s)) {
    w.u8(0x01); // bit0 = 1 ⇒ UTF-16LE
    for (final c in s.codeUnits) {
      w.u16(c);
    }
  } else {
    w.u8(0x00); // مضغوطة — بايت لكل حرف
    w.bytes(s.codeUnits);
  }
  return w.take();
}

/// سلسلة قصيرة (طول بايت واحد) — تُستخدم لاسم الورقة واسم الخط.
Uint8List _shortString(String s) {
  final w = _ByteWriter()..u8(s.length);
  if (_needsUtf16(s)) {
    w.u8(0x01);
    for (final c in s.codeUnits) {
      w.u16(c);
    }
  } else {
    w.u8(0x00);
    w.bytes(s.codeUnits);
  }
  return w.take();
}

Uint8List _bof(int docType) {
  final w = _ByteWriter()
    ..u16(0x0600) // BIFF8
    ..u16(docType) // 0x0005 globals · 0x0010 worksheet
    ..u16(0x0DBB)
    ..u16(0x07CC)
    ..u32(0x00000041)
    ..u32(0x00000006);
  return _rec(0x0809, w.take());
}

Uint8List _eof() => _rec(0x000A, Uint8List(0));

/// الحد الأدنى من سجلات FONT و XF. تركها يجعل بعض القارئات ترفض الملف،
/// فالتكلفة هنا سطور قليلة مقابل إزالة فئة كاملة من الفشل.
Uint8List _fontsAndXfs() {
  final out = BytesBuilder();

  Uint8List font() {
    final w = _ByteWriter()
      ..u16(200) // ارتفاع الخط (1/20 نقطة)
      ..u16(0) // أعلام
      ..u16(0x7FFF) // لون تلقائي
      ..u16(400) // وزن عادي
      ..u16(0) // بلا رفع/خفض
      ..u8(0) // بلا تسطير
      ..u8(0) // عائلة
      ..u8(0) // مجموعة محارف
      ..u8(0)
      ..bytes(_shortString('Arial'));
    return _rec(0x0031, w.take());
  }

  // BIFF8 يتطلّب أربعة سجلات FONT كحدّ أدنى (الفهرس 4 محجوز تاريخياً).
  for (var i = 0; i < 4; i++) {
    out.add(font());
  }

  Uint8List xf({required bool style}) {
    final w = _ByteWriter()
      ..u16(0) // ifnt
      ..u16(0) // ifmt — عام
      // bit0 مقفل · bit2 نمط · bits4-15 فهرس الأب (0xFFF للأنماط)
      ..u16(style ? 0xFFF5 : 0x0001)
      ..u8(0x20) // محاذاة عامة/أسفل
      ..u8(0)
      ..u8(0)
      ..u8(0)
      ..u32(0) // حدود
      ..u32(0)
      ..u16(0); // تعبئة
    return _rec(0x00E0, w.take());
  }

  // 15 سجل نمط ثم سجلات الخلايا. الفهرس 15 هو أول XF صالح للخلايا، وهو
  // ما تشير إليه كل الخلايا المكتوبة أدناه.
  for (var i = 0; i < 15; i++) {
    out.add(xf(style: true));
  }
  out.add(xf(style: false));

  return out.toBytes();
}

const int _cellXf = 15;

Uint8List _buildWorkbookStream(List<MerchandiseRow> rows) {
  // ── جدول السلاسل المشترك (SST) ──
  // كل نص في الورقة يدخل هنا مرة واحدة، والخلية تشير إليه بفهرس. هذا ما
  // يفعله الملف الأصلي، وهو ما يحفظ العربي بـUTF-16 سليماً.
  final sstIndex = <String, int>{};
  final sstOrder = <String>[];
  int intern(String s) {
    final existing = sstIndex[s];
    if (existing != null) return existing;
    final i = sstOrder.length;
    sstIndex[s] = i;
    sstOrder.add(s);
    return i;
  }

  for (final h in kMerchandiseHeaders) {
    intern(h);
  }
  for (final r in rows) {
    intern(r.name);
    intern(r.code);
  }

  int totalStringCells = kMerchandiseHeaders.length + rows.length * 2;

  final sstBody = _ByteWriter()
    ..u32(totalStringCells)
    ..u32(sstOrder.length);
  for (final s in sstOrder) {
    sstBody.bytes(_sstString(s));
  }
  final sstData = sstBody.take();
  // سجل BIFF واحد لا يتجاوز 8224 بايت. تجاوز ذلك يستلزم سجلات CONTINUE
  // بتقسيم دقيق للسلاسل — غير مطبَّق، فنمنعه صراحةً بدل إنتاج ملف تالف.
  if (sstData.length > 8224) {
    throw StateError(
      'جدول السلاسل تجاوز 8224 بايت (${sstData.length}). '
      'قسّم التصدير على دفعات أصغر — سجلات CONTINUE غير مدعومة بعد.',
    );
  }

  // ── الورقة ──
  final sheet = BytesBuilder();
  sheet.add(_bof(0x0010));

  final dims = _ByteWriter()
    ..u32(0) // أول صف
    ..u32(rows.length + 1) // آخر صف + 1 (الترويسة + البيانات)
    ..u16(0)
    ..u16(kMerchandiseHeaders.length)
    ..u16(0);
  sheet.add(_rec(0x0200, dims.take()));

  Uint8List labelSst(int row, int col, int isst) {
    final w = _ByteWriter()
      ..u16(row)
      ..u16(col)
      ..u16(_cellXf)
      ..u32(isst);
    return _rec(0x00FD, w.take());
  }

  Uint8List number(int row, int col, double v) {
    final w = _ByteWriter()
      ..u16(row)
      ..u16(col)
      ..u16(_cellXf)
      ..f64(v);
    // NUMBER بدل RK: RK يضغط بعض الأعداد فقط وله حالات حافّة في الكسور،
    // بينما NUMBER يمثّل أي قيمة بدقة مزدوجة دائماً. الفارق في الحجم لا
    // يُذكر لملف بمئات الأصناف.
    return _rec(0x0203, w.take());
  }

  for (var c = 0; c < kMerchandiseHeaders.length; c++) {
    sheet.add(labelSst(0, c, sstIndex[kMerchandiseHeaders[c]]!));
  }

  for (var i = 0; i < rows.length; i++) {
    final r = rows[i];
    final row = i + 1;
    sheet.add(number(row, 0, r.pluNo.toDouble()));
    sheet.add(labelSst(row, 1, sstIndex[r.name]!));
    sheet.add(labelSst(row, 2, sstIndex[r.code]!));
    sheet.add(number(row, 3, r.price));
    sheet.add(number(row, 4, r.mode.toDouble()));
    sheet.add(number(row, 5, r.shelfLife.toDouble()));
    sheet.add(number(row, 6, r.tare));
    sheet.add(number(row, 7, r.labelNo.toDouble()));
    sheet.add(number(row, 8, r.shopNo.toDouble()));
  }

  final window2 = _ByteWriter()
    ..u16(0x06B6) // أعلام عرض قياسية
    ..u16(0)
    ..u16(0)
    ..u32(0x00000040)
    ..u16(0)
    ..u16(0)
    ..u32(0);
  sheet.add(_rec(0x023E, window2.take()));
  sheet.add(_eof());
  final sheetBytes = sheet.toBytes();

  // ── الكتلة العامة ──
  // BOUNDSHEET يحمل **الإزاحة المطلقة** لبداية الورقة داخل التدفّق، فلا
  // يمكن معرفتها قبل بناء الكتلة العامة كاملة. نبنيها مرّتين: الأولى
  // بإزاحة صفرية لقياس طولها، والثانية بالإزاحة الحقيقية. طول السجلات
  // ثابت بين المرّتين لأن الإزاحة حقل u32 بحجم ثابت.
  Uint8List globals(int sheetOffset) {
    final g = BytesBuilder();
    g.add(_bof(0x0005));
    g.add(_rec(0x0042, (_ByteWriter()..u16(1200)).take())); // CODEPAGE = UTF-16
    final w1 = _ByteWriter()
      ..u16(0)
      ..u16(0)
      ..u16(0x4000)
      ..u16(0x2000)
      ..u16(0x0038)
      ..u16(0)
      ..u16(0)
      ..u16(1)
      ..u16(600);
    g.add(_rec(0x003D, w1.take()));
    g.add(_fontsAndXfs());
    final bs = _ByteWriter()
      ..u32(sheetOffset)
      ..u16(0) // مرئية · ورقة عادية
      ..bytes(_shortString(kMerchandiseSheetName));
    g.add(_rec(0x0085, bs.take()));
    g.add(_rec(0x00FC, sstData));
    g.add(_eof());
    return g.toBytes();
  }

  final probe = globals(0);
  final finalGlobals = globals(probe.length);

  final out = BytesBuilder()
    ..add(finalGlobals)
    ..add(sheetBytes);
  return out.toBytes();
}

// ═══════════════════════════════════════════════════════════════════════
// حاوية OLE2 / CFB
// ═══════════════════════════════════════════════════════════════════════

const int _endOfChain = 0xFFFFFFFE;
const int _fatSect = 0xFFFFFFFD;
const int _freeSect = 0xFFFFFFFF;
const int _sectorSize = 512;
const int _miniStreamCutoff = 4096;

/// يغلّف تدفّق `Workbook` في حاوية OLE2 بسيطة:
/// قطاع 0 = جدول FAT · قطاع 1 = الدليل · القطاعات التالية = التدفّق.
Uint8List _wrapInOle2(Uint8List workbook) {
  // التدفّقات الأصغر من 4096 بايت تُخزَّن في التدفّق المصغّر (mini stream)
  // بجدول FAT منفصل. تجنّباً لتلك الطبقة كاملةً نحشو التدفّق ليتجاوز الحدّ
  // فيسكن جدول FAT العادي. الحشو أصفار **بعد** سجل EOF الأخير، وقارئ BIFF
  // لا يزوره أصلاً: الكتلة العامة تنتهي بـEOF، والورقة يُوصَل إليها عبر
  // إزاحة BOUNDSHEET. وكلا الملفين الحقيقيين تجاوز هذا الحدّ طبيعياً.
  final streamLen = workbook.length < _miniStreamCutoff
      ? _miniStreamCutoff
      : workbook.length;
  final padded = Uint8List(streamLen)..setRange(0, workbook.length, workbook);

  final dataSectors = (streamLen + _sectorSize - 1) ~/ _sectorSize;
  const fatSector = 0;
  const dirSector = 1;
  const firstDataSector = 2;

  // ── FAT ──
  final fat = List<int>.filled(_sectorSize ~/ 4, _freeSect);
  fat[fatSector] = _fatSect;
  fat[dirSector] = _endOfChain;
  for (var i = 0; i < dataSectors; i++) {
    final s = firstDataSector + i;
    fat[s] = (i == dataSectors - 1) ? _endOfChain : s + 1;
  }

  // ── الدليل ──
  final dir = Uint8List(_sectorSize);
  void dirEntry(
    int index,
    String name,
    int type, {
    int child = -1,
    int start = _endOfChain,
    int size = 0,
  }) {
    final o = index * 128;
    final units = name.codeUnits;
    for (var i = 0; i < units.length; i++) {
      dir[o + i * 2] = units[i] & 0xFF;
      dir[o + i * 2 + 1] = (units[i] >> 8) & 0xFF;
    }
    final bd = ByteData.sublistView(dir);
    bd.setUint16(o + 64, (units.length + 1) * 2, Endian.little); // طول الاسم
    dir[o + 66] = type; // 5 = جذر · 2 = تدفّق · 0 = غير مستخدم
    dir[o + 67] = 1; // أسود
    bd.setInt32(o + 68, -1, Endian.little); // يسار
    bd.setInt32(o + 72, -1, Endian.little); // يمين
    bd.setInt32(o + 76, child, Endian.little);
    bd.setUint32(o + 116, start, Endian.little);
    bd.setUint32(o + 120, size, Endian.little);
  }

  dirEntry(0, 'Root Entry', 5, child: 1);
  dirEntry(1, 'Workbook', 2, start: firstDataSector, size: streamLen);
  // الفهرسان 2 و3 يبقيان أصفاراً (نوع 0 = غير مستخدم).

  // ── الترويسة ──
  final header = Uint8List(_sectorSize);
  final hb = ByteData.sublistView(header);
  header.setRange(0, 8, const [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]);
  hb.setUint16(0x18, 0x003E, Endian.little); // إصدار فرعي
  hb.setUint16(0x1A, 0x0003, Endian.little); // إصدار رئيسي (قطاع 512)
  hb.setUint16(0x1C, 0xFFFE, Endian.little); // ترتيب البايتات
  hb.setUint16(0x1E, 9, Endian.little); // 2^9 = 512
  hb.setUint16(0x20, 6, Endian.little); // 2^6 = 64 للتدفّق المصغّر
  hb.setUint32(0x2C, 1, Endian.little); // عدد قطاعات FAT
  hb.setUint32(0x30, dirSector, Endian.little);
  hb.setUint32(0x38, _miniStreamCutoff, Endian.little);
  hb.setUint32(0x3C, _endOfChain, Endian.little); // أول قطاع mini-FAT
  hb.setUint32(0x40, 0, Endian.little); // عدد قطاعات mini-FAT
  hb.setUint32(0x44, _endOfChain, Endian.little); // أول قطاع DIFAT
  hb.setUint32(0x48, 0, Endian.little); // عدد قطاعات DIFAT
  for (var i = 0; i < 109; i++) {
    hb.setUint32(0x4C + i * 4, i == 0 ? fatSector : _freeSect, Endian.little);
  }

  // ── التجميع ──
  final out = BytesBuilder()..add(header);
  final fatBytes = Uint8List(_sectorSize);
  final fb = ByteData.sublistView(fatBytes);
  for (var i = 0; i < fat.length; i++) {
    fb.setUint32(i * 4, fat[i], Endian.little);
  }
  out.add(fatBytes);
  out.add(dir);
  out.add(padded);
  return out.toBytes();
}

// ═══════════════════════════════════════════════════════════════════════
// ملاحظة العربي — قيد خارج سيطرة هذا الملف
// ═══════════════════════════════════════════════════════════════════════
//
// الملف يخزّن العربي بـUTF-16 سليماً (تحقّقنا: `موز` = U+0645 0648 0632 في
// ملف تصدير حقيقي). لكن `mscale` عرضه `???` — بعدد حروف صحيح وشكل ضائع،
// وهي بصمة تطبيق ANSI يحوّل Unicode بترميز «اللغة للبرامج غير الـUnicode»
// في ويندوز، وهي ليست العربية على جهاز العميل.
//
// أي أن الخلل ليس في الملف ولا في هذا الكاتب. الحلّ المرجَّح إعداد ويندوز
// (Region → Administrative → Change system locale → Arabic ثم إعادة تشغيل).
// ويبقى سؤال مفتوح لا يحسمه إلا اختبار طباعة فعلي: هل خطوط الميزان نفسه
// تدعم العربية؟ إن لم تكن، فسقف هذه الموازين أسماء لاتينية مهما فعلنا.

/// يبني ملف عيّنة صغيراً لاختبار الاستيراد في `mscale`.
///
/// الصفوف مختارة لتغطية الحالات التي كانت مجهولة قبل تفكيك ملف العميل:
/// اسم عربي، سعر بكسور، صنف بالعدد، ووزن فارغ غير صفري، وكود بصفر بادئ.
Uint8List buildMerchandiseSampleXls() => buildMerchandiseXls(const [
      MerchandiseRow(
        pluNo: 1,
        name: 'موز',
        code: '2200081',
        price: 10.5,
        mode: MerchandiseMode.weight,
        shelfLife: 10,
        labelNo: 0,
        shopNo: 1,
      ),
      MerchandiseRow(
        pluNo: 2,
        name: 'برتقال',
        code: '2200082',
        price: 12.76,
        mode: MerchandiseMode.weight,
        shelfLife: 20,
        tare: 0.5,
        labelNo: 1,
        shopNo: 1,
      ),
      MerchandiseRow(
        pluNo: 3,
        name: 'Biscuit',
        code: '0065765',
        price: 3,
        mode: MerchandiseMode.countByPieces,
        shelfLife: 30,
        labelNo: 2,
        shopNo: 1,
      ),
    ]);
