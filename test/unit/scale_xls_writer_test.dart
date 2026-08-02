// إثبات مفهوم — كاتب ملف PLU لموازين NVK TMA و TEM (بلاغ العميل 2026-07-30).
//
// ## لماذا هذا الاختبار مهم أكثر من المعتاد
//
// الموازين عند العملاء فقط — لا وصول لأي جهاز أثناء التطوير. تحت هذا القيد
// كان كل تعريف بروتوكول في المشروع يُكتب من الافتراض ويُشحن بلا تحقّق، وهو
// السبب الجذري لأن رونجتا وحده يعمل: هو البراند الوحيد الذي كُتب من ملف
// تصدير حقيقي.
//
// تفكيك ملفَّي تصدير من البرنامج الرسمي `mscale` أعطانا الحقيقة الأرضية
// كاملة، وهذا الملف يقفل عليها: يفكّ الناتج بايتاً بايت ويقارنه بما رُصد في
// ملف العميل. أي انحراف يسقط هنا لا عند العميل.
//
// الحقيقة الأرضية المرجعية (من ملف تصدير حقيقي):
//   حاوية OLE2 · تدفّق `Workbook` بصيغة BIFF8 · ورقة `Merchandise`
//   الصف 0 ترويسة · تسعة أعمدة: PLU NO · Name · Code · Price · Mode ·
//   Shelflife · Tare · Label NO · Shop NO
//   `Name` و`Code` نص (SST) · الباقي أرقام
//   `Price` عملة عادية بكسور (10.5 · 12.76) بلا أي ضرب
//   `Mode` 0=وزن 1=عدد بالقطعة · العربي UTF-16 في الـSST

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ural_erp/services/scale_xls_writer.dart';

// ═══════════════════════════════════════════════════════════════════
// قارئ OLE2 + BIFF8 مصغّر — أداة تحقّق، ليست جزءاً من التطبيق
// ═══════════════════════════════════════════════════════════════════

class _Cell {
  final int row;
  final int col;
  final Object value; // String أو double
  const _Cell(this.row, this.col, this.value);
}

class _Sheet {
  final String name;
  final List<_Cell> cells;
  const _Sheet(this.name, this.cells);
}

int _u16(Uint8List b, int i) => b[i] | (b[i + 1] << 8);
int _u32(Uint8List b, int i) =>
    b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24);

/// يستخرج تدفّق `Workbook` من حاوية OLE2 باتّباع سلسلة FAT الحقيقية —
/// لا بافتراض أن التدفّق متّصل.
Uint8List _extractWorkbook(Uint8List file) {
  expect(file.sublist(0, 8),
      [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1],
      reason: 'توقيع OLE2 مفقود');
  final sectorSize = 1 << _u16(file, 0x1E);
  final firstFat = _u32(file, 0x4C);
  final dirStart = _u32(file, 0x30);

  final fat = <int>[];
  final fatOff = 512 + firstFat * sectorSize;
  for (var k = 0; k < sectorSize; k += 4) {
    fat.add(_u32(file, fatOff + k));
  }

  Uint8List chain(int start, int? limit) {
    final out = BytesBuilder();
    var s = start;
    var guard = 0;
    while (s >= 0 && s < fat.length && guard++ < 1000) {
      out.add(file.sublist(512 + s * sectorSize, 512 + (s + 1) * sectorSize));
      final next = fat[s];
      if (next >= 0xFFFFFFFA) break;
      s = next;
    }
    final bytes = out.toBytes();
    return limit == null ? bytes : bytes.sublist(0, limit);
  }

  final dir = chain(dirStart, null);
  for (var e = 0; (e + 1) * 128 <= dir.length; e++) {
    final o = e * 128;
    final nameLen = _u16(dir, o + 64);
    if (nameLen < 2 || nameLen > 64) continue;
    final sb = StringBuffer();
    for (var k = 0; k < nameLen - 2; k += 2) {
      sb.writeCharCode(dir[o + k] | (dir[o + k + 1] << 8));
    }
    if (sb.toString() == 'Workbook') {
      return chain(_u32(dir, o + 116), _u32(dir, o + 120));
    }
  }
  fail('لم يُعثر على تدفّق Workbook داخل الحاوية');
}

