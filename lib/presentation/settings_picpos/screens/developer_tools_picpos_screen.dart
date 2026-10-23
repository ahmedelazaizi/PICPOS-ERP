import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/config/business_profile_provider.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../screens/developer_tools_screen.dart'
    show DeveloperPasswordGate, DeveloperToolsPanels;

/// أدواتُ المطوّر بترويسة PicPos الموحّدة (`HEADS.devtools`).
///
/// **قشرةٌ لا نسخة**: اللوحاتُ في `DeveloperToolsPanels` والبوّابةُ هي
/// `DeveloperPasswordGate` نفسُها المستوردةُ من الملفّ المشترك — لا نسخةَ
/// ثانيةً من أيٍّ منهما.
///
/// ⚠️ **والبوّابةُ تلفّ اللوحاتِ هنا كما تلفّها هناك.** لو رُكّبت اللوحاتُ
/// بلا بوّابةٍ لانفتح تبديلُ نمطِ التشغيل وتصفيرُ البيانات بلا كلمةِ مرور —
/// وهي أخطرُ ما في الشاشة. ويحرسها `settings_devtools_gate_test`.
///
/// ولا زرَّ CTA — `HEADS.devtools` بلا `cta` أصلاً. وزرُّ «إنهاء الجلسة»
/// منقولٌ من `AppBar` المشتركة إلى `headerActions`.
class DeveloperToolsPicposScreen extends ConsumerStatefulWidget {
  const DeveloperToolsPicposScreen({super.key});

  @override
  ConsumerState<DeveloperToolsPicposScreen> createState() =>
      _DeveloperToolsPicposScreenState();
}

class _DeveloperToolsPicposScreenState
    extends ConsumerState<DeveloperToolsPicposScreen> {
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
      title: tr('أدوات المطور'),
      subtitle: tr('الإعدادات ← عن البرنامج'),
      icon: PhosphorIconsBold.code,
      headerSearch: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _query = v),
        decoration: InputDecoration(
          isDense: true,
          hintText: tr('بحث في الأدوات...'),
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
      headerActions: [
        IconButton(
          tooltip: tr('إنهاء الجلسة'),
          icon: const Icon(PhosphorIconsBold.signOut),
          onPressed: () {
            ref.read(developerSessionProvider.notifier).clear();
            if (Navigator.canPop(context)) Navigator.pop(context);
          },
        ),
      ],
      bodyPadding: EdgeInsets.zero,
      body: DeveloperPasswordGate(
        child: DeveloperToolsPanels(searchQuery: _query),
      ),
    );
  }
}
