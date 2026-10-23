import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../screens/pos_terminals_screen.dart' show PosTerminalsBody;

/// نقاطُ البيع بترويسة PicPos الموحّدة (`HEADS.terminals` في ملفّ التصميم).
///
/// **قشرةٌ لا نسخة.** المنطقُ كلُّه في `PosTerminalsBody` المستوردةِ من
/// `screens/pos_terminals_screen.dart`، وتركبه قشرةُ UralCash هناك كما هي.
/// فلا نسخةَ ثانيةً تُصان ولا التزامَ تكافؤٍ جديد.
///
/// ⚠️ **ولا زرَّ CTA هنا عن قصد.** التصميمُ يعطي هذه الشاشةَ زرّاً اسمُه
/// «نقطة بيع جديدة»، وهو غيرُ قابلٍ للتنفيذ: صفُّ `pos_terminals` مفتاحُه
/// `deviceId` تولّده `DeviceIdentityService` على الجهاز نفسِه، ويُنشئ الصفَّ
/// `PosTerminalRegistrationService.registerIfNeeded()` عند أوّل تشغيل. فلا
/// معنى لإنشاء نقطةِ بيعٍ يدويّاً من جهازٍ آخر — والشاشةُ نفسُها تقول ذلك في
/// حالتها الفارغة: «تُسجَّل نقاط البيع تلقائياً أول مرة يفتح فيها كل جهاز».
/// حُذف الزرُّ بقرار المالك 2026-08-24؛ وزرٌّ لا يعمل أسوأُ من غيابه.
class PosTerminalsPicposScreen extends StatefulWidget {
  const PosTerminalsPicposScreen({super.key});

  @override
  State<PosTerminalsPicposScreen> createState() =>
      _PosTerminalsPicposScreenState();
}

class _PosTerminalsPicposScreenState extends State<PosTerminalsPicposScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PicPosScreenScaffold(
      title: tr('نقاط البيع'),
      subtitle: tr('الإعدادات ← الأجهزة والطباعة'),
      icon: PhosphorIconsBold.cashRegister,
      headerSearch: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _query = v),
        decoration: InputDecoration(
          isDense: true,
          hintText: tr('بحث باسم نقطة البيع...'),
          prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 16),
          suffixIcon: _query.isNotEmpty
              ? IconButton(
                  icon: const Icon(PhosphorIconsBold.x, size: 14),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _query = '');
                  },
                )
              : null,
        ),
      ),
      bodyPadding: EdgeInsets.zero,
      body: PosTerminalsBody(searchQuery: _query),
    );
  }
}