/// يفكّ سجلات BIFF8: SST + BOUNDSHEET + خلايا الورقة.
_Sheet _parseBiff(Uint8List wb) {
  final sst = <String>[];
  String? sheetName;
  int? sheetOffset;

  var pos = 0;
  while (pos + 4 <= wb.length) {
    final type = _u16(wb, pos);
    final len = _u16(wb, pos + 2);
    if (pos + 4 + len > wb.length) break;
    final d = pos + 4;

    if (type == 0x0085) {
      // BOUNDSHEET
      sheetOffset = _u32(wb, d);
      final cch = wb[d + 6];
      final flags = wb[d + 7];
      final sb = StringBuffer();
      if (flags & 1 != 0) {
        for (var i = 0; i < cch; i++) {
          sb.writeCharCode(_u16(wb, d + 8 + i * 2));
        }
      } else {
        for (var i = 0; i < cch; i++) {
          sb.writeCharCode(wb[d + 8 + i]);
        }
      }
      sheetName = sb.toString();
    } else if (type == 0x00FC) {
      // SST
      final unique = _u32(wb, d + 4);
      var q = d + 8;
      for (var n = 0; n < unique && q < d + len; n++) {
        final cch = _u16(wb, q);
        final flags = wb[q + 2];
        q += 3;
        final sb = StringBuffer();
        if (flags & 1 != 0) {
          for (var i = 0; i < cch; i++) {
            sb.writeCharCode(_u16(wb, q + i * 2));
          }
          q += cch * 2;
        } else {
          for (var i = 0; i < cch; i++) {
            sb.writeCharCode(wb[q + i]);
          }
          q += cch;
        }
        sst.add(sb.toString());
      }
    } else if (type == 0x000A && sheetOffset != null) {
      // نهاية الكتلة العامة — الورقة تبدأ عند إزاحة BOUNDSHEET
      break;
    }
    pos += 4 + len;
  }

  expect(sheetOffset, isNotNull, reason: 'BOUNDSHEET مفقود');
  final cells = <_Cell>[];
  pos = sheetOffset!;
  while (pos + 4 <= wb.length) {
    final type = _u16(wb, pos);
    final len = _u16(wb, pos + 2);
    if (pos + 4 + len > wb.length) break;
    final d = pos + 4;
    if (type == 0x00FD) {
      cells.add(_Cell(_u16(wb, d), _u16(wb, d + 2), sst[_u32(wb, d + 6)]));
    } else if (type == 0x0203) {
      final bd = ByteData.sublistView(wb, d + 6, d + 14);
      cells.add(_Cell(_u16(wb, d), _u16(wb, d + 2),
          bd.getFloat64(0, Endian.little)));
    } else if (type == 0x000A) {
      break;
    }
    pos += 4 + len;
  }
  return _Sheet(sheetName!, cells);
}

Object? _at(_Sheet s, int row, int col) {
  for (final c in s.cells) {
    if (c.row == row && c.col == col) return c.value;
  }
  return null;
}

