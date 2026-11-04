// نشرُ القوالب الجاهزة المصحَّحة إلى قواعد البيانات **القائمة** — عند الإقلاع.
//
// ── فئةُ العطب ────────────────────────────────────────────────────────────
// إصلاحُ ملفّ أصولٍ (`assets/invoice_templates/*.json`) لا يصل ورقةً واحدة
// في قاعدةٍ قائمة: ما يُطبع هو **الصفُّ المخزَّن**. فإيصالُ المرتجع ٨٠مم خرج
// حيّاً بستّة أعمدةٍ متراكبةٍ بخطّ ١٢ (‏التحقّق الحيّ 2026-11-03) لأنّ القاعدةَ
// تحمل بذرةَ `_seedSalesReturnElements` القديمة — بينما الأصلُ المُصلَح بثلاثة
// أعمدةٍ لا يقرؤه إلّا من يستورده بيده. ومثلُه «ملصق ميزان» وقوالبُ 58mm/A5:
// منادي البذرة الوحيدُ شاشةُ المصمّم القديم المخفيّة، و«قالب جديد» يدويّ.
//
// ── القواعد ───────────────────────────────────────────────────────────────
// ١. **لا يُمحى عملُ مستخدم أبداً.** القالبُ المبذورُ يُستبدَل محتواه في
//    مكانه **فقط** إن طابقت بصمتُه البذرةَ القديمةَ المعروفة، وكانت مواضعُه
//    (‏إن هاجر إلى v2) هي عينَ ما تشتقّه الهجرةُ الآليّة — أي لم يُحرَّك فيه
//    شيء. وما عدا ذلك لا يُلمس، وتُضاف بجانبه نسخةٌ محدَّثةٌ باسمٍ مميّز.
// ٢. **بلا تكرار.** كلُّ بندٍ يُسجَّل في `ready_templates_delivered` بعد
//    تسليمه، فلا يعود قالبٌ حذفه المستخدمُ عمداً، ولا تتكرّر نسخة.
// ٣. **لا يُفسد قرارَ البذرة.** `seedDefaultTemplates` تحرس بالنوع والفئة
//    (‏`!existingTypes.contains('kitchen')`…). فإضافةُ «طلب مطبخ 58mm» إلى قاعدةٍ
//    لم تُبذر بعدُ كانت ستمنع بذرَ مطبخ 80mm إلى الأبد. لذا لا يُضاف قالبٌ
//    إلّا حين يكون نوعُه وفئتُه المحروسان موجودَين سلفاً؛ وإلّا يُؤجَّل.
// ٤. **لا يُنادى `seedDefaultTemplates` من هنا**: `_migrateOldFormatElements`
//    فيها تحوّل عنصرَ `company_name` في **ملصقات الباركود** (‏«ملصق كرتون
//    كبير») إلى `variable` فيطبعه راسمُ الملصقات نصّاً خاماً.
// ٥. لا تغييرَ مخطَّط: الأعمدةُ القائمةُ وحدَها، والسجلُّ في `app_settings`.

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../domain/printing/template_mapper.dart';
import '../../services/printing/template_render_pipeline.dart';
import 'database.dart';

/// يقرأ ملفّاً من `assets/invoice_templates/` — يُحقن في الاختبار.
typedef ReadyAssetLoader = Future<String> Function(String file);

/// مفتاحُ سجلّ التسليم في الإعدادات — قائمةُ JSON بمفاتيح البنود.
const kReadyTemplatesDeliveredKey = 'ready_templates_delivered';

/// قالبٌ مبذورٌ له نسخةٌ جاهزةٌ مصحَّحة.
class ReadyTemplateUpgrade {
  const ReadyTemplateUpgrade({
    required this.key,
    required this.seedName,
    required this.type,
    required this.category,
    required this.paperWidth,
    required this.assetFile,
    required this.legacyFingerprints,
    required this.copyName,
  });

  final String key;
  final String seedName;
  final String type;
  final String category;
  final double paperWidth;
  final String assetFile;

  /// بصماتُ البذرة القديمة المعروفة ([readyTemplateFingerprint]).
  final Set<String> legacyFingerprints;

  /// اسمُ النسخة المحدَّثة المضافة بجانب قالبٍ عدّله المستخدم.
  final String copyName;
}

