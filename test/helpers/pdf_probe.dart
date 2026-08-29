// قراءةُ ما وصل الورقةَ فعلاً — لا ما نظنّه وصلها.
//
// ── لماذا ملفٌّ كامل لقراءة PDF ────────────────────────────────────────────
// راسمُ القوالبِ الحيُّ ٢٨٩٢ سطراً بلا شبكةِ أمان. وحراسُ المطبوع في هذا
// المستودع كلُّها **بنيويةٌ**: تقرأ المصدرَ وتؤكّد أن دالّةً تُنادى، ولا ترى
// ورقةً قطّ. فحين وصل بلاغُ «صفُّ عناوين الأعمدة لا يظهر» كذّب الرسمُ ثلاثَ
// فرضياتٍ معقولةٍ قبل أن يكشف السبب.
//
// وقبل نقلِ الراسم إلى المحرّك الجديد يلزم أن نعرف — بالقياس لا بالثقة — أن
// القوالبَ التسعةَ عشرَ تخرج كما كانت. فهذا يفكّ الوثيقةَ ويقرأ منها:
//   · عددَ الصفحات وقياسَها
//   · كلَّ نصٍّ بترتيبه ونقطتِه ووجهِ خطّه وحجمه
//   · كلَّ خطٍّ ومستطيلٍ يُرسم
//
// ⚠️ ولا يُقاس المطبوعُ ببصمةِ بايتات: حزمةُ `pdf` تكتب مُعرِّفَ وثيقةٍ
// مشتقّاً من الوقت، فنداءان لنفس المدخل يعطيان بايتاتٍ مختلفة. المقيسُ هنا
// **المحتوى والمواضع** وحدَها.
//
// ── ما يُفكّ ───────────────────────────────────────────────────────────────
// الحزمةُ تكتب: كائناتٍ غيرَ مضغوطةٍ بترويسةٍ نصّيّة، وتدفّقاتٍ بـFlateDecode،
// وخطوطَ Type0/Identity-H بجداول `/ToUnicode` من نوع `bfchar` وحدَه. وتدفّقُ
// المحتوى يستعمل مصفوفةَ CTM بـ`cm` داخلَ `q`/`Q`، ونصّاً بين `BT`/`ET`
// بإزاحةِ `Td`. كلُّ ذلك مقيسٌ على مخرَجٍ حقيقيٍّ لا مفترَض.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// نصٌّ كما وصل الورقة — بنقطته على الصفحة (الأصلُ أسفلَ اليسار، بالنقاط).
class PdfTextRun {
  final int page;
  final double x;
  final double y;
  final String font;
  final double size;
  final String text;

  const PdfTextRun({
    required this.page,
    required this.x,
    required this.y,
    required this.font,
    required this.size,
    required this.text,
  });
}

/// مستطيلٌ مرسوم (`re`) — إطارُ جدولٍ أو خلفيّةُ صفٍّ أو عنصرُ `rectangle`.
class PdfRectOp {
  final int page;
  final double x;
  final double y;
  final double w;
  final double h;

  const PdfRectOp({
    required this.page,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });
}

/// خطٌّ مرسوم (`m`…`l`) — فاصلٌ أو حدُّ عمود.
class PdfLineOp {
  final int page;
  final double x1;
  final double y1;
  final double x2;
  final double y2;

  const PdfLineOp({
    required this.page,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
  });
}

class PdfPageProbe {
  final int index;
  final double widthPts;
  final double heightPts;
  final List<PdfTextRun> texts;
  final List<PdfLineOp> lines;
  final List<PdfRectOp> rects;

  const PdfPageProbe({
    required this.index,
    required this.widthPts,
    required this.heightPts,
    required this.texts,
    required this.lines,
    required this.rects,
  });
}

class PdfProbe {
  final List<PdfPageProbe> pages;

  const PdfProbe(this.pages);

  int get pageCount => pages.length;

  /// كلُّ النصوص عبر الصفحات بترتيب الرسم.
  List<PdfTextRun> get allTexts => [for (final p in pages) ...p.texts];