void main() {
  group('الحاوية والبنية', () {
    test('ملف OLE2 صالح، وورقة اسمها Merchandise', () {
      final sheet = _parseBiff(_extractWorkbook(buildMerchandiseSampleXls()));
      // الاسم ليس تجميلياً: mscale يبحث عن هذه الورقة تحديداً.
      expect(sheet.name, kMerchandiseSheetName);
    });

    test('الترويسة تطابق ملف العميل حرفاً وترتيباً', () {
      final sheet = _parseBiff(_extractWorkbook(buildMerchandiseSampleXls()));
      for (var c = 0; c < kMerchandiseHeaders.length; c++) {
        expect(_at(sheet, 0, c), kMerchandiseHeaders[c],
            reason: 'العمود $c');
      }
      expect(kMerchandiseHeaders, [
        'PLU NO', 'Name', 'Code', 'Price', 'Mode',
        'Shelflife', 'Tare', 'Label NO', 'Shop NO',
      ]);
    });
  });

  group('أنواع القيم — حيث كانت الأخطاء الصامتة', () {
    late _Sheet sheet;
    setUp(() {
      sheet = _parseBiff(_extractWorkbook(buildMerchandiseSampleXls()));
    });

    test('Code نص لا رقم — الصفر البادئ محفوظ', () {
      // كتابته رقماً تحوّل 0065765 إلى 65765 ويفسد الباركود بصمت.
      final code = _at(sheet, 3, 2);
      expect(code, isA<String>());
      expect(code, '0065765');
    });

    test('Price عملة عادية بكسور — بلا أي ضرب', () {
      // كان مجهولاً قبل ملف العميل: خطأ في المقياس = أسعار ×100 أو ×1000.
      expect(_at(sheet, 1, 3), 10.5);
      expect(_at(sheet, 2, 3), 12.76);
    });

    test('Mode: 0 وزن · 1 عدد بالقطعة', () {
      expect(_at(sheet, 1, 4), 0.0);
      expect(_at(sheet, 3, 4), 1.0);
      expect(MerchandiseMode.weight, 0);
      expect(MerchandiseMode.countByPieces, 1);
    });

    test('Tare بكسور يمرّ سليماً', () {
      expect(_at(sheet, 2, 6), 0.5);
    });

    test('PLU NO رقم لا نص', () {
      expect(_at(sheet, 1, 0), isA<double>());
      expect(_at(sheet, 1, 0), 1.0);
    });
  });

  group('العربي', () {
    test('يُخزَّن UTF-16 سليماً بلا أي تلف', () {
      // الملف يحفظ العربي صحيحاً؛ ظهوره «???» في mscale سببه ترميز نظام
      // ويندوز للبرامج غير الـUnicode، لا هذا الملف.
      final sheet = _parseBiff(_extractWorkbook(buildMerchandiseSampleXls()));
      expect(_at(sheet, 1, 1), 'موز');
      expect(_at(sheet, 2, 1), 'برتقال');
      expect((_at(sheet, 1, 1)! as String).codeUnits, [0x0645, 0x0648, 0x0632]);
    });

    test('ASCII والعربي يتعايشان في نفس الجدول', () {
      final sheet = _parseBiff(_extractWorkbook(buildMerchandiseSampleXls()));
      expect(_at(sheet, 3, 1), 'Biscuit');
      expect(_at(sheet, 1, 1), 'موز');
    });
  });

  group('الحدود', () {
    test('قائمة فارغة تنتج ملفاً صالحاً بترويسة فقط', () {
      final sheet = _parseBiff(_extractWorkbook(buildMerchandiseXls(const [])));
      expect(sheet.name, kMerchandiseSheetName);
      expect(_at(sheet, 0, 0), 'PLU NO');
      expect(_at(sheet, 1, 0), isNull);
    });

    test('الأسماء المكرّرة تُخزَّن مرة واحدة وتظل صحيحة', () {
      final xls = buildMerchandiseXls(const [
        MerchandiseRow(pluNo: 1, name: 'تفاح', code: '1', price: 1),
        MerchandiseRow(pluNo: 2, name: 'تفاح', code: '2', price: 2),
      ]);
      final sheet = _parseBiff(_extractWorkbook(xls));
      expect(_at(sheet, 1, 1), 'تفاح');
      expect(_at(sheet, 2, 1), 'تفاح');
    });

    test('دفعة كبيرة ترمي رسالة مفهومة بدل ملف تالف', () {
      // سجل BIFF واحد لا يتجاوز 8224 بايت وسجلات CONTINUE غير مدعومة.
      // الفشل الصريح أفضل من ملف يبدو سليماً ويرفضه mscale بلا سبب.
      final many = List.generate(
        900,
        (i) => MerchandiseRow(
            pluNo: i + 1, name: 'صنف رقم $i', code: '$i', price: 1),
      );
      expect(() => buildMerchandiseXls(many), throwsA(isA<StateError>()));
    });

    test('التدفّق يتجاوز حدّ 4096 فيسكن جدول FAT العادي', () {
      // أصغر من ذلك يستلزم التدفّق المصغّر بجدوله المنفصل — غير مطبَّق.
      final bytes = buildMerchandiseSampleXls();
      expect(bytes.length, greaterThanOrEqualTo(512 * 3 + 4096));
    });
  });
}