/// بصمةُ «إيصال مرتجع مبيعات» كما تبذره `_seedSalesReturnElements` (‏v1،
/// وبعد الهجرة الآليّة إلى v2 بلا تغيير). يثبّتها
/// `ready_template_deployment_test` على البذرة الحيّة **وعلى صفّ قاعدة
/// sandbox** المصدَّر (‏`test/fixtures/sandbox_sales_return_template_*.json`).
const kLegacySalesReturn80Fingerprint =
    '96a2812a8efbef9728aa606e9cf761a5f0e622b2f2d8c28790ea501a042319ad';

const kReadyTemplateUpgrades = <ReadyTemplateUpgrade>[
  ReadyTemplateUpgrade(
    key: 'upgrade:sales_return_80mm@2026-11-03',
    seedName: 'إيصال مرتجع مبيعات',
    type: 'thermal',
    category: 'sales_return',
    paperWidth: 80,
    assetFile: 'thermal80_sales_return.json',
    legacyFingerprints: {kLegacySalesReturn80Fingerprint},
    copyName: 'إيصال مرتجع مبيعات — النسخة الجاهزة المحدثة',
  ),
];

/// قوالبُ الأصول التي تُضاف إن غابت (‏58mm وA5 المضافةُ في e7e2fb57).
const kReadyTemplateAdditions = <String>[
  'thermal58_sales_return.json',
  'thermal58_kitchen.json',
  'thermal58_shift_closing.json',
  'thermal58_purchase_invoice.json',
  'a5_sales_return.json',
  'a5_purchase_invoice.json',
];

/// ما تحرسه `seedDefaultTemplates` بالنوع وبالفئة — انظر القاعدة ٣.
const _seedGuardedTypes = {'thermal', 'kitchen', 'shift_closing'};
const _seedGuardedCategories = {
  'invoice',
  'sales_return',
  'purchase',
  'purchase_return',
  'barcode',
};

/// حصيلةُ تشغيلٍ واحد — للسجلّ والاختبار.
class ReadyTemplateDeploymentReport {
  final List<String> upgraded = [];
  final List<String> copied = [];
  final List<String> added = [];
  final List<String> deferred = [];
  final List<String> failed = [];

  bool get changed => upgraded.isNotEmpty || copied.isNotEmpty || added.isNotEmpty;

  @override
  String toString() =>
      'upgraded=$upgraded copied=$copied added=$added deferred=$deferred failed=$failed';
}

String _n(double v) => v.toStringAsFixed(2);
String _s(String? v) => v ?? '';

/// بصمةُ **ما يصل الورقة** من قالبٍ — لا معرِّفات ولا تواريخ ولا مواضعُ v2
/// (‏تلك تُفحص بـ[readyTemplatePositionsAreDerived]). و`section` خارجها عمداً:
/// الهجرةُ الآليّةُ تعيد كتابته إلى اسم النطاق، فتختلف بصمةُ قالبٍ لم يمسّه أحد.
String readyTemplateFingerprint(
  InvoiceTemplate t,
  List<InvoiceTemplateElement> elements,
  InvoiceTableSetting? s,
) {
  final b = StringBuffer()
    ..writeln(
      [t.type, t.templateCategory, _n(t.paperWidth), t.margins].join('|'),
    );
  final sorted = [...elements]
    ..sort((a, b) => a.sortOrder != b.sortOrder
        ? a.sortOrder.compareTo(b.sortOrder)
        : a.id.compareTo(b.id));
  for (final e in sorted) {
    b.writeln([
      e.sortOrder,
      e.rowIndex,
      e.elementType,
      _s(e.content),
      _s(e.labelAr),
      _s(e.labelEn),
      _n(e.fontSize),
      _s(e.fontFamily),
      e.isBold,
      e.isItalic,
      e.isVisible,
      e.textAlign,
      e.fontColor,
      _s(e.backgroundColor),
      _s(e.borderColor),
      _n(e.borderWidth),
      _n(e.flexWidth),
      _s(e.formula),
      _s(e.condition),
    ].join('|'));
  }
  if (s != null) {
    b.writeln([
      _n(s.fontSize),
      _n(s.headerFontSize),
      _n(s.rowHeight),
      s.showIndex,
      s.showProductCode,
      s.showProductName,
      s.showQuantity,
      s.showUnitPrice,
      s.showDiscount,
      s.showTax,
      s.showTotal,
      s.showUnit,
      s.showBarcode,
      s.showNotes,
      _s(s.columnWidths),
      _s(s.columnsJson),
      s.tableKind,
      s.headerBgColor,
      s.headerTextColor,
      _s(s.headerFontFamily),
      s.rowBgColor,
      _s(s.altRowBgColor),
    ].join('|'));
  }
  return sha256.convert(utf8.encode(b.toString())).toString();
}