  /// بصمةٌ نصّيّةٌ قابلةٌ للمقارنة والقراءة بالعين.
  ///
  /// التقريبُ إلى منزلتين (‏٠٫٠١ نقطة ≈ ٠٫٠٠٤ مم) — أدقُّ بمراتبَ من حدِّ
  /// «انزياحٍ أقلَّ من مليمتر»، فأيُّ فرقٍ ذي معنًى يظهر.
  String fingerprint({String? header}) {
    final b = StringBuffer();
    if (header != null) b.writeln(header);
    b.writeln('PAGES ${pages.length}');
    for (final p in pages) {
      b.writeln(
          'PAGE ${p.index} ${_n(p.widthPts)}x${_n(p.heightPts)}');
      for (final t in p.texts) {
        b.writeln('  TXT ${_n(t.x)},${_n(t.y)} ${t.font} ${_n(t.size)} '
            '«${t.text}»');
      }
      for (final l in p.lines) {
        b.writeln('  LIN ${_n(l.x1)},${_n(l.y1)} -> ${_n(l.x2)},${_n(l.y2)}');
      }
      for (final r in p.rects) {
        b.writeln('  REC ${_n(r.x)},${_n(r.y)} ${_n(r.w)}x${_n(r.h)}');
      }
    }
    return b.toString();
  }

