// كان هذا الملف نسخةً حرفيةً من lib/presentation/screens/settings/scale_barcode_settings.dart
// (مصيدة النسخ §٥.٨). **انفصل عنها عمداً (2026-11-04)**: النسخةُ كانت تُخفي
// حقولَ البادئة/الخانات/المعامل خلف مفتاح «ميزان الوزن» داخل ExpansionTile
// مطويّ، فظهرت الشاشة «غير مفعّل» بمفتاحين بلا حقول (التحقّق الحيّ final3)،
// وكانت تفترض بادئة السعر 22 بينما المحلّل يفترض 20 ويجعل 22 بادئةَ وزنٍ بديلة.
//
// المنطقُ كلُّه (قراءة المفاتيح الأساسية + احتياط المفاتيح القديمة
// scale_barcode_prefix/scale_qty_* ، الحفظ، سجلّ التدقيق) انتقل إلى
// `ScaleBarcodeSettingsPanel` (lib/presentation/widgets/settings/) وقواعده إلى
// `ScaleBarcodeConfig` — لا شيء حُذف بلا بديل. أُبقي الاسم الخاص
// `_ScaleBarcodeSettings` لأن `settings_picpos_sections_core.dart` يستدعيه.
// الأصلُ القديم لـUralCash بقي كما هو (ملفه الأم `settings_screen.dart` في سقف
// file_size_ratchet، فلا يتّسع لسطر استيراد) — راجع
// docs/plans/2026-11-04-scale-barcode-settings-and-label.md.
part of 'settings_picpos_screen.dart';

class _ScaleBarcodeSettings extends StatelessWidget {
  const _ScaleBarcodeSettings();

  @override
  Widget build(BuildContext context) => const ScaleBarcodeSettingsPanel();
}