/// هل مواضعُ القالب هي ما تشتقّه الهجرةُ الآليّة بالضبط؟
///
/// قالبٌ عند v1 لا مواضعَ له تصل الورقة (‏التدفّقُ لا يقرأ `x_position`)، فهو
/// «مشتقّ». وعند v2 تُعاد الاشتقاقةُ بالمُخطِّط نفسِه (‏`TemplateMigration`)
/// وتُقارَن: عنصرٌ سُحب في المحرّر أو ارتفاعُ نطاقٍ مخزَّن ⇒ عملُ مستخدم.
bool readyTemplatePositionsAreDerived(
  InvoiceTemplate t,
  List<InvoiceTemplateElement> elements,
  InvoiceTableSetting? s,
) {
  final anyPositioned = elements.any(
    (e) => e.bandId != null || e.xMm != null || e.yMm != null,
  );
  if (t.layoutVersion < kBandLayoutVersion && !anyPositioned) return true;
  if ((t.bandHeights ?? '').trim().isNotEmpty) return false;

  final paper = TemplateRenderPipeline.buildPaper(t);
  final document = TemplateMapper.fromLegacy(
    paper: paper,
    elements: [
      for (final e in elements)
        LegacyElement(
          elementType: e.elementType,
          content: e.content,
          section: e.section,
          sortOrder: e.sortOrder,
          flexWidth: e.flexWidth,
          fontSize: e.fontSize,
          isBold: e.isBold,
          isVisible: e.isVisible,
          labelAr: e.labelAr,
          labelEn: e.labelEn,
          textAlign: e.textAlign,
          fontColor: e.fontColor,
          condition: e.condition,
          sourceId: '${e.id}',
        ),
    ],
    table: TemplateRenderPipeline.buildTable(s, paper),
  );
  final derived = <int, (String, double, double, double, double)>{};
  for (final band in document.bands) {
    for (final el in band.elements) {
      final id = int.tryParse(el.id);
      if (id != null) derived[id] = (band.id.name, el.xMm, el.yMm, el.wMm, el.hMm);
    }
  }
  bool near(double? a, double b) => a != null && (a - b).abs() < 0.01;
  for (final e in elements) {
    final d = derived[e.id];
    if (d == null) {
      // عنصرٌ لا تشتقّه الهجرة (مخفيّ مثلاً) — مقبولٌ ما دام بلا مواضع.
      if (e.bandId != null || e.xMm != null) return false;
      continue;
    }
    if (e.bandId != d.$1 ||
        !near(e.xMm, d.$2) ||
        !near(e.yMm, d.$3) ||
        !near(e.wMm, d.$4) ||
        !near(e.hMm, d.$5)) {
      return false;
    }
  }
  return true;
}

extension ReadyTemplateDeployment on AppDatabase {
  /// متعادلةٌ ولا ترمي أبداً — تُنادى كلَّ إقلاعٍ من `database_startup.dart`.
  Future<ReadyTemplateDeploymentReport> deployReadyTemplates({
    ReadyAssetLoader? loadAsset,
  }) async {
    final report = ReadyTemplateDeploymentReport();
    final load = loadAsset ??
        (String f) => rootBundle.loadString('assets/invoice_templates/$f');
    try {
      // قاعدةٌ لم تُبذر قوالبُها بعد: البذرةُ صاحبةُ أوّل تعبئة (القاعدة ٣).
      if ((await getAllTemplates()).isEmpty) return report;
      final delivered = await _readDelivered();
      final before = delivered.length;

      for (final u in kReadyTemplateUpgrades) {
        if (delivered.contains(u.key)) continue;
        try {
          if (await _applyUpgrade(u, load, report)) delivered.add(u.key);
        } catch (e) {
          report.failed.add('${u.key}: $e');
        }
      }

      for (final file in kReadyTemplateAdditions) {
        final key = 'asset:$file';
        if (delivered.contains(key)) continue;
        try {
          if (await _applyAddition(file, load, report)) delivered.add(key);
        } catch (e) {
          report.failed.add('$key: $e');
        }
      }

      const scaleKey = 'seed:scale_label';
      if (!delivered.contains(scaleKey)) {
        if (await _seedGuardsAllow('thermal', 'barcode')) {
          final had = await _hasTemplate('ملصق ميزان', 'barcode');
          await seedScaleBarcodeTemplateIfMissing();
          if (!had) report.added.add('ملصق ميزان');
          delivered.add(scaleKey);
        } else {
          report.deferred.add(scaleKey);
        }
      }

      if (delivered.length != before) {
        await setSetting(
          kReadyTemplatesDeliveredKey,
          jsonEncode(delivered.toList()..sort()),
        );
      }
    } catch (e) {
      report.failed.add('$e');
    }
    if (report.changed || report.failed.isNotEmpty) {
      debugPrint('[Startup] ready templates: $report');
    }
    return report;
  }