  static String _n(double v) {
    // ‏`-0.00` و`0.00` نفسُ النقطة — التوحيدُ يمنع فرقاً وهمياً.
    final s = v.toStringAsFixed(2);
    return s == '-0.00' ? '0.00' : s;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// الفكّ
// ═══════════════════════════════════════════════════════════════════════════

PdfProbe probePdf(Uint8List bytes) => _PdfReader(bytes).read();

class _RawObject {
  final String dict;
  final int? streamStart;
  final int? streamEnd;
  const _RawObject(this.dict, this.streamStart, this.streamEnd);
}

class _FontInfo {
  final String baseFont;
  final Map<int, String> toUnicode;
  const _FontInfo(this.baseFont, this.toUnicode);
}

class _PdfReader {
  _PdfReader(this.bytes) : raw = latin1.decode(bytes, allowInvalid: true);

  final Uint8List bytes;
  final String raw;
  final Map<int, _RawObject> objects = {};

  PdfProbe read() {
    _indexObjects();
    final pageRefs = _pageRefs();
    final pages = <PdfPageProbe>[];
    for (var i = 0; i < pageRefs.length; i++) {
      final page = _readPage(pageRefs[i], i + 1);
      if (page != null) pages.add(page);
    }
    return PdfProbe(pages);
  }

  // ── فهرسةُ الكائنات ─────────────────────────────────────────────────────
  void _indexObjects() {
    final re = RegExp(r'(?:^|[\r\n])(\d+) 0 obj');
    for (final m in re.allMatches(raw)) {
      final num = int.parse(m.group(1)!);
      final bodyStart = m.end;
      final endObj = raw.indexOf('endobj', bodyStart);
      final streamKw = RegExp(r'stream\r?\n').firstMatch(
          raw.substring(bodyStart, endObj < 0 ? raw.length : endObj));
      if (streamKw == null) {
        objects[num] = _RawObject(
            raw.substring(bodyStart, endObj < 0 ? raw.length : endObj),
            null,
            null);
      } else {
        final sStart = bodyStart + streamKw.end;
        final sEnd = raw.indexOf('endstream', sStart);
        objects[num] = _RawObject(
            raw.substring(bodyStart, bodyStart + streamKw.start),
            sStart,
            sEnd < 0 ? raw.length : sEnd);
      }
    }
  }

  Uint8List? _streamOf(int objNum) {
    final o = objects[objNum];
    if (o == null || o.streamStart == null) return null;
    final data = bytes.sublist(o.streamStart!, o.streamEnd!);
    if (!o.dict.contains('FlateDecode')) return data;
    try {
      return Uint8List.fromList(ZLibDecoder().convert(data));
    } catch (_) {
      return null;
    }
  }

  // ── شجرةُ الصفحات ───────────────────────────────────────────────────────
  List<int> _pageRefs() {
    int? pagesRoot;
    for (final e in objects.entries) {
      if (e.value.dict.contains('/Type/Catalog')) {
        final m = RegExp(r'/Pages (\d+) 0 R').firstMatch(e.value.dict);
        if (m != null) pagesRoot = int.parse(m.group(1)!);
      }
    }
    if (pagesRoot == null) {
      // لا فهرس ⇒ خُذ كلَّ ما وسمُه صفحة، بترتيب رقم الكائن.
      return [
        for (final e in objects.entries)
          if (e.value.dict.contains('/Type/Page') &&
              !e.value.dict.contains('/Type/Pages'))
            e.key
      ]..sort();
    }
    final out = <int>[];
    _walkPages(pagesRoot, out, 0);
    return out;
  }

  void _walkPages(int node, List<int> out, int depth) {
    if (depth > 8) return;
    final o = objects[node];
    if (o == null) return;
    if (o.dict.contains('/Type/Page') && !o.dict.contains('/Type/Pages')) {
      out.add(node);
      return;
    }
    final kids = RegExp(r'/Kids\s*\[([^\]]*)\]').firstMatch(o.dict);
    if (kids == null) return;
    for (final m in RegExp(r'(\d+) 0 R').allMatches(kids.group(1)!)) {
      _walkPages(int.parse(m.group(1)!), out, depth + 1);
    }
  }

  PdfPageProbe? _readPage(int objNum, int index) {
    final o = objects[objNum];
    if (o == null) return null;

    var w = 0.0, h = 0.0;
    final mb = RegExp(
            r'/MediaBox\s*\[\s*(-?[\d.]+)\s+(-?[\d.]+)\s+(-?[\d.]+)\s+(-?[\d.]+)')
        .firstMatch(o.dict);
    if (mb != null) {
      w = double.parse(mb.group(3)!) - double.parse(mb.group(1)!);
      h = double.parse(mb.group(4)!) - double.parse(mb.group(2)!);
    }

    final fonts = _fontsOf(o.dict);

    final contentRefs = <int>[];
    final single = RegExp(r'/Contents (\d+) 0 R').firstMatch(o.dict);
    if (single != null) {
      contentRefs.add(int.parse(single.group(1)!));
    } else {
      final arr = RegExp(r'/Contents\s*\[([^\]]*)\]').firstMatch(o.dict);
      if (arr != null) {
        for (final m in RegExp(r'(\d+) 0 R').allMatches(arr.group(1)!)) {
          contentRefs.add(int.parse(m.group(1)!));
        }
      }
    }

    final buf = StringBuffer();
    for (final r in contentRefs) {
      final s = _streamOf(r);
      if (s != null) buf.write(latin1.decode(s, allowInvalid: true));
      buf.write('\n');
    }

    final interp = _ContentInterpreter(buf.toString(), fonts, index);
    interp.run();
    return PdfPageProbe(
      index: index,
      widthPts: w,
      heightPts: h,
      texts: interp.texts,
      lines: interp.lines,
      rects: interp.rects,
    );
  }

  Map<String, _FontInfo> _fontsOf(String pageDict) {
    final out = <String, _FontInfo>{};
    final fm = RegExp(r'/Font\s*<<(.*?)>>', dotAll: true).firstMatch(pageDict);
    if (fm == null) return out;
    for (final m in RegExp(r'/(\w+) (\d+) 0 R').allMatches(fm.group(1)!)) {
      final name = m.group(1)!;
      final ref = int.parse(m.group(2)!);
      final fd = objects[ref];
      if (fd == null) continue;
      final base = RegExp(r'/BaseFont/([\w+\-]+)').firstMatch(fd.dict);
      final tu = RegExp(r'/ToUnicode (\d+) 0 R').firstMatch(fd.dict);
      out[name] = _FontInfo(
        base?.group(1) ?? '?',
        tu == null ? const {} : _parseToUnicode(int.parse(tu.group(1)!)),
      );
    }
    return out;
  }

  Map<int, String> _parseToUnicode(int objNum) {
    final s = _streamOf(objNum);
    if (s == null) return const {};
    final txt = latin1.decode(s, allowInvalid: true);
    final map = <int, String>{};

    for (final block
        in RegExp(r'beginbfchar(.*?)endbfchar', dotAll: true).allMatches(txt)) {
      for (final m in RegExp(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>')
          .allMatches(block.group(1)!)) {
        map[int.parse(m.group(1)!, radix: 16)] = _utf16beToString(m.group(2)!);
      }
    }
    // ‏`bfrange` لا تكتبه الحزمةُ اليوم، ويُفكّ احتياطاً لو كتبته غداً.
    for (final block in RegExp(r'beginbfrange(.*?)endbfrange', dotAll: true)
        .allMatches(txt)) {
      for (final m in RegExp(
              r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>')
          .allMatches(block.group(1)!)) {
        final lo = int.parse(m.group(1)!, radix: 16);
        final hi = int.parse(m.group(2)!, radix: 16);
        final dst = int.parse(m.group(3)!, radix: 16);
        for (var c = lo; c <= hi && c - lo < 65536; c++) {
          map[c] = String.fromCharCode(dst + (c - lo));
        }
      }
    }
    return map;
  }

  static String _utf16beToString(String hex) {
    final units = <int>[];
    for (var i = 0; i + 3 < hex.length + 1; i += 4) {
      final chunk = hex.substring(i, i + 4 > hex.length ? hex.length : i + 4);
      if (chunk.length < 4) break;
      units.add(int.parse(chunk, radix: 16));
    }
    return String.fromCharCodes(units);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// مفسّرُ تدفّق المحتوى
// ═══════════════════════════════════════════════════════════════════════════

/// مصفوفةُ تحويلٍ مستوية `[a b c d e f]`.
typedef _M = List<double>;

_M _mul(_M m, _M n) => [
      m[0] * n[0] + m[1] * n[2],
      m[0] * n[1] + m[1] * n[3],
      m[2] * n[0] + m[3] * n[2],
      m[2] * n[1] + m[3] * n[3],
      m[4] * n[0] + m[5] * n[2] + n[4],
      m[4] * n[1] + m[5] * n[3] + n[5],
    ];

List<double> _apply(_M m, double x, double y) =>
    [x * m[0] + y * m[2] + m[4], x * m[1] + y * m[3] + m[5]];

class _ContentInterpreter {
  _ContentInterpreter(this.src, this.fonts, this.pageIndex);

  final String src;
  final Map<String, _FontInfo> fonts;
  final int pageIndex;

  final texts = <PdfTextRun>[];
  final lines = <PdfLineOp>[];
  final rects = <PdfRectOp>[];

  _M ctm = [1, 0, 0, 1, 0, 0];
  final _stack = <_M>[];
  _M tm = [1, 0, 0, 1, 0, 0];
  _M tlm = [1, 0, 0, 1, 0, 0];
  String curFont = '';
  double curSize = 0;

  // مسارُ الرسم الجاري — نقاطٌ بالفضاء الجهازيّ.
  final _path = <List<double>>[];

  void run() {
    final ops = <Object>[];
    for (final tok in _tokenize(src)) {
      if (tok is _Op) {
        _exec(tok.name, ops);
        ops.clear();
      } else {
        ops.add(tok);
        if (ops.length > 64) ops.removeAt(0);
      }
    }
  }

  double _num(Object? o) => o is num ? o.toDouble() : 0.0;

  void _exec(String op, List<Object> a) {
    switch (op) {
      case 'q':
        _stack.add(List<double>.from(ctm));
        break;
      case 'Q':
        if (_stack.isNotEmpty) ctm = _stack.removeLast();
        break;
      case 'cm':
        if (a.length >= 6) {
          final m = a.sublist(a.length - 6).map(_num).toList();
          ctm = _mul(m, ctm);
        }
        break;
      case 'BT':
        tm = [1, 0, 0, 1, 0, 0];
        tlm = [1, 0, 0, 1, 0, 0];
        break;
      case 'Tf':
        if (a.length >= 2) {
          final n = a[a.length - 2];
          curFont = n is _Name ? n.value : curFont;
          curSize = _num(a.last);
        }
        break;
      case 'Td':
      case 'TD':
        if (a.length >= 2) {
          final tx = _num(a[a.length - 2]);
          final ty = _num(a.last);
          tlm = _mul([1, 0, 0, 1, tx, ty], tlm);
          tm = List<double>.from(tlm);
        }
        break;
      case 'Tm':
        if (a.length >= 6) {
          tlm = a.sublist(a.length - 6).map(_num).toList();
          tm = List<double>.from(tlm);
        }
        break;
      case 'T*':
        tlm = _mul([1, 0, 0, 1, 0, -curSize], tlm);
        tm = List<double>.from(tlm);
        break;
      case 'Tj':
      case '\'':
      case '"':
        if (a.isNotEmpty) _emitText([a.last]);
        break;
      case 'TJ':
        if (a.isNotEmpty && a.last is List) {
          _emitText((a.last as List).cast<Object>());
        }
        break;
      case 'm':
      case 'l':
        if (a.length >= 2) {
          _path.add(_apply(ctm, _num(a[a.length - 2]), _num(a.last)));
        }
        break;
      case 're':
        if (a.length >= 4) {
          final x = _num(a[a.length - 4]);
          final y = _num(a[a.length - 3]);
          final w = _num(a[a.length - 2]);
          final h = _num(a.last);
          final p0 = _apply(ctm, x, y);
          final p1 = _apply(ctm, x + w, y + h);
          rects.add(PdfRectOp(
            page: pageIndex,
            x: p0[0] < p1[0] ? p0[0] : p1[0],
            y: p0[1] < p1[1] ? p0[1] : p1[1],
            w: (p1[0] - p0[0]).abs(),
            h: (p1[1] - p0[1]).abs(),
          ));
        }
        break;
      case 'S':
      case 's':
      case 'f':
      case 'F':
      case 'f*':
      case 'B':
      case 'B*':
      case 'b':
      case 'n':
        _flushPath();
        break;
      case 'W':
      case 'W*':
        // قصٌّ — لا يرسم، والمسارُ يُستهلك بـ`n` بعده.
        break;
    }
  }

  void _flushPath() {
    for (var i = 0; i + 1 < _path.length; i += 2) {
      lines.add(PdfLineOp(
        page: pageIndex,
        x1: _path[i][0],
        y1: _path[i][1],
        x2: _path[i + 1][0],
        y2: _path[i + 1][1],
      ));
    }
    _path.clear();
  }

  void _emitText(List<Object> parts) {
    final font = fonts[curFont];
    final b = StringBuffer();
    for (final p in parts) {
      if (p is _HexStr) {
        b.write(_decodeGlyphs(p.bytes, font));
      } else if (p is _LitStr) {
        b.write(p.value);
      }
    }
    var text = b.toString();
    if (text.isEmpty) return;
    text = _toLogicalOrder(text);
    final pos = _apply(_mul(tm, ctm), 0, 0);
    texts.add(PdfTextRun(
      page: pageIndex,
      x: pos[0],
      y: pos[1],
      font: font?.baseFont ?? curFont,
      size: curSize,
      text: text,
    ));
  }

  static String _decodeGlyphs(List<int> raw, _FontInfo? font) {
    final b = StringBuffer();
    for (var i = 0; i + 1 < raw.length; i += 2) {
      final cid = (raw[i] << 8) | raw[i + 1];
      final u = font?.toUnicode[cid];
      // بلا جدولٍ يُكتب المُعرِّفُ صراحةً — لا يُبتلع صامتاً.
      b.write(u ?? '\u{FFFD}[$cid]');
    }
    return b.toString();
  }

  /// الحزمةُ تكتب المقاطعَ العربيةَ **معكوسةً** (ترتيبُ العرض)، واللاتينيةَ
  /// كما هي. مقيسٌ على مخرَجٍ حقيقيّ: «جبنة» تخرج ة‌ن‌ب‌ج، و«251.00» تخرج
  /// كما تُقرأ. فالقلبُ يُطبَّق على المقاطع العربية وحدَها ليكون الملفُّ
  /// الذهبيُّ مقروءاً بالعين.
  static String _toLogicalOrder(String s) {
    final hasArabic = s.runes.any((r) =>
        (r >= 0x0600 && r <= 0x06FF) || (r >= 0xFB50 && r <= 0xFEFF));
    if (!hasArabic) return s;
    return String.fromCharCodes(s.runes.toList().reversed);
  }

  // ── التقطيع ────────────────────────────────────────────────────────────
  static Iterable<Object> _tokenize(String s) sync* {
    var i = 0;
    while (i < s.length) {
      final c = s[i];
      if (c == ' ' || c == '\n' || c == '\r' || c == '\t' || c == ' ') {
        i++;
        continue;
      }
      if (c == '%') {
        while (i < s.length && s[i] != '\n') {
          i++;
        }
        continue;
      }
      if (c == '/') {
        var j = i + 1;
        while (j < s.length && !_isDelim(s[j])) {
          j++;
        }
        yield _Name(s.substring(i + 1, j));
        i = j;
        continue;
      }
      if (c == '<' && i + 1 < s.length && s[i + 1] != '<') {
        final end = s.indexOf('>', i);
        if (end < 0) return;
        yield _HexStr(_hexBytes(s.substring(i + 1, end)));
        i = end + 1;
        continue;
      }
      if (c == '<') {
        // قاموسٌ داخل التدفّق (نادر) — تُقفز.
        final end = s.indexOf('>>', i);
        if (end < 0) return;
        i = end + 2;
        continue;
      }
      if (c == '(') {
        final sb = StringBuffer();
        var j = i + 1;
        var depth = 1;
        while (j < s.length) {
          final ch = s[j];
          if (ch == r'\') {
            if (j + 1 < s.length) sb.write(s[j + 1]);
            j += 2;
            continue;
          }
          if (ch == '(') depth++;
          if (ch == ')') {
            depth--;
            if (depth == 0) break;
          }
          sb.write(ch);
          j++;
        }
        yield _LitStr(sb.toString());
        i = j + 1;
        continue;
      }
      if (c == '[') {
        final inner = <Object>[];
        var j = i + 1;
        var depth = 1;
        while (j < s.length && depth > 0) {
          if (s[j] == '[') depth++;
          if (s[j] == ']') {
            depth--;
            if (depth == 0) break;
          }
          j++;
        }
        inner.addAll(_tokenize(s.substring(i + 1, j)));
        yield inner;
        i = j + 1;
        continue;
      }
      if (c == ']' || c == '{' || c == '}') {
        i++;
        continue;
      }
      // ⚠️ بلا `^`: ‏`matchAsPrefix` تُثبّت عند `i` بنفسها، و`^` داخلها تعني
      // **بدايةَ النصّ كلِّه** — فتفشل عند كلِّ رقمٍ بعد أوّل محرف. وأثرُها
      // صامتٌ وقاتل: الرقمُ يصير «معاملاً» فيمسح مكدّسَ المعاملات قبل أن
      // يقرأه `Tf`/`Td`/`cm`، فتخرج النصوصُ كلُّها عند (٠،٠) بلا وجهٍ ولا
      // حجم — وهو ما حدث فعلاً في أوّل تشغيل.
      final numM =
          RegExp(r'[+-]?(?:\d+\.?\d*|\.\d+)').matchAsPrefix(s, i);
      if (numM != null && numM.end > i) {
        yield double.parse(numM.group(0)!);
        i = numM.end;
        continue;
      }
      var j = i;
      while (j < s.length && !_isDelim(s[j])) {
        j++;
      }
      if (j == i) j = i + 1;
      yield _Op(s.substring(i, j));
      i = j;
    }
  }

  static bool _isDelim(String c) =>
      c == ' ' ||
      c == '\n' ||
      c == '\r' ||
      c == '\t' ||
      c == ' ' ||
      c == '/' ||
      c == '[' ||
      c == ']' ||
      c == '<' ||
      c == '>' ||
      c == '(' ||
      c == ')' ||
      c == '{' ||
      c == '}' ||
      c == '%';

  static List<int> _hexBytes(String hex) {
    final clean = hex.replaceAll(RegExp(r'\s'), '');
    final out = <int>[];
    for (var i = 0; i < clean.length; i += 2) {
      final pair =
          i + 2 <= clean.length ? clean.substring(i, i + 2) : '${clean[i]}0';
      final v = int.tryParse(pair, radix: 16);
      if (v != null) out.add(v);
    }
    return out;
  }
}

class _Op {
  final String name;
  const _Op(this.name);
}

class _Name {
  final String value;
  const _Name(this.value);
}

class _HexStr {
  final List<int> bytes;
  const _HexStr(this.bytes);
}

class _LitStr {
  final String value;
  const _LitStr(this.value);
}