  Future<Set<String>> _readDelivered() async {
    final raw = await getSettingValue(kReadyTemplatesDeliveredKey);
    if (raw == null || raw.trim().isEmpty) return <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return {for (final v in decoded) '$v'};
    } catch (_) {
      // سجلٌّ تالف لا يوقف الإقلاع — يُعاد بناؤه، والبنودُ متعادلةٌ بالاسم.
    }
    return <String>{};
  }

  Future<bool> _hasTemplate(String name, String category) async =>
      (await getAllTemplates())
          .any((t) => t.name == name && t.templateCategory == category);

  /// القاعدة ٣: إضافةُ قالبٍ بهذا النوع/الفئة لا تغيّر قرارَ البذرة.
  Future<bool> _seedGuardsAllow(String type, String category) async {
    final all = await getAllTemplates();
    if (_seedGuardedTypes.contains(type) && !all.any((t) => t.type == type)) {
      return false;
    }
    if (_seedGuardedCategories.contains(category) &&
        !all.any((t) => t.templateCategory == category)) {
      return false;
    }
    return true;
  }

  /// `true` ⇒ سُلِّم البند (رُقّي أو نُسخ أو لا حاجة)، `false` ⇒ يُؤجَّل.
  Future<bool> _applyUpgrade(
    ReadyTemplateUpgrade u,
    ReadyAssetLoader load,
    ReadyTemplateDeploymentReport report,
  ) async {
    final candidates = (await getAllTemplates())
        .where((t) =>
            t.type == u.type &&
            t.templateCategory == u.category &&
            (t.paperWidth - u.paperWidth).abs() < 0.01)
        .toList();
    // البذرةُ لم تُزرع بعد ⇒ يُؤجَّل حتى تُزرع (بالعناصر القديمة) فيُرقّى.
    if (candidates.isEmpty) {
      report.deferred.add(u.key);
      return false;
    }

    final asset = await load(u.assetFile);
    var needsCopy = false;
    for (final t in candidates) {
      final data = await getTemplateWithData(t.id);
      if (data == null) continue;
      final untouched =
          u.legacyFingerprints.contains(
            readyTemplateFingerprint(t, data.elements, data.tableSettings),
          ) &&
          readyTemplatePositionsAreDerived(
            t,
            data.elements,
            data.tableSettings,
          );
      if (untouched) {
        await replaceTemplateContentFromJson(t.id, asset);
        report.upgraded.add('${t.id}:${t.name}');
      } else if (t.name == u.seedName) {
        needsCopy = true;
      }
    }

    if (needsCopy && !await _hasTemplate(u.copyName, u.category)) {
      final data = jsonDecode(asset) as Map<String, dynamic>
        ..['name'] = u.copyName
        ..['templateCategory'] = u.category
        ..['type'] = u.type;
      await importTemplateFromJson(jsonEncode(data));
      report.copied.add(u.copyName);
    }
    return true;
  }

  Future<bool> _applyAddition(
    String file,
    ReadyAssetLoader load,
    ReadyTemplateDeploymentReport report,
  ) async {
    final raw = await load(file);
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final name = data['name'] as String? ?? file;
    final type = data['type'] as String? ?? 'thermal';
    final category = data['templateCategory'] as String? ?? 'receipt';
    if (await _hasTemplate(name, category)) return true;
    if (!await _seedGuardsAllow(type, category)) {
      report.deferred.add(file);
      return false;
    }
    await importTemplateFromJson(raw);
    report.added.add(name);
    return true;
  }
}
